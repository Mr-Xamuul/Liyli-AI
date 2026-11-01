import 'package:flutter/material.dart';

import '../../models/app_telemetry_log.dart';
import '../../services/app_telemetry_storage.dart';

/// AppMonitoringWorkspace
/// Admin telemetry & monitoring interface designed for Windows desktop.
/// Tracks:
/// 1. Inta jeer ee app-ka fariin lagu diray (Total messages sent)
/// 2. Model-ka fariinta kasoo jawaabay iyo inta ay ku qaadatay (Model & response latency)
/// 3. Inta jeer oo model uu fashilmay iyo model-ka fashilmay (Model failure counts & breakdown)
/// 4. Fariimaha la diray, xiliga la diray, iyo hadii buug/cashar la doortay (Message audit logs & context)
class AppMonitoringWorkspace extends StatefulWidget {
  const AppMonitoringWorkspace({super.key});

  @override
  State<AppMonitoringWorkspace> createState() => _AppMonitoringWorkspaceState();
}

class _AppMonitoringWorkspaceState extends State<AppMonitoringWorkspace> {
  final _storage = AppTelemetryStorage.instance;

  List<AppTelemetryLog> _logs = [];
  TelemetrySummary? _summary;
  bool _isLoading = true;

  String _searchQuery = '';
  String _statusFilter = 'All'; // 'All', 'Success', 'Fallback', 'Failed'
  String _modelFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final logs = await _storage.getLogs();
    final summary = AppTelemetryStorage.computeSummary(logs);
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _summary = summary;
      _isLoading = false;
    });
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 10),
            Text('Nadiifi Diiwaanka Telemetry-ga'),
          ],
        ),
        content: const Text(
          'Ma hubtaa inaad tirtirto dhammaan diiwaanka xogta fariimaha iyo kormeerka app-ka? '
          'Tallaabadan dib looma noqon karo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Jooji'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Haa, Nadiifi'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storage.clearLogs();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Diiwaankii xogta app-ka si guul leh ayaa loo nadiifiyay.'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
      }
    }
  }

  List<AppTelemetryLog> get _filteredLogs {
    return _logs.where((log) {
      // Status filter
      if (_statusFilter == 'Success' && !log.isSuccess) return false;
      if (_statusFilter == 'Fallback' && !log.hadFailover) return false;
      if (_statusFilter == 'Failed' && log.isSuccess) return false;

      // Model filter
      if (_modelFilter != 'All') {
        final matchesAnswered = log.answeredModelName == _modelFilter;
        final matchesAttempt = log.attempts.any((a) => a.modelName == _modelFilter);
        if (!matchesAnswered && !matchesAttempt) return false;
      }

      // Search query filter
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesMsg = log.userMessage.toLowerCase().contains(q);
        final matchesBook = (log.bookTitle ?? '').toLowerCase().contains(q);
        final matchesLesson = (log.focusLesson ?? '').toLowerCase().contains(q);
        final matchesChapter = (log.focusChapter ?? '').toLowerCase().contains(q);
        final matchesModel = (log.answeredModelName ?? '').toLowerCase().contains(q);
        if (!matchesMsg && !matchesBook && !matchesLesson && !matchesChapter && !matchesModel) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  List<String> get _allModelNames {
    final set = <String>{};
    for (final l in _logs) {
      if (l.answeredModelName != null && l.answeredModelName!.isNotEmpty) {
        set.add(l.answeredModelName!);
      }
      for (final a in l.attempts) {
        if (a.modelName.isNotEmpty) set.add(a.modelName);
      }
    }
    return ['All', ...set.toList()..sort()];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final summary = _summary ?? AppTelemetryStorage.computeSummary(_logs);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ==================== Top Action & Info Bar ====================
          _buildTopActionBar(summary),
          const SizedBox(height: 18),

          // ==================== 4 Primary KPI Cards ====================
          _buildKpiMetricsRow(summary),
          const SizedBox(height: 20),

          // ==================== Analytical Cards: Models & Activity ====================
          _buildAnalyticalPanels(summary),
          const SizedBox(height: 20),

          // ==================== Audit Log Section (Filter & Table) ====================
          _buildLogsAuditSection(),
        ],
      ),
    );
  }

  Widget _buildTopActionBar(TelemetrySummary summary) {
    return Container(
      padding: const EdgeInsets.all(18),
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
              color: const Color(0xFF0022FF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.monitor_heart_rounded,
              color: Color(0xFF0022FF),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kormeerka Shaqada App-ka (App Telemetry & Analytics)',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Diiwaanka tooska ah ee tirada fariimaha, xawaaraha moodellada, '
                  'fashilaadaha ciriiriga, iyo macluumaadka buugga/casharka.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Cusbooneysii'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          if (_logs.isNotEmpty)
            OutlinedButton.icon(
              onPressed: _clearLogs,
              icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
              label: const Text('Nadiifi', style: TextStyle(color: Color(0xFFEF4444))),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.red.shade200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKpiMetricsRow(TelemetrySummary summary) {
    final avgLatencyText = summary.avgLatencyMs > 0
        ? '${(summary.avgLatencyMs / 1000).toStringAsFixed(2)}s'
        : '0.0s';

    final successRateText = '${summary.successRatePercent.toStringAsFixed(1)}%';

    return Row(
      children: [
        // 1. Total Messages Sent
        Expanded(
          child: _buildMetricCard(
            title: 'Wadarta Fariimaha La Diray',
            value: '${summary.totalMessages}',
            unit: 'fariin',
            icon: Icons.chat_bubble_rounded,
            color: const Color(0xFF0022FF),
            subtitle: '${summary.totalSuccess} Guul • ${summary.totalFailed} Fashil',
          ),
        ),
        const SizedBox(width: 14),

        // 2. Average Response Latency
        Expanded(
          child: _buildMetricCard(
            title: 'Celceliska Xawaaraha',
            value: avgLatencyText,
            unit: '(${summary.avgLatencyMs.toInt()} ms)',
            icon: Icons.speed_rounded,
            color: const Color(0xFF10B981),
            subtitle: 'Waqtiga moodelku ku jawaabo',
          ),
        ),
        const SizedBox(width: 14),

        // 3. Model Failures
        Expanded(
          child: _buildMetricCard(
            title: 'Fashilaadaha Moodellada',
            value: '${summary.totalModelFailures}',
            unit: 'jeer',
            icon: Icons.warning_amber_rounded,
            color: summary.totalModelFailures > 0
                ? const Color(0xFFEF4444)
                : const Color(0xFF64748B),
            subtitle: 'Ciriiri (503/429) & khaladaad',
          ),
        ),
        const SizedBox(width: 14),

        // 4. Success Rate
        Expanded(
          child: _buildMetricCard(
            title: 'Guusha Guud ee Nidaamka',
            value: successRateText,
            unit: 'Success',
            icon: Icons.verified_rounded,
            color: const Color(0xFF8B5CF6),
            subtitle: 'Auto-fallback ayaa badbaadiya',
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        unit,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticalPanels(TelemetrySummary summary) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Model Performance Breakdown (Answers, Avg Latency, Failures)
        Expanded(
          flex: 6,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.smart_toy_rounded,
                        color: Color(0xFF0284C7),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Moodellada, Xawaarahooda & Fashilaadaha',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Inta jeer ee model kasta fariin ka jawaabay, xawaaraha celceliska ah, iyo fashilaadaha',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (summary.modelSuccessCounts.isEmpty && summary.modelFailureCounts.isEmpty)
                  Container(
                    height: 120,
                    alignment: Alignment.center,
                    child: Text(
                      'Weli ma jiro xog moodel la diiwaangeliyay.',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    ),
                  )
                else
                  _buildModelPerformanceTable(summary),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),

        // Right: Books & Lessons Activity
        Expanded(
          flex: 4,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.menu_book_rounded,
                        color: Color(0xFF8B5CF6),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Buugaagta & Casharrada',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Meelaha ardaydu fariimaha ugu badan ka dirayaan',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (summary.bookUsageCounts.isEmpty)
                  Container(
                    height: 120,
                    alignment: Alignment.center,
                    child: Text(
                      'Weli ma jiro buug la doortay.',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    ),
                  )
                else
                  _buildBookUsageList(summary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModelPerformanceTable(TelemetrySummary summary) {
    final allModelKeys = {
      ...summary.modelSuccessCounts.keys,
      ...summary.modelFailureCounts.keys,
    }.toList();

    return Column(
      children: allModelKeys.map((modelName) {
        final successCount = summary.modelSuccessCounts[modelName] ?? 0;
        final failureCount = summary.modelFailureCounts[modelName] ?? 0;
        final avgLatency = summary.modelAvgLatencies[modelName] ?? 0.0;
        final avgSecText = avgLatency > 0
            ? '${(avgLatency / 1000).toStringAsFixed(2)}s'
            : '-';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF0022FF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.psychology_rounded,
                  color: Color(0xFF0022FF),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modelName,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Kasoo jawaabay: $successCount jeer',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              // Latency badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined, size: 13, color: Color(0xFF10B981)),
                    const SizedBox(width: 4),
                    Text(
                      avgSecText,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Failure badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: failureCount > 0
                      ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      failureCount > 0 ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                      size: 13,
                      color: failureCount > 0 ? const Color(0xFFEF4444) : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$failureCount Fashil',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: failureCount > 0 ? const Color(0xFFEF4444) : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBookUsageList(TelemetrySummary summary) {
    final sorted = summary.bookUsageCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxVal = sorted.isNotEmpty ? sorted.first.value : 1;

    return Column(
      children: sorted.take(5).map((entry) {
        final progress = maxVal > 0 ? (entry.value / maxVal) : 0.0;
        final isGeneral = entry.key.contains('Guud') || entry.key.contains('General');

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isGeneral ? Icons.public_rounded : Icons.book_rounded,
                    size: 14,
                    color: isGeneral ? const Color(0xFF0284C7) : const Color(0xFF8B5CF6),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entry.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  Text(
                    '${entry.value} fariin',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: Colors.grey.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isGeneral ? const Color(0xFF0284C7) : const Color(0xFF8B5CF6),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ==================== Audit Logs Table Section ====================
  Widget _buildLogsAuditSection() {
    final filtered = _filteredLogs;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header & Search / Filters
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0022FF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Color(0xFF0022FF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Diiwaanka Fariimaha La Diray (${filtered.length} Fariin)',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const Text(
                      'Taariikhda, fariinta, buugga/casharka la doortay, moodelka, iyo xawaaraha',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Filters Row
          Row(
            children: [
              // Search Input
              Expanded(
                flex: 5,
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Raadi fariin, buug, cashar, ama moodel...',
                      hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Status Filter ChoiceChips
              Wrap(
                spacing: 6,
                children: [
                  _buildStatusChip('All', 'Dhammaan'),
                  _buildStatusChip('Success', 'Guul'),
                  _buildStatusChip('Fallback', 'Fallback'),
                  _buildStatusChip('Failed', 'Fashil'),
                ],
              ),
              const SizedBox(width: 10),

              // Model Filter Dropdown
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _modelFilter,
                    icon: const Icon(Icons.arrow_drop_down_rounded),
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    items: _allModelNames.map((name) {
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(name == 'All' ? 'Dhammaan Moodellada' : name),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _modelFilter = val);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Audit Table / List
          if (filtered.isEmpty)
            Container(
              height: 160,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                _logs.isEmpty
                    ? 'Weli fariin app-ka laguma dirin. Marka ardaydu AI-ga wax weydiiyaan halkan ayaa si toos ah loogu arki doonaa!'
                    : 'Ma jiro diiwaan u dhigma raadintaada ama filtarka la doortay.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final log = filtered[index];
                return _buildLogItemRow(log);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String key, String label) {
    final isSelected = _statusFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _statusFilter = key),
      selectedColor: const Color(0xFF0022FF),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontSize: 11.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
    );
  }

  Widget _buildLogItemRow(AppTelemetryLog log) {
    final hasBook = log.bookTitle != null && log.bookTitle!.trim().isNotEmpty;
    final answeredModel = log.answeredModelName ?? 'Lama helin';
    final latencySec = log.responseTimeMs != null
        ? '${(log.responseTimeMs! / 1000).toStringAsFixed(2)}s'
        : '-';

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (!log.isSuccess) {
      statusColor = const Color(0xFFEF4444);
      statusLabel = 'Fashilmay';
      statusIcon = Icons.cancel_rounded;
    } else if (log.hadFailover) {
      statusColor = const Color(0xFFF59E0B);
      statusLabel = 'Wareegay (Fallback)';
      statusIcon = Icons.swap_horiz_rounded;
    } else {
      statusColor = const Color(0xFF16A34A);
      statusLabel = 'Guuleystay';
      statusIcon = Icons.check_circle_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Time badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                Text(
                  log.formattedTime,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  log.formattedDate,
                  style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Message & Book / Lesson info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.userMessage,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      hasBook ? Icons.menu_book_rounded : Icons.public_rounded,
                      size: 13,
                      color: hasBook ? const Color(0xFF0022FF) : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        log.bookAndScopeSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: hasBook ? const Color(0xFF0022FF) : Colors.grey.shade600,
                          fontWeight: hasBook ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Model Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.smart_toy_rounded, size: 13, color: Color(0xFF0284C7)),
                const SizedBox(width: 5),
                Text(
                  answeredModel,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Latency badge
          if (log.isSuccess)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined, size: 12, color: Color(0xFF10B981)),
                  const SizedBox(width: 4),
                  Text(
                    latencySec,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 13, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Inspect details button
          IconButton(
            tooltip: 'Eeg Faahfaahinta',
            icon: const Icon(Icons.info_outline_rounded, size: 19),
            onPressed: () => _showLogDetailsDialog(log),
          ),
        ],
      ),
    );
  }

  void _showLogDetailsDialog(AppTelemetryLog log) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0022FF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.analytics_rounded, color: Color(0xFF0022FF), size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Faahfaahinta Fariinta & AI-ga', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Question
                const Text(
                  'Fariinta / Su\'aasha Ardayga:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    log.userMessage,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
                const SizedBox(height: 14),

                // Book & Lesson details
                const Text(
                  'Buugga & Casharka La Doortay:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Buugga: ${log.bookTitle ?? 'Guud (Buug lama dooran)'}'),
                      if (log.bookCategory != null) Text('Heerka: ${log.bookCategory}'),
                      if (log.focusChapter != null) Text('Cutubka: ${log.focusChapter}'),
                      if (log.focusLesson != null) Text('Casharka: ${log.focusLesson}'),
                      if (log.focusSection != null) Text('Qaybta: ${log.focusSection}'),
                      if (log.scopeLabel != null) Text('Scope Label: ${log.scopeLabel}'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Timing & Model
                const Text(
                  'Moodelka & Xawaaraha:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Moodelka Jawaabay: ${log.answeredModelName ?? 'Lama helin'}'),
                      if (log.responseTimeMs != null)
                        Text(
                          'Waqtiga Jawaabta (Latency): ${log.responseTimeMs} ms (${(log.responseTimeMs! / 1000).toStringAsFixed(2)}s)',
                        ),
                      Text('Waqtiga la diray: ${log.formattedDateTime}'),
                      Text('Guusha: ${log.isSuccess ? 'Haa (Guuleystay)' : 'Maya (Fashilmay)'}'),
                    ],
                  ),
                ),

                // Model Attempts Breakdown (if fallback occurred)
                if (log.attempts.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Isku dayada Moodellada (Attempts & Failovers):',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  ...log.attempts.map((att) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: att.isSuccess
                            ? const Color(0xFF16A34A).withValues(alpha: 0.08)
                            : const Color(0xFFEF4444).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: att.isSuccess
                              ? const Color(0xFF16A34A).withValues(alpha: 0.3)
                              : const Color(0xFFEF4444).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                att.isSuccess ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                size: 14,
                                color: att.isSuccess ? const Color(0xFF16A34A) : const Color(0xFFEF4444),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                att.modelName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              const Spacer(),
                              Text(
                                '${att.latencyMs} ms',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                          if (att.errorMessage != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Sababta fashilka: ${att.errorMessage}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Xir'),
          ),
        ],
      ),
    );
  }
}
