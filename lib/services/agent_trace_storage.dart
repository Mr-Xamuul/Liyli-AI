import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/agent_execution_trace.dart';
import '../models/agent_tool_config.dart';
import 'ai_admin_settings_storage.dart';
import 'supabase_config.dart';

class AgentTraceSummary {
  const AgentTraceSummary({
    required this.totalTraces,
    required this.confirmedCount,
    required this.rejectedCount,
    required this.pendingCount,
    required this.failedCount,
    required this.averageLatencyMs,
    required this.toolUsageCounts,
  });

  final int totalTraces;
  final int confirmedCount;
  final int rejectedCount;
  final int pendingCount;
  final int failedCount;
  final int averageLatencyMs;
  final Map<String, int> toolUsageCounts;

  double get confirmedRate =>
      totalTraces > 0 ? (confirmedCount / totalTraces) * 100 : 0.0;
}

class AgentTraceStorage {
  AgentTraceStorage._();
  static final AgentTraceStorage instance = AgentTraceStorage._();

  static const _tracesKey = 'leyli_agent_execution_traces_v1';
  static const _toolsKey = 'leyli_agent_tool_configs_v1';
  static const int _maxStoredTraces = 500;

  final ValueNotifier<int> tracesCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<List<AgentLiveExecution>> liveExecutionsNotifier =
      ValueNotifier<List<AgentLiveExecution>>([]);
  final AiAdminSettingsStorage _settings = const AiAdminSettingsStorage();
  bool _liveMonitoringStarted = false;
  Future<void> _liveWriteQueue = Future<void>.value();
  final Map<String, Timer> _liveHeartbeats = {};

  // ---------------------------------------------------------------------------
  // Live Agent Execution In-Flight Tracking
  // ---------------------------------------------------------------------------

