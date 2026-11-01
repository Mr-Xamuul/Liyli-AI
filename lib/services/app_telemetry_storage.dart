import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_telemetry_log.dart';
import 'supabase_config.dart';

class AppTelemetryStorage {
  AppTelemetryStorage._();
  static final AppTelemetryStorage instance = AppTelemetryStorage._();

  static const _prefKey = 'leyli_app_telemetry_logs_v1';
  static const int _maxStoredLogs = 1500;

  final ValueNotifier<int> logsCountNotifier = ValueNotifier<int>(0);

  Future<List<AppTelemetryLog>> getLogs() async {
    if (SupabaseConfig.isInitialized) {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        logsCountNotifier.value = 0;
        return [];
      }
      try {
        final rows = await SupabaseConfig.client
            .from('app_telemetry_logs')
            .select('log_data')
            .order('created_at', ascending: false)
            .limit(_maxStoredLogs);
        final logs = rows
            .map((row) => row['log_data'])
            .whereType<Map<String, dynamic>>()
            .map(AppTelemetryLog.fromJson)
            .toList();
        logsCountNotifier.value = logs.length;
        return logs;
      } catch (error) {
        debugPrint('Could not load app telemetry from Supabase: $error');
        logsCountNotifier.value = 0;
        return [];
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null || raw.trim().isEmpty) {
      logsCountNotifier.value = 0;
      return [];
    }

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final logs = list
          .whereType<Map<String, dynamic>>()
          .map(AppTelemetryLog.fromJson)
          .toList();
      logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      logsCountNotifier.value = logs.length;
      return logs;
    } catch (_) {
      logsCountNotifier.value = 0;
      return [];
    }
  }

  Future<void> recordLog(AppTelemetryLog log) async {
    if (SupabaseConfig.isInitialized) {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return;
      try {
        await SupabaseConfig.client.from('app_telemetry_logs').upsert({
          'user_id': user.id,
          'log_id': log.id,
          'created_at': log.timestamp.toUtc().toIso8601String(),
          'log_data': log.toJson(),
        }, onConflict: 'user_id,log_id');
        logsCountNotifier.value = (logsCountNotifier.value + 1).clamp(
          0,
          _maxStoredLogs,
        );
      } catch (error) {
        // Telemetry is best-effort and must not interrupt chat responses.
        debugPrint('Could not save app telemetry to Supabase: $error');
      }
      return;
    }

    final current = await getLogs();
    final updated = [log, ...current];
    if (updated.length > _maxStoredLogs) {
      updated.removeRange(_maxStoredLogs, updated.length);
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(updated.map((l) => l.toJson()).toList());
    await prefs.setString(_prefKey, raw);
    logsCountNotifier.value = updated.length;
  }

  Future<void> clearLogs() async {
    if (SupabaseConfig.isInitialized) {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return;
      await SupabaseConfig.client
          .from('app_telemetry_logs')
          .delete()
          .neq('log_id', '');
      logsCountNotifier.value = 0;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    logsCountNotifier.value = 0;
  }

  Future<TelemetrySummary> getSummary() async {
    final logs = await getLogs();
    return computeSummary(logs);
  }

  static TelemetrySummary computeSummary(List<AppTelemetryLog> logs) {
    int totalSuccess = 0;
    int totalFailed = 0;
    int totalModelFailures = 0;
    int latencySum = 0;
    int latencyCount = 0;

    final modelSuccessCounts = <String, int>{};
    final modelFailureCounts = <String, int>{};
    final modelLatencySums = <String, int>{};
    final modelLatencyCounts = <String, int>{};
    final bookUsageCounts = <String, int>{};
    final recentFailures = <ModelAttemptLog>[];

    for (final log in logs) {
      if (log.isSuccess) {
        totalSuccess++;
        if (log.responseTimeMs != null && log.responseTimeMs! > 0) {
          latencySum += log.responseTimeMs!;
          latencyCount++;

          final modelKey = log.answeredModelName ?? 'Aqoonta AI';
          modelSuccessCounts[modelKey] =
              (modelSuccessCounts[modelKey] ?? 0) + 1;
          modelLatencySums[modelKey] =
              (modelLatencySums[modelKey] ?? 0) + log.responseTimeMs!;
          modelLatencyCounts[modelKey] =
              (modelLatencyCounts[modelKey] ?? 0) + 1;
        }
      } else {
        totalFailed++;
      }

      // Track book context usage
      final bookKey =
          (log.bookTitle != null && log.bookTitle!.trim().isNotEmpty)
          ? log.bookTitle!
          : 'Guud (General Chat)';
      bookUsageCounts[bookKey] = (bookUsageCounts[bookKey] ?? 0) + 1;

      // Track individual model attempts and failures
      for (final attempt in log.attempts) {
        if (!attempt.isSuccess) {
          totalModelFailures++;
          final mKey = attempt.modelName.isNotEmpty
              ? attempt.modelName
              : 'Unknown Model';
          modelFailureCounts[mKey] = (modelFailureCounts[mKey] ?? 0) + 1;
          if (recentFailures.length < 20) {
            recentFailures.add(attempt);
          }
        }
      }
    }

    final modelAvgLatencies = <String, double>{};
    for (final entry in modelLatencySums.entries) {
      final count = modelLatencyCounts[entry.key] ?? 1;
      modelAvgLatencies[entry.key] = entry.value / count;
    }

    final avgLatencyMs = latencyCount > 0 ? (latencySum / latencyCount) : 0.0;

    return TelemetrySummary(
      totalMessages: logs.length,
      totalSuccess: totalSuccess,
      totalFailed: totalFailed,
      totalModelFailures: totalModelFailures,
      avgLatencyMs: avgLatencyMs,
      modelSuccessCounts: modelSuccessCounts,
      modelFailureCounts: modelFailureCounts,
      modelAvgLatencies: modelAvgLatencies,
      bookUsageCounts: bookUsageCounts,
      recentFailures: recentFailures,
    );
  }
}
