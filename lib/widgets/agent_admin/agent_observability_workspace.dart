import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/agent_execution_trace.dart';
import '../../models/agent_tool_config.dart';
import '../../services/agent_trace_storage.dart';

class _ChatSessionGroup {
  _ChatSessionGroup({
    required this.sessionId,
    required this.title,
    required this.studentForm,
    required this.bookTitle,
    required this.category,
    required this.latestTimestamp,
    required this.traces,
  });

  final String sessionId;
  final String title;
  final String studentForm;
  final String? bookTitle;
  final String? category;
  final DateTime latestTimestamp;
  final List<AgentExecutionTrace> traces;

  int get totalTurns => traces.length;
  int get totalToolsUsed =>
      traces.fold(0, (sum, t) => sum + t.toolCalls.length);
  int get totalLatencyMs => traces.fold(0, (sum, t) => sum + t.totalLatencyMs);
  int get totalModelLatencyMs =>
      traces.fold(0, (sum, t) => sum + t.resolvedModelLatencyMs);
  int get totalToolLatencyMs =>
      traces.fold(0, (sum, t) => sum + t.totalToolLatencyMs);
  bool get hasErrors => traces.any(
    (t) => !t.isSuccess || t.status == AgentVerificationStatus.failed,
  );
}

class AgentObservabilityWorkspace extends StatefulWidget {
  const AgentObservabilityWorkspace({super.key});

  @override
  State<AgentObservabilityWorkspace> createState() =>
      _AgentObservabilityWorkspaceState();
}