  Future<void> startLiveExecutionMonitoring() async {
    if (!SupabaseConfig.isInitialized) return;
    if (_liveMonitoringStarted) return;
    _liveMonitoringStarted = true;
    await refreshLiveExecutions();
    SupabaseConfig.client
        .channel('agent-live-executions-admin')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'agent_live_executions',
          callback: (_) => unawaited(refreshLiveExecutions()),
        )
        .subscribe();
  }

  Future<void> refreshLiveExecutions() async {
    if (!SupabaseConfig.isInitialized ||
        SupabaseConfig.client.auth.currentUser == null) {
      return;
    }
    try {
      final staleBefore = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 45))
          .toIso8601String();
      await SupabaseConfig.client
          .from('agent_live_executions')
          .delete()
          .lt('updated_at', staleBefore);
      final rows = await SupabaseConfig.client
          .from('agent_live_executions')
          .select('execution_data')
          .gte('updated_at', staleBefore)
          .order('updated_at', ascending: false)
          .limit(20);
      final live = rows
          .map((row) => row['execution_data'])
          .whereType<Map<String, dynamic>>()
          .map(AgentLiveExecution.fromJson)
          .where((execution) => !execution.isCompleted)
          .toList();
      liveExecutionsNotifier.value = live;
    } catch (error) {
      debugPrint('Could not load live Agent executions: $error');
    }
  }

  void _queueLiveWrite(Future<void> Function() operation) {
    if (!SupabaseConfig.isInitialized) return;
    _liveWriteQueue = _liveWriteQueue.then((_) => operation()).catchError((
      Object error,
    ) {
      // Live monitoring must never interrupt a student's AI response.
      debugPrint('Could not sync live Agent execution: $error');
    });
  }

  Future<void> _upsertLiveExecution(AgentLiveExecution execution) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;
    await SupabaseConfig.client.from('agent_live_executions').upsert({
      'user_id': user.id,
      'execution_id': execution.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'execution_data': execution.toJson(),
    }, onConflict: 'user_id,execution_id');
  }

  Future<void> _deleteLiveExecution(String id) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;
    await SupabaseConfig.client
        .from('agent_live_executions')
        .delete()
        .eq('user_id', user.id)
        .eq('execution_id', id);
  }

  void startLiveExecution(AgentLiveExecution execution) {
    final list = List<AgentLiveExecution>.from(liveExecutionsNotifier.value);
    list.removeWhere((e) => e.id == execution.id);
    list.insert(0, execution);
    // Keep max 20 recent live executions
    if (list.length > 20) {
      list.removeRange(20, list.length);
    }
    liveExecutionsNotifier.value = list;
    _queueLiveWrite(() => _upsertLiveExecution(execution));
    _liveHeartbeats.remove(execution.id)?.cancel();
    if (SupabaseConfig.isInitialized) {
      _liveHeartbeats[execution.id] = Timer.periodic(
        const Duration(seconds: 10),
        (_) {
          for (final current in liveExecutionsNotifier.value) {
            if (current.id == execution.id) {
              _queueLiveWrite(() => _upsertLiveExecution(current));
              break;
            }
          }
        },
      );
    }
  }

  void updateLiveExecution({
    required String id,
    String? currentStatus,
    String? activeStepName,
    String? currentModelName,
    AgentToolCallLog? addToolCall,
    AgentModelCallLog? addModelCall,
    bool? isCompleted,
    bool? isSuccess,
    String? finalAnswer,
    String? errorMessage,
  }) {
    final list = List<AgentLiveExecution>.from(liveExecutionsNotifier.value);
    final idx = list.indexWhere((e) => e.id == id);
    if (idx != -1) {
      final item = list[idx].copy();
      if (currentStatus != null) item.currentStatus = currentStatus;
      if (activeStepName != null) item.activeStepName = activeStepName;
      if (currentModelName != null) item.currentModelName = currentModelName;
      if (addToolCall != null) item.toolCalls.add(addToolCall);
      if (addModelCall != null) item.modelCalls.add(addModelCall);
      if (isCompleted != null) item.isCompleted = isCompleted;
      if (isSuccess != null) item.isSuccess = isSuccess;
      if (finalAnswer != null) item.finalAnswer = finalAnswer;
      if (errorMessage != null) item.errorMessage = errorMessage;
      list[idx] = item;
      liveExecutionsNotifier.value = list;
      _queueLiveWrite(() => _upsertLiveExecution(item));
    }
  }

  void finishLiveExecution(
    String id, {
    bool success = true,
    String? finalAnswer,
    String? errorMessage,
  }) {
    final list = List<AgentLiveExecution>.from(liveExecutionsNotifier.value);
    final idx = list.indexWhere((e) => e.id == id);
    if (idx != -1) {
      _liveHeartbeats.remove(id)?.cancel();
      list.removeAt(idx);
      liveExecutionsNotifier.value = list;
      _queueLiveWrite(() => _deleteLiveExecution(id));
    }
  }

  void removeLiveExecution(String id) {
    _liveHeartbeats.remove(id)?.cancel();
    final list = List<AgentLiveExecution>.from(liveExecutionsNotifier.value);
    list.removeWhere((e) => e.id == id);
    liveExecutionsNotifier.value = list;
    _queueLiveWrite(() => _deleteLiveExecution(id));
  }

  // ---------------------------------------------------------------------------
  // Trace Logging & Retrieval
  // ---------------------------------------------------------------------------

  Future<List<AgentExecutionTrace>> getTraces() async {
    if (SupabaseConfig.isInitialized) {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        tracesCountNotifier.value = 0;
        return [];
      }
      try {
        final rows = await SupabaseConfig.client
            .from('agent_execution_traces')
            .select('record_data')
            .order('created_at', ascending: false)
            .limit(_maxStoredTraces);
        final traces = rows
            .map((row) => row['record_data'])
            .whereType<Map<String, dynamic>>()
            .map(AgentExecutionTrace.fromJson)
            .toList();
        tracesCountNotifier.value = traces.length;
        return traces;
      } catch (error) {
        debugPrint('Could not load agent traces from Supabase: $error');
        tracesCountNotifier.value = 0;
        return [];
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tracesKey);
    if (raw == null || raw.trim().isEmpty) {
      tracesCountNotifier.value = 0;
      return [];
    }

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final traces = list
          .whereType<Map<String, dynamic>>()
          .map(AgentExecutionTrace.fromJson)
          .toList();
      traces.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      tracesCountNotifier.value = traces.length;
      return traces;
    } catch (_) {
      tracesCountNotifier.value = 0;
      return [];
    }
  }

  Future<void> recordTrace(AgentExecutionTrace trace) async {
    if (SupabaseConfig.isInitialized) {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return;
      try {
        await SupabaseConfig.client.from('agent_execution_traces').upsert({
          'user_id': user.id,
          'trace_id': trace.id,
          'created_at': trace.timestamp.toUtc().toIso8601String(),
          'record_data': trace.toJson(),
        }, onConflict: 'user_id,trace_id');
        tracesCountNotifier.value = (tracesCountNotifier.value + 1).clamp(
          0,
          _maxStoredTraces,
        );
      } catch (error) {
        // Monitoring must not interrupt a student's AI response.
        debugPrint('Could not save agent trace to Supabase: $error');
      }
      return;
    }

    final current = await getTraces();
    // Prepend new trace
    final updated = [trace, ...current];
    if (updated.length > _maxStoredTraces) {
      updated.removeRange(_maxStoredTraces, updated.length);
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(updated.map((t) => t.toJson()).toList());
    await prefs.setString(_tracesKey, raw);
    tracesCountNotifier.value = updated.length;
  }

  Future<void> updateTraceFeedback({
    required String traceId,
    required bool isConfirmed,
    required String studentFeedback,
    String? reasoningUpdate,
  }) async {
    if (SupabaseConfig.isInitialized) {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return;
      try {
        final row = await SupabaseConfig.client
            .from('agent_execution_traces')
            .select('record_data')
            .eq('user_id', user.id)
            .eq('trace_id', traceId)
            .maybeSingle();
        final data = row?['record_data'];
        if (data is! Map<String, dynamic>) return;
        final target = AgentExecutionTrace.fromJson(data);
        final updatedTrace = _withFeedback(
          target,
          isConfirmed: isConfirmed,
          studentFeedback: studentFeedback,
          reasoningUpdate: reasoningUpdate,
        );
        await SupabaseConfig.client
            .from('agent_execution_traces')
            .update({'record_data': updatedTrace.toJson()})
            .eq('user_id', user.id)
            .eq('trace_id', traceId);
      } catch (error) {
        debugPrint('Could not update agent feedback in Supabase: $error');
      }
      return;
    }

    final current = await getTraces();
    final index = current.indexWhere((t) => t.id == traceId);
    if (index == -1) return;

    final target = current[index];
    final updatedThought =
        (reasoningUpdate != null && reasoningUpdate.isNotEmpty)
        ? '${target.internalThought} -> Feedback: $reasoningUpdate'
        : target.internalThought;

    final updatedTrace = target.copyWith(
      status: isConfirmed
          ? AgentVerificationStatus.accepted
          : AgentVerificationStatus.rejected,
      studentFeedback: studentFeedback,
      feedbackTimestamp: DateTime.now(),
      internalThought: updatedThought,
    );

    current[index] = updatedTrace;

    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(current.map((t) => t.toJson()).toList());
    await prefs.setString(_tracesKey, raw);
  }

  Future<void> clearTraces() async {
    if (SupabaseConfig.isInitialized) {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return;
      await SupabaseConfig.client
          .from('agent_execution_traces')
          .delete()
          .neq('trace_id', '');
      tracesCountNotifier.value = 0;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tracesKey);
    tracesCountNotifier.value = 0;
  }

  Future<AgentTraceSummary> getSummary() async {
    final traces = await getTraces();
    if (traces.isEmpty) {
      return const AgentTraceSummary(
        totalTraces: 0,
        confirmedCount: 0,
        rejectedCount: 0,
        pendingCount: 0,
        failedCount: 0,
        averageLatencyMs: 0,
        toolUsageCounts: {},
      );
    }

    int confirmed = 0;
    int rejected = 0;
    int pending = 0;
    int failed = 0;
    int totalLatency = 0;
    final Map<String, int> toolUsage = {};

    for (final trace in traces) {
      totalLatency += trace.totalLatencyMs;
      switch (trace.status) {
        case AgentVerificationStatus.accepted:
          confirmed++;
          break;
        case AgentVerificationStatus.rejected:
          rejected++;
          break;
        case AgentVerificationStatus.pendingConfirmation:
        case AgentVerificationStatus.searching:
          pending++;
          break;
        case AgentVerificationStatus.failed:
          failed++;
          break;
      }

      for (final tool in trace.toolCalls) {
        toolUsage[tool.toolId] = (toolUsage[tool.toolId] ?? 0) + 1;
      }
    }

    return AgentTraceSummary(
      totalTraces: traces.length,
      confirmedCount: confirmed,
      rejectedCount: rejected,
      pendingCount: pending,
      failedCount: failed,
      averageLatencyMs: (totalLatency / traces.length).round(),
      toolUsageCounts: toolUsage,
    );
  }

  // ---------------------------------------------------------------------------
  // Agent Tools Config Management
  // ---------------------------------------------------------------------------

  Future<List<AgentToolConfig>> getToolConfigs() async {
    final String? raw;
    if (SupabaseConfig.isInitialized) {
      raw = await _settings.getString(_toolsKey);
    } else {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(_toolsKey);
    }
    if (raw == null || raw.trim().isEmpty) {
      // First run: save and return defaults
      final defaults = AgentToolConfig.defaultTools;
      if (!SupabaseConfig.isInitialized || await _isAdmin()) {
        await saveToolConfigs(defaults);
      }
      return defaults;
    }

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final configs = list
          .whereType<Map<String, dynamic>>()
          .map(AgentToolConfig.fromJson)
          .toList();

      // Upgrade old confirmation-gate registry entries to the tool-call
      // workflow while preserving each tool's admin enabled/disabled setting.
      var changed = false;
      for (final migration in const {
        'curriculum_search': 'search_curriculum',
        'pdf_retriever': 'get_lesson_pdf',
      }.entries) {
        final oldIndex = configs.indexWhere((c) => c.id == migration.key);
        final newIndex = configs.indexWhere((c) => c.id == migration.value);
        if (oldIndex >= 0 && newIndex < 0) {
          configs[oldIndex] = configs[oldIndex].copyWith(id: migration.value);
          changed = true;
        } else if (oldIndex >= 0) {
          configs.removeAt(oldIndex);
          changed = true;
        }
      }
      final oldLength = configs.length;
      configs.removeWhere((c) => c.id == 'verification_gate');
      changed = changed || configs.length != oldLength;
      for (final def in AgentToolConfig.defaultTools) {
        final index = configs.indexWhere((c) => c.id == def.id);
        if (index < 0) {
          configs.add(def);
          changed = true;
        } else {
          final upgraded = def.copyWith(isEnabled: configs[index].isEnabled);
          if (configs[index].name != upgraded.name ||
              configs[index].somaliTitle != upgraded.somaliTitle ||
              configs[index].description != upgraded.description ||
              configs[index].category != upgraded.category ||
              jsonEncode(configs[index].parameters) !=
                  jsonEncode(upgraded.parameters)) {
            configs[index] = upgraded;
            changed = true;
          }
        }
      }
      if (changed && (!SupabaseConfig.isInitialized || await _isAdmin())) {
        await saveToolConfigs(configs);
      }
      return configs;
    } catch (_) {
      return AgentToolConfig.defaultTools;
    }
  }

  Future<void> saveToolConfigs(List<AgentToolConfig> configs) async {
    final raw = jsonEncode(configs.map((c) => c.toJson()).toList());
    if (SupabaseConfig.isInitialized) {
      await _settings.setString(_toolsKey, raw);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_toolsKey, raw);
    }
  }

  Future<void> toggleTool(String toolId, bool isEnabled) async {
    final configs = await getToolConfigs();
    final index = configs.indexWhere((c) => c.id == toolId);
    if (index != -1) {
      configs[index] = configs[index].copyWith(isEnabled: isEnabled);
      await saveToolConfigs(configs);
    }
  }

  Future<bool> isToolEnabled(String toolId) async {
    final configs = await getToolConfigs();
    final tool = configs.firstWhere(
      (c) => c.id == toolId,
      orElse: () => AgentToolConfig(
        id: toolId,
        name: toolId,
        somaliTitle: toolId,
        description: '',
        isEnabled: true,
      ),
    );
    return tool.isEnabled;
  }

  AgentExecutionTrace _withFeedback(
    AgentExecutionTrace target, {
    required bool isConfirmed,
    required String studentFeedback,
    String? reasoningUpdate,
  }) {
    final updatedThought =
        (reasoningUpdate != null && reasoningUpdate.isNotEmpty)
        ? '${target.internalThought} -> Feedback: $reasoningUpdate'
        : target.internalThought;
    return target.copyWith(
      status: isConfirmed
          ? AgentVerificationStatus.accepted
          : AgentVerificationStatus.rejected,
      studentFeedback: studentFeedback,
      feedbackTimestamp: DateTime.now(),
      internalThought: updatedThought,
    );
  }

  Future<bool> _isAdmin() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return false;
    final row = await SupabaseConfig.client
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    return row?['role'] == 'admin';
  }
}