class _AgentObservabilityWorkspaceState
    extends State<AgentObservabilityWorkspace> {
  final _traceStorage = AgentTraceStorage.instance;

  int _selectedTabIndex =
      0; // 0 = Chat Cards, 1 = Flat Traces, 2 = Tools Registry
  List<AgentExecutionTrace> _traces = [];
  List<AgentToolConfig> _toolConfigs = [];
  AgentTraceSummary? _summary;
  bool _isLoading = true;

  final Set<String> _expandedSessionIds = {};
  final Set<String> _expandedLiveIds = {};
  final Set<String> _expandedTurnIds = {};
  Timer? _liveTimer;

  // Filters for traces
  String _searchQuery = '';
  String _statusFilter =
      'All'; // 'All', 'Accepted', 'Rejected', 'Pending', 'Failed'
  String _formFilter = 'All'; // 'All', 'Form 1', 'Form 2', 'Form 3', 'Form 4'
  AgentExecutionTrace? _selectedTrace;

  @override
  void initState() {
    super.initState();
    _loadData();
    _traceStorage.liveExecutionsNotifier.addListener(_onLiveExecutionsChanged);
    _traceStorage.tracesCountNotifier.addListener(_loadDataSilently);
    unawaited(_traceStorage.startLiveExecutionMonitoring());
    _startLiveTimer();
  }

  void _startLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final active = _traceStorage.liveExecutionsNotifier.value;
      if (active.any((e) => !e.isCompleted) && mounted) {
        setState(() {});
      }
    });
  }

  void _onLiveExecutionsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDataSilently() async {
    final traces = await _traceStorage.getTraces();
    final summary = await _traceStorage.getSummary();
    if (mounted) {
      setState(() {
        _traces = traces;
        _summary = summary;
      });
    }
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _traceStorage.liveExecutionsNotifier.removeListener(
      _onLiveExecutionsChanged,
    );
    _traceStorage.tracesCountNotifier.removeListener(_loadDataSilently);
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final traces = await _traceStorage.getTraces();
    final tools = await _traceStorage.getToolConfigs();
    final summary = await _traceStorage.getSummary();

    if (!mounted) return;
    setState(() {
      _traces = traces;
      _toolConfigs = tools;
      _summary = summary;
      if (_traces.isNotEmpty && _selectedTrace == null) {
        _selectedTrace = _traces.first;
      }
      if (_expandedSessionIds.isEmpty && _chatSessionGroups.isNotEmpty) {
        _expandedSessionIds.add(_chatSessionGroups.first.sessionId);
      }
      _isLoading = false;
    });
  }

  Future<void> _toggleTool(String toolId, bool isEnabled) async {
    await _traceStorage.toggleTool(toolId, isEnabled);
    final updated = await _traceStorage.getToolConfigs();
    if (!mounted) return;
    setState(() {
      _toolConfigs = updated;
    });
  }

  Future<void> _clearTraces() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 10),
            Text('Nadiifi Traces-ka Agent-ka'),
          ],
        ),
        content: const Text(
          'Ma hubtaa inaad tirtirto dhammaan diiwaannada shaqada qarsoon ee Agent-ka? Tallaabadan dib looma noqon karo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Jooji'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Haa, Tirtir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _traceStorage.clearTraces();
      _selectedTrace = null;
      _expandedSessionIds.clear();
      await _loadData();
    }
  }

  List<AgentExecutionTrace> get _filteredTraces {
    return _traces.where((trace) {
      if (_statusFilter != 'All') {
        if (_statusFilter == 'Accepted' &&
            trace.status != AgentVerificationStatus.accepted) {
          return false;
        }
        if (_statusFilter == 'Rejected' &&
            trace.status != AgentVerificationStatus.rejected) {
          return false;
        }
        if (_statusFilter == 'Pending' &&
            trace.status != AgentVerificationStatus.pendingConfirmation &&
            trace.status != AgentVerificationStatus.searching) {
          return false;
        }
        if (_statusFilter == 'Failed' &&
            trace.status != AgentVerificationStatus.failed) {
          return false;
        }
      }

      if (_formFilter != 'All') {
        if (!trace.studentForm.toLowerCase().contains(
          _formFilter.toLowerCase(),
        )) {
          return false;
        }
      }

      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final inMsg = trace.userMessage.toLowerCase().contains(q);
        final inLesson =
            trace.matchedLessonTitle?.toLowerCase().contains(q) ?? false;
        final inBook =
            trace.matchedBookTitle?.toLowerCase().contains(q) ?? false;
        final inThought = trace.internalThought.toLowerCase().contains(q);
        final inTitle = trace.chatTitle?.toLowerCase().contains(q) ?? false;
        final inAnswer = trace.finalAnswer?.toLowerCase().contains(q) ?? false;
        final inAugmented =
            trace.augmentedPrompt?.toLowerCase().contains(q) ?? false;
        if (!inMsg &&
            !inLesson &&
            !inBook &&
            !inThought &&
            !inTitle &&
            !inAnswer &&
            !inAugmented) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  List<_ChatSessionGroup> get _chatSessionGroups {
    final Map<String, List<AgentExecutionTrace>> map = {};
    for (final trace in _filteredTraces) {
      final sId = trace.sessionId != null && trace.sessionId!.trim().isNotEmpty
          ? trace.sessionId!.trim()
          : (trace.chatTitle != null && trace.chatTitle!.trim().isNotEmpty
                ? 'title_${trace.chatTitle!.trim()}'
                : 'time_${trace.timestamp.year}_${trace.timestamp.month}_${trace.timestamp.day}_${trace.timestamp.hour}');
      map.putIfAbsent(sId, () => []).add(trace);
    }

    final groups = <_ChatSessionGroup>[];
    for (final entry in map.entries) {
      final list = entry.value;
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final first = list.first;
      final last = list.last;
      final title =
          last.chatTitle ??
          first.chatTitle ??
          (first.matchedBookTitle ?? first.userMessage);

      groups.add(
        _ChatSessionGroup(
          sessionId: entry.key,
          title: title,
          studentForm: last.studentForm,
          bookTitle: last.matchedBookTitle ?? first.matchedBookTitle,
          category: last.matchedCategory ?? first.matchedCategory,
          latestTimestamp: last.timestamp,
          traces: list,
        ),
      );
    }

    groups.sort((a, b) => b.latestTimestamp.compareTo(a.latestTimestamp));
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Top KPI Summary Cards
        _buildKpiMetricsRow(),

        const SizedBox(height: 16),

        // 2. Tab Navigation Switcher & Actions
        _buildWorkspaceControls(),

        const SizedBox(height: 14),

        // 3. Main Body: Chat Cards vs Traces vs Tools
        Expanded(
          child: _selectedTabIndex == 0
              ? _buildChatSessionsView()
              : (_selectedTabIndex == 1
                    ? _buildExecutionTracesView()
                    : _buildToolsRegistryView()),
        ),
      ],
    );
  }

  Widget _buildKpiMetricsRow() {
    final summary = _summary;
    final total = summary?.totalTraces ?? 0;
    final avgLatency = summary?.averageLatencyMs ?? 0;
    final activeTools = _toolConfigs.where((t) => t.isEnabled).length;

    return Row(
      children: [
        Expanded(
          child: _buildKpiCard(
            title: 'Kulamada Wada-hadalka',
            value: '${_chatSessionGroups.length}',
            subtitle: 'Wadarta chat-yada la diiwaangeliyay',
            icon: Icons.forum_rounded,
            color: const Color(0xFF0022FF),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _buildKpiCard(
            title: 'Wadarta Fariimaha (Turns)',
            value: '$total',
            subtitle: 'Fariimaha la falanqeeyay',
            icon: Icons.hub_rounded,
            color: const Color(0xFF10B981),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _buildKpiCard(
            title: 'Xawaaraha Celceliska',
            value: formatTraceDuration(avgLatency),
            subtitle: 'Waqtiga jawaabaha & tools-ka',
            icon: Icons.speed_rounded,
            color: const Color(0xFFF59E0B),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _buildKpiCard(
            title: 'Tools-ka Shidan',
            value: '$activeTools / ${_toolConfigs.length}',
            subtitle: 'Awoodaha diyaar u ah Agent-ka',
            icon: Icons.extension_rounded,
            color: const Color(0xFF8B5CF6),
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceControls() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTabPill(
                  index: 0,
                  label: 'Kulamada (Chat Cards)',
                  icon: Icons.forum_rounded,
                  count: _chatSessionGroups.length,
                ),
                _buildTabPill(
                  index: 1,
                  label: 'Diiwaanka Tooska ah (Traces)',
                  icon: Icons.visibility_rounded,
                  count: _traces.length,
                ),
                _buildTabPill(
                  index: 2,
                  label: 'Tools-ka Agent-ka',
                  icon: Icons.build_circle_rounded,
                  count: _toolConfigs.length,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            tooltip: 'Cusbooneysii xogta',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
              side: BorderSide(color: Colors.red.shade200),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _traces.isEmpty ? null : _clearTraces,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text(
              'Nadiifi Traces-ka',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill({
    required int index,
    required String label,
    required IconData icon,
    int? count,
  }) {
    final isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedTabIndex = index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? const Color(0xFF0022FF)
                  : Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.black87 : Colors.grey.shade700,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF0022FF).withValues(alpha: 0.1)
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? const Color(0xFF0022FF)
                        : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 0. CHAT SESSIONS & DEEP PER-MESSAGE CARDS VIEW
  // ===========================================================================

  Widget _buildChatSessionsView() {
    final groups = _chatSessionGroups;
    final liveExecutions = _traceStorage.liveExecutionsNotifier.value
        .where((execution) => !execution.isCompleted)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: _buildChatFiltersBar(),
          ),
          const Divider(height: 1),
          Expanded(
            child: (groups.isEmpty && liveExecutions.isEmpty)
                ? _buildEmptyState(
                    title: 'Ma jiraan Kulamo Wada-hadal ah',
                    subtitle:
                        'Marka ardaydu chat-ka fariin u diraan, chat kasta iyo fariin kasta oo gudaha ka dhacday halkan ayaa lagu soo bandhigi doonaa.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 1. Dedicated Live Activity Section
                      if (liveExecutions.isNotEmpty) ...[
                        _buildLiveExecutionsSection(),
                        const SizedBox(height: 8),
                      ],

                      // 2. Chat Sessions List
                      ...groups.map((group) {
                        final isExpanded = _expandedSessionIds.contains(
                          group.sessionId,
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildChatSessionCard(group, isExpanded),
                        );
                      }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveExecutionsSection() {
    final liveExecutions = _traceStorage.liveExecutionsNotifier.value
        .where((execution) => !execution.isCompleted)
        .toList();
    if (liveExecutions.isEmpty) return const SizedBox.shrink();

    final activeCount = liveExecutions.where((e) => !e.isCompleted).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: activeCount > 0
              ? const Color(0xFF10B981)
              : const Color(0xFF0022FF).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: activeCount > 0
                ? const Color(0xFF10B981).withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Live Section Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: activeCount > 0
                    ? [const Color(0xFF064E3B), const Color(0xFF0F172A)]
                    : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(15),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activeCount > 0
                        ? const Color(0xFF10B981)
                        : const Color(0xFF94A3B8),
                    boxShadow: activeCount > 0
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF10B981,
                              ).withValues(alpha: 0.8),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  activeCount > 0
                      ? 'QAYBTA TOOSKA AH (LIVE AGENT ACTIVITY)'
                      : 'DHACDOOYINKII TOOSKA AHAA EE UGU DAMBEEYAY',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: activeCount > 0
                        ? const Color(0xFF10B981).withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    activeCount > 0
                        ? '$activeCount shaqo ayaa socota'
                        : '${liveExecutions.length} dhameystirmay',
                    style: TextStyle(
                      color: activeCount > 0
                          ? const Color(0xFF34D399)
                          : Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // List of live message cards
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: liveExecutions.map((live) {
                final isExpanded = _expandedLiveIds.contains(live.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildLiveExecutionCard(live, isExpanded),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveExecutionCard(AgentLiveExecution live, bool isExpanded) {
    final elapsedSec = (live.elapsedMs / 1000).toStringAsFixed(1);
    final isDone = live.isCompleted;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDone
              ? (live.isSuccess ? Colors.green.shade200 : Colors.red.shade200)
              : const Color(0xFF10B981).withValues(alpha: 0.4),
          width: isDone ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tappable Header
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedLiveIds.remove(live.id);
                } else {
                  _expandedLiveIds.add(live.id);
                }
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Status Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: isDone
                              ? (live.isSuccess
                                    ? const Color(
                                        0xFF10B981,
                                      ).withValues(alpha: 0.12)
                                    : const Color(
                                        0xFFEF4444,
                                      ).withValues(alpha: 0.12))
                              : const Color(0xFF0284C7).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isDone) ...[
                              const SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF0284C7),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              isDone
                                  ? (live.isSuccess
                                        ? '✅ Guulaystay'
                                        : '❌ Fashilmay')
                                  : '🔄 Shaqadu Way Socotaa',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDone
                                    ? (live.isSuccess
                                          ? const Color(0xFF059669)
                                          : const Color(0xFFDC2626))
                                    : const Color(0xFF0284C7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Form Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF0022FF,
                          ).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          live.studentForm,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0022FF),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Model Badge
                      if (live.currentModelName != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.smart_toy_rounded,
                                size: 11,
                                color: Color(0xFF2563EB),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                live.currentModelName!,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      // Elapsed Timer Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              size: 11,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${elapsedSec}s',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.grey.shade600,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Message Text
                  Text(
                    live.userMessage,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: isExpanded ? 10 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Status & Step
                  Row(
                    children: [
                      Icon(
                        Icons.near_me_rounded,
                        size: 13,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          live.currentStatus,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (live.toolCalls.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${live.toolCalls.length} tools',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Expanded Live Details (Timeline & Stages)
          if (isExpanded) ...[
            const Divider(height: 1),
            Container(
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tallaabooyinka Shaqada ee Tooska ah (Live Execution Timeline):',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Stage 1: Question
                  _buildLiveStepRow(
                    stepNumber: 1,
                    title: 'Fariinta Ardayga & Codsiga',
                    subtitle: 'Su’aasha waxaa loo diray agent orchestrator',
                    isDone: true,
                    isSuccess: true,
                  ),

                  // Stage 2: Tool Calls
                  if (live.toolCalls.isNotEmpty) ...[
                    ...live.toolCalls.map(
                      (call) => _buildLiveStepRow(
                        stepNumber: 2,
                        title: 'Tool: ${call.toolName}',
                        subtitle: call.outputSummary ?? 'Wicitaanka tool-ka',
                        durationStr: formatTraceDuration(call.latencyMs),
                        isDone: true,
                        isSuccess: call.isSuccess,
                      ),
                    ),
                  ] else if (!isDone) ...[
                    _buildLiveStepRow(
                      stepNumber: 2,
                      title: 'Raadinta Manhajka & Tools-ka',
                      subtitle:
                          'Agent-ku wuxuu go’aaminayaa baahida tool-ka...',
                      isDone: false,
                    ),
                  ],

                  // Stage 3: LLM Calls
                  if (live.modelCalls.isNotEmpty) ...[
                    ...live.modelCalls.map(
                      (mCall) => _buildLiveStepRow(
                        stepNumber: 3,
                        title: '${mCall.modelName ?? "LLM"}: ${mCall.callType}',
                        subtitle:
                            mCall.errorMessage ??
                            (mCall.isSuccess ? 'Guulaystay' : 'Cillad'),
                        durationStr: formatTraceDuration(mCall.latencyMs),
                        isDone: true,
                        isSuccess: mCall.isSuccess,
                      ),
                    ),
                  ] else if (!isDone) ...[
                    _buildLiveStepRow(
                      stepNumber: 3,
                      title:
                          'Wicitaanka Model-ka (${live.currentModelName ?? "Gemini"})',
                      subtitle: 'Diyaarinta iyo dhuuxista jawaabta...',
                      isDone: false,
                    ),
                  ],

                  // Final Answer or Error
                  if (live.finalAnswer != null &&
                      live.finalAnswer!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 14,
                                color: Color(0xFF10B981),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Jawaabta Diyaarka ah:',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            live.finalAnswer!,
                            style: const TextStyle(fontSize: 12, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ] else if (live.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 14,
                            color: Color(0xFFEF4444),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              live.errorMessage!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveStepRow({
    required int stepNumber,
    required String title,
    required String subtitle,
    String? durationStr,
    required bool isDone,
    bool isSuccess = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone
                  ? (isSuccess
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444))
                  : const Color(0xFF0284C7),
            ),
            alignment: Alignment.center,
            child: isDone
                ? Icon(
                    isSuccess ? Icons.check : Icons.close,
                    size: 12,
                    color: Colors.white,
                  )
                : const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.white,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (durationStr != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                durationStr,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChatFiltersBar() {
    return Column(
      children: [
        TextField(
          decoration: InputDecoration(
            isDense: true,
            hintText:
                'Raadi fariin arday, waxa app-ku ku daray, cinwaan, ama buug...',
            hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
          onChanged: (val) => setState(() => _searchQuery = val),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _statusFilter,
                isDense: true,
                decoration: InputDecoration(
                  labelText: 'Xaaladda Fariimaha',
                  labelStyle: const TextStyle(fontSize: 11),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('Dhammaan')),
                  DropdownMenuItem(
                    value: 'Accepted',
                    child: Text('✅ Aqbalay / Guulaystay'),
                  ),
                  DropdownMenuItem(
                    value: 'Rejected',
                    child: Text('❌ Diiday / Cillad'),
                  ),
                  DropdownMenuItem(value: 'Pending', child: Text('⏳ Sugaya')),
                  DropdownMenuItem(
                    value: 'Failed',
                    child: Text('⚠️ Fashilmay'),
                  ),
                ],
                onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _formFilter,
                isDense: true,
                decoration: InputDecoration(
                  labelText: 'Fasalka',
                  labelStyle: const TextStyle(fontSize: 11),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('Dhammaan')),
                  DropdownMenuItem(value: 'Form 1', child: Text('Form 1')),
                  DropdownMenuItem(value: 'Form 2', child: Text('Form 2')),
                  DropdownMenuItem(value: 'Form 3', child: Text('Form 3')),
                  DropdownMenuItem(value: 'Form 4', child: Text('Form 4')),
                ],
                onChanged: (v) => setState(() => _formFilter = v ?? 'All'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChatSessionCard(_ChatSessionGroup group, bool isExpanded) {
    final turnsCount = group.totalTurns;
    final toolsCount = group.totalToolsUsed;
    final hasErrors = group.hasErrors;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded
              ? const Color(0xFF0022FF).withValues(alpha: 0.35)
              : Colors.grey.shade200,
          width: isExpanded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header (Clickable to toggle expansion)
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedSessionIds.remove(group.sessionId);
                } else {
                  _expandedSessionIds.add(group.sessionId);
                }
              });
            },
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(16),
              bottom: isExpanded ? Radius.zero : const Radius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0022FF).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.forum_rounded,
                      color: Color(0xFF0022FF),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                group.title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Form Badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF0022FF,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                group.studentForm,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0022FF),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Error or Success Badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (hasErrors
                                            ? const Color(0xFFEF4444)
                                            : const Color(0xFF10B981))
                                        .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    hasErrors
                                        ? Icons.error_outline_rounded
                                        : Icons.check_circle_rounded,
                                    size: 12,
                                    color: hasErrors
                                        ? const Color(0xFFEF4444)
                                        : const Color(0xFF10B981),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    hasErrors
                                        ? 'Cillad ayaa ku jirta'
                                        : 'Wuu Guulaystay',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: hasErrors
                                          ? const Color(0xFFEF4444)
                                          : const Color(0xFF10B981),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (group.bookTitle != null) ...[
                              Icon(
                                Icons.menu_book_rounded,
                                size: 13,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                group.bookTitle!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Icon(
                              Icons.access_time_rounded,
                              size: 13,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDateTime(group.latestTimestamp),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            const Spacer(),
                            // Duration pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF0F172A,
                                ).withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.timer_outlined,
                                    size: 11,
                                    color: Color(0xFF0F172A),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    formatTraceDuration(group.totalLatencyMs),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Turns count pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Text(
                                '$turnsCount fariimood (turns)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Tool calls pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: toolsCount > 0
                                    ? const Color(
                                        0xFF10B981,
                                      ).withValues(alpha: 0.1)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: toolsCount > 0
                                      ? const Color(
                                          0xFF10B981,
                                        ).withValues(alpha: 0.3)
                                      : Colors.grey.shade200,
                                ),
                              ),
                              child: Text(
                                toolsCount > 0
                                    ? '$toolsCount tool calls'
                                    : 'Toos ah (No tools)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: toolsCount > 0
                                      ? const Color(0xFF059669)
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: Colors.grey.shade600,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Collapsible turns list
          if (isExpanded) ...[
            const Divider(height: 1),
            Container(
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          size: 16,
                          color: Color(0xFF0022FF),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Dhacdooyinkii Gudaha ee Chat-kan (Fariin kasta iyo tallaabooyinkeedii):',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...group.traces.asMap().entries.map((entry) {
                    final turnIndex = entry.key + 1;
                    final trace = entry.value;
                    final isTurnExpanded = _expandedTurnIds.contains(trace.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _buildMessageTurnCard(
                        trace: trace,
                        turnIndex: turnIndex,
                        totalTurns: group.traces.length,
                        isExpanded: isTurnExpanded,
                        onToggleExpand: () {
                          setState(() {
                            if (isTurnExpanded) {
                              _expandedTurnIds.remove(trace.id);
                            } else {
                              _expandedTurnIds.add(trace.id);
                            }
                          });
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageTurnCard({
    required AgentExecutionTrace trace,
    required int turnIndex,
    required int totalTurns,
    required bool isExpanded,
    required VoidCallback onToggleExpand,
  }) {
    final hasTools = trace.toolCalls.isNotEmpty;
    final timeStr =
        '${trace.timestamp.hour.toString().padLeft(2, '0')}:${trace.timestamp.minute.toString().padLeft(2, '0')}:${trace.timestamp.second.toString().padLeft(2, '0')}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: trace.isSuccess
              ? (isExpanded
                    ? const Color(0xFF0022FF).withValues(alpha: 0.4)
                    : Colors.grey.shade300)
              : const Color(0xFFEF4444).withValues(alpha: 0.5),
          width: isExpanded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Turn Header (Tappable to toggle expand)
          InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(13),
              bottom: isExpanded ? Radius.zero : const Radius.circular(13),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(13),
                  bottom: isExpanded ? Radius.zero : const Radius.circular(13),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0022FF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Fariinta #$turnIndex',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (trace.mode != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        trace.mode!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (trace.modelName != null) ...[
                    const Icon(
                      Icons.smart_toy_rounded,
                      size: 13,
                      color: Color(0xFF60A5FA),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trace.modelName!,
                      style: const TextStyle(
                        color: Color(0xFF60A5FA),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Spacer(),
                  Text(
                    timeStr,
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          size: 11,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formatTraceDuration(trace.totalLatencyMs),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),

          // Collapsed preview row
          if (!isExpanded) ...[
            InkWell(
              onTap: onToggleExpand,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trace.userMessage,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (trace.isSuccess
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFFEF4444))
                                    .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            trace.isSuccess
                                ? '✅ Wuu Guulaystay'
                                : '❌ Fashilmay',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: trace.isSuccess
                                  ? const Color(0xFF059669)
                                  : const Color(0xFFDC2626),
                            ),
                          ),
                        ),
                        if (hasTools) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF0022FF,
                              ).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${trace.toolCalls.length} tools',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0022FF),
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Taabo si aad u aragto tallaabooyinka shaqada',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue.shade700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: Colors.blue.shade700,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (isExpanded)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Waqtiga & Xawaaraha (Latency & Time Breakdown)
                  _buildLatencyBreakdownCard(trace),
                  const SizedBox(height: 12),

                  // 1. Fariinta Ardaygu Qoray (Student Prompt)
                  _buildTurnSubSection(
                    badgeColor: const Color(0xFF0022FF),
                    icon: Icons.person_rounded,
                    title: '1. Fariinta Ardaygu Qoray (Student Input):',
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0022FF).withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(
                            0xFF0022FF,
                          ).withValues(alpha: 0.15),
                        ),
                      ),
                      child: SelectableText(
                        trace.userMessage,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 2. Waxa App-ku Ku Daray & Tilmaamaha Nidaamka
                  _buildTurnSubSection(
                    badgeColor: const Color(0xFF8B5CF6),
                    icon: Icons.auto_awesome_rounded,
                    title:
                        '2. Waxa App-ku Ku Daray (Injected Context & Prompts):',
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Injected Context details
                          if (trace.injectedContext != null &&
                              trace.injectedContext!.trim().isNotEmpty) ...[
                            Text(
                              'Xogta Xadka & Manhajka ee la raaciyay:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: SelectableText(
                                trace.injectedContext!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade800,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],

                          // System Prompt toggle/view
                          if (trace.systemPrompt != null &&
                              trace.systemPrompt!.trim().isNotEmpty) ...[
                            _buildCodeSnippetBox(
                              title: 'Tilmaamaha Nidaamka (System Prompt)',
                              content: trace.systemPrompt!,
                              icon: Icons.settings_suggest_rounded,
                            ),
                            const SizedBox(height: 10),
                          ],

                          // Full Prompt Sent To Model
                          if (trace.augmentedPrompt != null &&
                              trace.augmentedPrompt!.trim().isNotEmpty) ...[
                            _buildCodeSnippetBox(
                              title:
                                  'Qoraalka Dhammaystiran ee loo Diray AI-ga (Full Prompt Sent to LLM)',
                              content: trace.augmentedPrompt!,
                              icon: Icons.outgoing_mail,
                              isHighlighted: true,
                            ),
                          ] else ...[
                            Text(
                              'Qoraal dheeraad ah lama keydin kulankan ka hor.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade500,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 3. Wicitaannada Tools-ka & Waxa ay soo celiyeen
                  _buildTurnSubSection(
                    badgeColor: const Color(0xFF059669),
                    icon: Icons.extension_rounded,
                    title: '3. Codsiyada Tools-ka & Waxa Tool-ku Soo Celiyay:',
                    child: hasTools
                        ? Column(
                            children: trace.toolCalls
                                .map((call) => _buildRichToolCallCard(call))
                                .toList(),
                          )
                        : Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 16,
                                  color: Color(0xFF475569),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Jawaab Toos ah: AI-gu wax tool ah ma uusan wicin sababtoo ah suaashu uma baahnayn xog cusub oo manhajka ah.',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),

                  const SizedBox(height: 12),

                  // 4. Jawaabta AI-ga & Natiijada
                  _buildTurnSubSection(
                    badgeColor: const Color(0xFFD97706),
                    icon: Icons.psychology_rounded,
                    title: '4. Jawaabta Model-ka & Natiijada:',
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: trace.isSuccess
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: trace.isSuccess
                              ? Colors.grey.shade300
                              : const Color(0xFFFCA5A5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (trace.finalAnswer != null &&
                              trace.finalAnswer!.isNotEmpty) ...[
                            SelectableText(
                              trace.finalAnswer!,
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.45,
                                color: Colors.black87,
                              ),
                            ),
                          ] else if (trace.errorMessage != null) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Color(0xFFDC2626),
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SelectableText(
                                    trace.errorMessage!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFB91C1C),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            Text(
                              trace.internalThought.isNotEmpty
                                  ? trace.internalThought
                                  : 'Jawaab toos ah oo kooban ayaa loo celiyay ardayga.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                          if (trace.studentFeedback != null &&
                              trace.studentFeedback!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.amber.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.feedback_outlined,
                                    size: 14,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Feedback-ga ardayga: ${trace.studentFeedback}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLatencyBreakdownCard(AgentExecutionTrace trace) {
    final totalMs = trace.totalLatencyMs;
    final modelMs = trace.resolvedModelLatencyMs;
    final toolsMs = trace.totalToolLatencyMs;
    final modelPct = trace.modelTimePercentage;
    final toolsPct = trace.toolsTimePercentage;
    final hasModelSteps = trace.modelCalls.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.speed_rounded,
                size: 15,
                color: Color(0xFF0F172A),
              ),
              const SizedBox(width: 6),
              const Text(
                'Falanqaynta Waqtiga (Latency & Time Breakdown):',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Guud: ${formatTraceDuration(totalMs)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Visual Proportion Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                    flex: (modelPct * 10).round().clamp(1, 1000),
                    child: Container(color: const Color(0xFF0022FF)),
                  ),
                  if (toolsMs > 0)
                    Expanded(
                      flex: (toolsPct * 10).round().clamp(1, 1000),
                      child: Container(color: const Color(0xFF10B981)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Cards Row: Model Time vs Tools Time
          Row(
            children: [
              // Model Latency Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0022FF).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF0022FF).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.psychology_rounded,
                            size: 13,
                            color: Color(0xFF0022FF),
                          ),
                          const SizedBox(width: 4),
                          const Expanded(
                            child: Text(
                              'Waqtiga Model-ka (LLM):',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0022FF),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            formatTraceDuration(modelMs),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(${modelPct.toStringAsFixed(1)}%)',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Waqtiga uu AI-gu ku maqnaa xisaabinta & falanqaynta',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Tools Latency Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.extension_rounded,
                            size: 13,
                            color: Color(0xFF059669),
                          ),
                          const SizedBox(width: 4),
                          const Expanded(
                            child: Text(
                              'Waqtiga Tools-ka (Search & PDF):',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF059669),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            formatTraceDuration(toolsMs),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(${toolsPct.toStringAsFixed(1)}%)',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Raadinta buugga iyo soo jaridda PDF-ka',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // If individual step-by-step model calls exist, show them clearly!
          if (hasModelSteps) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tallaabooyinkii Model-ka ee Kulamadan (LLM Call Steps):',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...trace.modelCalls.map((call) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            call.isSuccess
                                ? Icons.check_circle_outline_rounded
                                : Icons.error_outline_rounded,
                            size: 12,
                            color: call.isSuccess
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              call.callType,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          Text(
                            formatTraceDuration(call.latencyMs),
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTurnSubSection({
    required Color badgeColor,
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: badgeColor),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _buildRichToolCallCard(AgentToolCallLog call) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.build_rounded,
                  size: 14,
                  color: Color(0xFF059669),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  call.toolName.isNotEmpty ? call.toolName : call.toolId,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      (call.isSuccess
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444))
                          .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  call.isSuccess
                      ? 'Guulaystay (${formatTraceDuration(call.latencyMs)})'
                      : 'Fashilmay',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: call.isSuccess
                        ? const Color(0xFF059669)
                        : const Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Arguments
          Text(
            'Codsiga loo diray tool-ka (Arguments):',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(call.arguments),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Response / Output
          Text(
            'Waxa tool-ku soo celiyay (Tool Response):',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: SelectableText(
              call.rawOutput != null
                  ? (call.rawOutput is String
                        ? call.rawOutput as String
                        : const JsonEncoder.withIndent(
                            '  ',
                          ).convert(call.rawOutput))
                  : (call.outputSummary ?? 'Wax xog ah lama soo celin.'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeSnippetBox({
    required String title,
    required String content,
    required IconData icon,
    bool isHighlighted = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHighlighted
              ? const Color(0xFF8B5CF6).withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.08)
                  : Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(7),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 13,
                  color: isHighlighted
                      ? const Color(0xFF8B5CF6)
                      : Colors.grey.shade700,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isHighlighted
                          ? const Color(0xFF6D28D9)
                          : Colors.grey.shade800,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text('$title waa la koobiyeeyay!'),
                          ],
                        ),
                        duration: const Duration(seconds: 2),
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 12,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Koobiyeey',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              content,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                height: 1.45,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (date == today) {
      return 'Maanta $timeStr';
    } else if (date == today.subtract(const Duration(days: 1))) {
      return 'Shalay $timeStr';
    }
    return '${dt.day}/${dt.month}/${dt.year} $timeStr';
  }

  // ===========================================================================
  // 1. LIVE EXECUTION TRACES VIEW (Master-Detail)
  // ===========================================================================

  Widget _buildExecutionTracesView() {
    final filtered = _filteredTraces;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Filter & List of Traces
        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                _buildTraceFiltersBar(),
                const Divider(height: 1),
                Expanded(
                  child: filtered.isEmpty
                      ? _buildEmptyState(
                          title: 'Ma jiraan Traces la helay',
                          subtitle:
                              'Ardaygu marka uu su\'aal weydiiyo iyadoo aan buug la dooran, tallaabo kasta oo qarsoon halkan ayaa lagu arki doonaa.',
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 16),
                          itemBuilder: (context, index) {
                            final trace = filtered[index];
                            final isSelected = _selectedTrace?.id == trace.id;
                            return _buildTraceListTile(trace, isSelected);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 16),

        // Right Column: Deep Trace Inspector (Reasoning, Tools, Output)
        Expanded(
          flex: 6,
          child: _selectedTrace == null
              ? Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: _buildEmptyState(
                    title: 'Dooro Trace',
                    subtitle:
                        'Guji mid ka mid ah fariimaha bidixda si aad u aragto waxa gudaha ka socday.',
                  ),
                )
              : _buildDeepTraceInspector(_selectedTrace!),
        ),
      ],
    );
  }

  Widget _buildTraceFiltersBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Raadi fariin, cashar, buug...',
              hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Status dropdown
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: 'Xaaladda',
                    labelStyle: const TextStyle(fontSize: 11),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('Dhammaan')),
                    DropdownMenuItem(
                      value: 'Accepted',
                      child: Text('✅ Aqbalay'),
                    ),
                    DropdownMenuItem(
                      value: 'Rejected',
                      child: Text('❌ Diiday'),
                    ),
                    DropdownMenuItem(value: 'Pending', child: Text('⏳ Sugaya')),
                    DropdownMenuItem(
                      value: 'Failed',
                      child: Text('⚠️ Fashilmay'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
                ),
              ),
              const SizedBox(width: 8),
              // Form dropdown
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _formFilter,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: 'Fasalka',
                    labelStyle: const TextStyle(fontSize: 11),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('Dhammaan')),
                    DropdownMenuItem(value: 'Form 1', child: Text('Form 1')),
                    DropdownMenuItem(value: 'Form 2', child: Text('Form 2')),
                    DropdownMenuItem(value: 'Form 3', child: Text('Form 3')),
                    DropdownMenuItem(value: 'Form 4', child: Text('Form 4')),
                  ],
                  onChanged: (v) => setState(() => _formFilter = v ?? 'All'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTraceListTile(AgentExecutionTrace trace, bool isSelected) {
    final curriculumToolCount = trace.toolCalls
        .where(
          (call) =>
              call.toolId != 'intent_router' &&
              call.toolId != 'conversation_memory',
        )
        .length;
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (trace.status) {
      case AgentVerificationStatus.accepted:
        statusColor = const Color(0xFF10B981);
        statusLabel = 'Aqbalay';
        statusIcon = Icons.check_circle_rounded;
        break;
      case AgentVerificationStatus.rejected:
        statusColor = const Color(0xFFEF4444);
        statusLabel = 'Diiday';
        statusIcon = Icons.cancel_rounded;
        break;
      case AgentVerificationStatus.pendingConfirmation:
      case AgentVerificationStatus.searching:
        statusColor = const Color(0xFFF59E0B);
        statusLabel = 'Hubin Sugaya';
        statusIcon = Icons.hourglass_top_rounded;
        break;
      case AgentVerificationStatus.failed:
        statusColor = Colors.grey;
        statusLabel = 'Lama Helin';
        statusIcon = Icons.info_outline_rounded;
        break;
    }

    final timeStr =
        '${trace.timestamp.hour.toString().padLeft(2, '0')}:${trace.timestamp.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: () => setState(() => _selectedTrace = trace),
      child: Container(
        padding: const EdgeInsets.all(12),
        color: isSelected
            ? const Color(0xFF0022FF).withValues(alpha: 0.05)
            : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Form Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0022FF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    trace.studentForm,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0022FF),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Status Chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 11, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: curriculumToolCount > 0
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : const Color(0xFF64748B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    curriculumToolCount > 0
                        ? 'Tools: $curriculumToolCount'
                        : 'Jawaab toos ah',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: curriculumToolCount > 0
                          ? const Color(0xFF059669)
                          : const Color(0xFF475569),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  timeStr,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              trace.userMessage,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.menu_book_rounded,
                  size: 13,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    trace.matchedLessonTitle ??
                        (trace.matchedBookTitle ?? 'Baaritaan guud'),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  formatTraceDuration(trace.totalLatencyMs),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeepTraceInspector(AgentExecutionTrace trace) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Inspector Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.psychology_rounded,
                  color: Color(0xFF60A5FA),
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Waxa Gadaal ka Socda (Behind-The-Scenes Trace)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Trace ID: ${trace.id} • ${trace.studentForm}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${formatTraceDuration(trace.totalLatencyMs)} Total',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Student Original Input
                  _buildSectionBox(
                    title: 'Fariinta Ardaygu Soo Qoray (Student Prompt)',
                    icon: Icons.chat_bubble_outline_rounded,
                    color: const Color(0xFF0022FF),
                    child: Text(
                      trace.userMessage,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 2. Waxa App-ku Ku Daray & Tilmaamaha Nidaamka
                  _buildSectionBox(
                    title: 'Waxa App-ku Ku Daray (Injected Context & Prompts)',
                    icon: Icons.auto_awesome_rounded,
                    color: const Color(0xFF8B5CF6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (trace.injectedContext != null &&
                            trace.injectedContext!.trim().isNotEmpty) ...[
                          Text(
                            'Xogta Xadka & Manhajka ee la raaciyay:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: SelectableText(
                              trace.injectedContext!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade800,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (trace.systemPrompt != null &&
                            trace.systemPrompt!.trim().isNotEmpty) ...[
                          _buildCodeSnippetBox(
                            title: 'Tilmaamaha Nidaamka (System Prompt)',
                            content: trace.systemPrompt!,
                            icon: Icons.settings_suggest_rounded,
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (trace.augmentedPrompt != null &&
                            trace.augmentedPrompt!.trim().isNotEmpty) ...[
                          _buildCodeSnippetBox(
                            title:
                                'Qoraalka Dhammaystiran ee loo Diray AI-ga (Full Prompt Sent to LLM)',
                            content: trace.augmentedPrompt!,
                            icon: Icons.outgoing_mail,
                            isHighlighted: true,
                          ),
                        ] else ...[
                          Text(
                            'Qoraal dheeraad ah lama keydin kulankan ka hor.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 3. Internal Thought / Reasoning
                  _buildSectionBox(
                    title:
                        'Falanqaynta & Fikirka Gudaha ee AI-ga (Internal Reasoning)',
                    icon: Icons.lightbulb_rounded,
                    color: const Color(0xFFF59E0B),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Text(
                        trace.internalThought.isNotEmpty
                            ? trace.internalThought
                            : 'Falanqayn dheeraad ah lama diiwaangelin.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  _buildSectionBox(
                    title: 'Go’aanka Isticmaalka Tools-ka',
                    icon: Icons.extension_rounded,
                    color: const Color(0xFF0EA5E9),
                    child: _buildToolUsageSummary(trace),
                  ),

                  const SizedBox(height: 14),

                  // 4. Tools Execution Timeline
                  _buildSectionBox(
                    title: 'Go’aanka AI-ga iyo Tool Calls-ka',
                    icon: Icons.alt_route_rounded,
                    color: const Color(0xFF8B5CF6),
                    child: Column(
                      children: trace.toolCalls.isEmpty
                          ? [
                              const Text(
                                'Wax tool-call ah lama diiwaangelin.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ]
                          : trace.toolCalls.map(_buildToolCallStep).toList(),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 5. Matched Content & Verification Result
                  if (trace.matchedLessonTitle != null) ...[
                    _buildSectionBox(
                      title: 'Casharka La Helay & Dulucda Kooban',
                      icon: Icons.menu_book_rounded,
                      color: const Color(0xFF10B981),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${trace.matchedBookTitle} (${trace.matchedCategory})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (trace.startPage != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Bogagga ${trace.startPage}-${trace.endPage}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '• Cutubka: ${trace.matchedChapterTitle ?? ""}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            '• Casharka: ${trace.matchedLessonTitle ?? ""}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0022FF),
                            ),
                          ),
                          if (trace.concisePreviewAnswer != null) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Dulucda Kooban ee Hubinta:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black54,
                              ),
                            ),
                            Text(
                              trace.concisePreviewAnswer!,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // 6. Final AI Answer & Response
                  _buildSectionBox(
                    title: 'Jawaabta Model-ka & Natiijada (Final AI Response)',
                    icon: Icons.psychology_rounded,
                    color: const Color(0xFF059669),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: trace.isSuccess
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: trace.isSuccess
                              ? Colors.grey.shade300
                              : const Color(0xFFFCA5A5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (trace.modelName != null) ...[
                            Row(
                              children: [
                                const Icon(
                                  Icons.smart_toy_rounded,
                                  size: 14,
                                  color: Color(0xFF0022FF),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Model: ${trace.modelName}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0022FF),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  formatTraceDuration(trace.totalLatencyMs),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                          ],
                          if (trace.finalAnswer != null &&
                              trace.finalAnswer!.isNotEmpty)
                            SelectableText(
                              trace.finalAnswer!,
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.45,
                                color: Colors.black87,
                              ),
                            )
                          else if (trace.errorMessage != null)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Color(0xFFDC2626),
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SelectableText(
                                    trace.errorMessage!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFB91C1C),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              trace.internalThought.isNotEmpty
                                  ? trace.internalThought
                                  : 'Jawaab toos ah ayaa la siiyay ardayga.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 7. Student Confirmation Feedback
                  _buildSectionBox(
                    title: 'Jawaabtii Ardayga (Feedback & Confirmation)',
                    icon: Icons.how_to_reg_rounded,
                    color: trace.status == AgentVerificationStatus.accepted
                        ? const Color(0xFF10B981)
                        : (trace.status == AgentVerificationStatus.rejected
                              ? const Color(0xFFEF4444)
                              : Colors.orange),
                    child: Row(
                      children: [
                        Icon(
                          trace.status == AgentVerificationStatus.accepted
                              ? Icons.check_circle_rounded
                              : (trace.status ==
                                        AgentVerificationStatus.rejected
                                    ? Icons.cancel_rounded
                                    : Icons.hourglass_top_rounded),
                          color:
                              trace.status == AgentVerificationStatus.accepted
                              ? const Color(0xFF10B981)
                              : (trace.status ==
                                        AgentVerificationStatus.rejected
                                    ? const Color(0xFFEF4444)
                                    : Colors.orange),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trace.status == AgentVerificationStatus.accepted
                                    ? 'Ardaygu wuu aqbalay oo xaqiijiyay'
                                    : (trace.status ==
                                              AgentVerificationStatus.rejected
                                          ? 'Ardaygu wuu diiday (wuxuu rabay wax kale)'
                                          : 'Waxaa la sugayaa jawaabta ardayga'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                              if (trace.studentFeedback != null) ...[
                                Text(
                                  'Qoraalkii ardayga: "${trace.studentFeedback}"',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolUsageSummary(AgentExecutionTrace trace) {
    final invokedTools = trace.toolCalls
        .where(
          (call) =>
              call.toolId != 'intent_router' &&
              call.toolId != 'conversation_memory',
        )
        .toList();
    final used = invokedTools.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          used ? Icons.check_circle_rounded : Icons.chat_bubble_rounded,
          color: used ? const Color(0xFF059669) : const Color(0xFF64748B),
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            used
                ? 'AI-gu wuxuu adeegsaday ${invokedTools.length} tool: ${invokedTools.map((call) => call.toolName).join(', ')}.'
                : 'AI-gu wuxuu doortay jawaab toos ah; tool-ka raadinta manhajka ama PDF-ka lama adeegsan.',
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionBox({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildToolCallStep(AgentToolCallLog call) {
    return _buildRichToolCallCard(call);
  }

  // ===========================================================================
  // 2. TOOLS REGISTRY & CONFIGURATION VIEW
  // ===========================================================================

  Widget _buildToolsRegistryView() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.extension_rounded, color: Color(0xFF0022FF)),
              SizedBox(width: 8),
              Text(
                'Tools-ka uu Agent-ku Adeegsado (Autonomous Tools Registry)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Halkan waxaad ka shidi kartaa ama ku damin kartaa tools-ka uu Agent-ku isticmaalo marka ardaydu wax weydiiyaan.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: _toolConfigs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final tool = _toolConfigs[index];
                return _buildToolConfigCard(tool);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolConfigCard(AgentToolConfig tool) {
    final usageCount = _summary?.toolUsageCounts[tool.id] ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: tool.isEnabled
              ? const Color(0xFF0022FF).withValues(alpha: 0.3)
              : Colors.grey.shade300,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tool.isEnabled
                  ? const Color(0xFF0022FF).withValues(alpha: 0.1)
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.extension_rounded,
              color: tool.isEnabled
                  ? const Color(0xFF0022FF)
                  : Colors.grey.shade500,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      tool.somaliTitle,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tool.id,
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const Spacer(),
                    Switch(
                      value: tool.isEnabled,
                      activeColor: const Color(0xFF0022FF),
                      onChanged: (val) => _toggleTool(tool.id, val),
                    ),
                  ],
                ),
                Text(
                  tool.name,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'La isticmaalay: $usageCount jeer',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: usageCount > 0
                        ? const Color(0xFF059669)
                        : Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tool.description,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                if (tool.parameters.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      'Parameters: ${jsonEncode(tool.parameters)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
