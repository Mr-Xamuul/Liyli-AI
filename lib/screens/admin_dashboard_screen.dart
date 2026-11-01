import 'dart:async';

import 'package:flutter/material.dart';

import '../models/ai_model_config.dart';
import '../models/app_telemetry_log.dart';
import '../models/agent_execution_trace.dart';
import '../models/prepared_book.dart';
import '../services/admin_auth_service.dart';
import '../services/ai_model_storage.dart';
import '../services/app_telemetry_storage.dart';
import '../services/agent_trace_storage.dart';
import '../services/prepared_book_storage.dart';
import '../widgets/ai_admin/ai_management_workspace.dart';
import '../widgets/agent_admin/agent_observability_workspace.dart';
import '../widgets/book_admin/book_management_workspace.dart';
import '../widgets/telemetry_admin/app_monitoring_workspace.dart';
import '../models/user_profile.dart';
import '../services/user_auth_service.dart';
import '../widgets/user_admin/user_management_workspace.dart';
import '../widgets/finance_admin/finance_management_workspace.dart';

/// AdminDashboardScreen
/// Optimized specifically for Windows Desktop and wide screens.
/// Features a left navigation sidebar separating:
/// 1. Dashboard
/// 2. Book Manage (Buugaagta)
/// 3. AI Management (5-stage Topbar: Models, Test, Diyaar ah, App Routing, API Keys)
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    required this.onOpenEditor,
    this.onBackToChat,
    this.onOpenLibrary,
    this.onOpenChatWithBook,
    this.initialSidebarIndex = 0,
    this.initialBookStageIndex = 0,
    this.initialBook,
  });

  /// Opens the editor with parameters
  final void Function({
    PreparedBook? book,
    int initialTabIndex,
    int? chapterIndex,
    int? lessonIndex,
    int? sectionIndex,
    bool returnToPreview,
  })
  onOpenEditor;
  final VoidCallback? onBackToChat;
  final VoidCallback? onOpenLibrary;
  final void Function(PreparedBook book)? onOpenChatWithBook;
  final int initialSidebarIndex;
  final int initialBookStageIndex;
  final PreparedBook? initialBook;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _adminAuth = AdminAuthService.instance;
  final _bookStorage = const PreparedBookStorage();
  final _aiStorage = const AiModelStorage();
  final _telemetryStorage = AppTelemetryStorage.instance;
  final _agentTraceStorage = AgentTraceStorage.instance;

  // 0 = Dashboard, 1 = Book Manage, 2 = AI Management, 3 = App Telemetry
  int _currentSidebarIndex = 0;

  List<PreparedBook> _books = const [];
  List<AiModelConfig> _aiModels = const [];
  List<UserProfile> _users = const [];
  TelemetrySummary? _telemetrySummary;
  bool _loading = true;
  bool _refreshing = false;
  bool _hasLoadedDashboard = false;

  @override
  void initState() {
    super.initState();
    _currentSidebarIndex = widget.initialSidebarIndex;
    _loadDashboardData();
    unawaited(_agentTraceStorage.startLiveExecutionMonitoring());
  }

  @override
  void didUpdateWidget(covariant AdminDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSidebarIndex != oldWidget.initialSidebarIndex) {
      _currentSidebarIndex = widget.initialSidebarIndex;
    }
  }

  Future<void> _loadDashboardData() async {
    if (_refreshing) return;
    final isFirstLoad = !_hasLoadedDashboard;
    setState(() {
      if (isFirstLoad) {
        _loading = true;
      } else {
        _refreshing = true;
      }
    });
    try {
      final books = await _bookStorage.loadAll();
      final models = await _aiStorage.getModels();
      final telemetrySummary = await _telemetryStorage.getSummary();
      final users = await UserAuthService.instance.getAllUsers();
      if (!mounted) return;
      setState(() {
        _books = books;
        _aiModels = models;
        _telemetrySummary = telemetrySummary;
        _users = users;
        _loading = false;
        _refreshing = false;
        _hasLoadedDashboard = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  int get _publishedBooksCount => _books.where((b) => b.isPublished).length;
  int get _draftBooksCount => _books.where((b) => !b.isPublished).length;
  int get _activeAiModelsCount => _aiModels.where((m) => m.isActive).length;
  int get _readyAiModelsCount =>
      _aiModels.where((m) => m.status == 'ready').length;
  int get _totalMessagesCount => _telemetrySummary?.totalMessages ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Slate 100 Windows background
      body: Row(
        children: [
          // ==================== Left Desktop Sidebar ====================
          _buildDesktopSidebar(theme),

          // ==================== Right Main Workspace ====================
          Expanded(
            child: Column(
              children: [
                _buildDesktopTopBar(theme),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                          child: _buildSelectedWorkspaceView(theme),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Left Sidebar navigation dividing into the 3 requested primary sections
  Widget _buildDesktopSidebar(ThemeData theme) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Slate 900 professional dark sidebar
        border: Border(
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // App & Admin Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0022FF).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF0022FF).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Image.asset(
                        'assets/icon-Leyli AI.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Leyli AI Admin',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            'Windows Control Suite',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 16),

              // Navigation Label
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                child: Text(
                  'MAAMULKA GUUD',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ),

              // Sidebar Items: 1. Dashboard, 2. Book Manage, 3. AI Management, 4. Telemetry & Monitoring
              _buildSidebarNavItem(
                index: 0,
                icon: Icons.dashboard_rounded,
                label: 'Dashboard',
                badge: null,
              ),
              _buildSidebarNavItem(
                index: 1,
                icon: Icons.menu_book_rounded,
                label: 'Buugaagta (Book Manage)',
                badge: '${_books.length}',
              ),
              _buildSidebarNavItem(
                index: 2,
                icon: Icons.smart_toy_rounded,
                label: 'Maamulka AI-ga (AI Manage)',
                badge: '5 Stages',
              ),
              _buildSidebarNavItem(
                index: 3,
                icon: Icons.monitor_heart_rounded,
                label: 'Kormeerka App-ka (Telemetry)',
                badge: '$_totalMessagesCount Msg',
              ),
              _buildSidebarNavItem(
                index: 4,
                icon: Icons.psychology_rounded,
                label: 'Kormeerka Agent-ka (Agent Center)',
                badge: 'Live Traces',
              ),
              _buildSidebarNavItem(
                index: 5,
                icon: Icons.people_alt_rounded,
                label: 'Ardayda (Users & Students)',
                badge: '${_users.length}',
              ),
              _buildSidebarNavItem(
                index: 6,
                icon: Icons.account_balance_wallet_rounded,
                label: 'Dhaqaalaha & Lacagta (Finance)',
                badge: 'VIP Hub',
              ),

              const SizedBox(height: 24),

              // Shortcuts to Student Chat & Library
              const Divider(color: Colors.white12, height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (widget.onBackToChat != null)
                      ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        tileColor: Colors.white.withValues(alpha: 0.05),
                        leading: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: Colors.white70,
                          size: 18,
                        ),
                        title: const Text(
                          'Ku noqo AI Chat-ka',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        onTap: widget.onBackToChat,
                      ),
                    const SizedBox(height: 8),
                    if (widget.onOpenLibrary != null)
                      ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        tileColor: Colors.white.withValues(alpha: 0.05),
                        leading: const Icon(
                          Icons.local_library_outlined,
                          color: Colors.white70,
                          size: 18,
                        ),
                        title: const Text(
                          'Maktabadda Ardayda',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        onTap: widget.onOpenLibrary,
                      ),
                    const SizedBox(height: 12),
                    // Admin Mode tag
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF16A34A).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 3.5,
                            backgroundColor: Color(0xFF22C55E),
                          ),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Local Admin Active',
                              style: TextStyle(
                                color: Color(0xFF22C55E),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
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
    );
  }

  Widget _buildSidebarNavItem({
    required int index,
    required IconData icon,
    required String label,
    required String? badge,
  }) {
    final isSelected = _currentSidebarIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: InkWell(
        onTap: () => setState(() => _currentSidebarIndex = index),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0022FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey.shade400,
                size: 19,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey.shade300,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey.shade400,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Top Bar inside main workspace
  Widget _buildDesktopTopBar(ThemeData theme) {
    String title = 'Admin Dashboard';
    String subtitle = 'Kormeerka guud ee xogta iyo nidaamka';

    if (_currentSidebarIndex == 1) {
      title = 'Maamulka Buugaagta (Book Manage)';
      subtitle =
          '5-ta Marxaladood: 1. Upload ➔ 2. Editor ➔ 3. Preview ➔ 4. Diyaar ah ➔ 5. Maktabadda';
    } else if (_currentSidebarIndex == 2) {
      title = 'Hormarinta & Maamulka AI-ga (AI Management)';
      subtitle =
          '5-ta Marxaladood: Models ➔ Test ➔ Diyaar ah ➔ App Routing ➔ API Keys';
    } else if (_currentSidebarIndex == 3) {
      title = 'Kormeerka Shaqada App-ka (App Telemetry & Analytics)';
      subtitle =
          'Fariimaha la diray, moodellada jawaabay, xawaaraha (latency), iyo fashilaadaha';
    } else if (_currentSidebarIndex == 4) {
      title = 'Kormeerka & Maamulka Agent-ka (Agent Center)';
      subtitle =
          'Live Execution Traces, Internal Reasoning, iyo Maamulka Tools-ka Agent-ka';
    } else if (_currentSidebarIndex == 5) {
      title = 'Maamulka & Kormeerka Ardayda (User Management)';
      subtitle =
          'Xogta ardayda, fasalladooda (Form 1 - Form 4), iyo kormeerka duruusta & Chat History-ga';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dib u cusbooneysii xogta',
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _refreshing ? null : _loadDashboardData,
          ),
        ],
      ),
    );
  }

  /// Selected Workspace View switcher
  Widget _buildSelectedWorkspaceView(ThemeData theme) {
    switch (_currentSidebarIndex) {
      case 0:
        return _buildDashboardPane(theme);
      case 1:
        return BookManagementWorkspace(
          key: ValueKey(
            'book_workspace_${widget.initialBookStageIndex}_${widget.initialBook?.id}_${widget.initialBook?.updatedAt?.millisecondsSinceEpoch}',
          ),
          initialStageIndex: widget.initialBookStageIndex,
          initialBook: widget.initialBook,
          onOpenEditor:
              (
                book, {
                chapterIndex,
                lessonIndex,
                sectionIndex,
                returnToPreview = false,
              }) {
                widget.onOpenEditor(
                  book: book,
                  initialTabIndex: 0,
                  chapterIndex: chapterIndex,
                  lessonIndex: lessonIndex,
                  sectionIndex: sectionIndex,
                  returnToPreview: returnToPreview,
                );
              },
          onOpenChat: (book) {
            if (widget.onOpenChatWithBook != null) {
              widget.onOpenChatWithBook!(book);
            } else if (widget.onBackToChat != null) {
              widget.onBackToChat!();
            }
          },
        );
      case 2:
        return const AiManagementWorkspace();
      case 3:
        return const AppMonitoringWorkspace();
      case 4:
        return const AgentObservabilityWorkspace();
      case 5:
        return const UserManagementWorkspace();
      case 6:
        return const FinanceManagementWorkspace();
      default:
        return _buildDashboardPane(theme);
    }
  }

  // ==================== ADMIN DASHBOARD ====================
  Widget _buildDashboardPane(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1080;
        final twoColumns = constraints.maxWidth >= 700;
        final workspacesWidth = wide
            ? (constraints.maxWidth - 20) * 7 / 11
            : constraints.maxWidth;
        final workspaceCardWidth = twoColumns
            ? (workspacesWidth - 14) / 2
            : workspacesWidth;
        final workspaceCards = [
          _buildWorkspaceCard(
            icon: Icons.menu_book_rounded,
            color: const Color(0xFF3157D5),
            title: 'Maktabadda',
            description:
                'Soo geli buugaag, habee casharrada, kadibna u daabac ardayda.',
            metric: '$_publishedBooksCount buug oo daabacan',
            detail: '$_draftBooksCount qabyo',
            onTap: () => _openWorkspace(1),
          ),
          _buildWorkspaceCard(
            icon: Icons.smart_toy_rounded,
            color: const Color(0xFF7654D6),
            title: 'Maamulka AI-ga',
            description:
                'Habee models, API keys, kala hormarinta iyo tijaabooyinka.',
            metric: '$_readyAiModelsCount model oo diyaar ah',
            detail: '$_activeAiModelsCount firfircoon',
            onTap: () => _openWorkspace(2),
          ),
          _buildWorkspaceCard(
            icon: Icons.monitor_heart_rounded,
            color: const Color(0xFF0F9B78),
            title: 'Kormeerka App-ka',
            description:
                'La soco fariimaha AI-ga, xawaaraha jawaabta iyo fashilaadaha.',
            metric: '$_totalMessagesCount fariimood',
            detail: '${_telemetrySummary?.totalModelFailures ?? 0} fashil',
            onTap: () => _openWorkspace(3),
          ),
          _buildAgentWorkspaceCard(),
          _buildWorkspaceCard(
            icon: Icons.people_alt_rounded,
            color: const Color(0xFF3478B9),
            title: 'Ardayda',
            description:
                'Maamul profile-yada, fasallada iyo xogta waxbarashada.',
            metric: '${_users.length} arday',
            detail: 'Users & chat history',
            onTap: () => _openWorkspace(5),
          ),
          _buildWorkspaceCard(
            icon: Icons.account_balance_wallet_rounded,
            color: const Color(0xFFB7791F),
            title: 'Dhaqaalaha',
            description: 'Qorshaha lacag-bixinta iyo rukhsadaha VIP-ga.',
            metric: 'Marxaladda xigta',
            detail: 'Lacag-bixintu weli lama darin',
            onTap: () => _openWorkspace(6),
          ),
        ];

        final workspaces = Wrap(
          spacing: 14,
          runSpacing: 14,
          children: workspaceCards
              .map((card) => SizedBox(width: workspaceCardWidth, child: card))
              .toList(),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDashboardWelcome(),
              const SizedBox(height: 18),
              _buildDashboardMetrics(constraints.maxWidth),
              const SizedBox(height: 26),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeading(
                            'Qaybaha maamulka',
                            'Shaqada aad rabto si toos ah uga fur.',
                          ),
                          const SizedBox(height: 14),
                          workspaces,
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSystemOverviewCard(),
                          const SizedBox(height: 14),
                          _buildQuickActionsCard(),
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                _buildSectionHeading(
                  'Qaybaha maamulka',
                  'Shaqada aad rabto si toos ah uga fur.',
                ),
                const SizedBox(height: 14),
                workspaces,
                const SizedBox(height: 18),
                _buildSystemOverviewCard(),
                const SizedBox(height: 14),
                _buildQuickActionsCard(),
              ],
            ],
          ),
        );
      },
    );
  }

  void _openWorkspace(int index) {
    setState(() => _currentSidebarIndex = index);
  }

  Widget _buildDashboardWelcome() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 20, 22),
      decoration: BoxDecoration(
        color: const Color(0xFF101B3C),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'XARUNTA MAAMULKA',
                    style: TextStyle(
                      color: Color(0xFFC7D2FE),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Ku soo dhawoow, ${_adminAuth.adminName}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Maamul waxbarashada, AI-ga iyo adeegyada Leyli AI hal meel.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 17),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _openWorkspace(1),
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('Maamul buugaagta'),
                      style: FilledButton.styleFrom(
                        foregroundColor: const Color(0xFF101B3C),
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openWorkspace(2),
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: const Text('Dejinta AI-ga'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.34),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            padding: const EdgeInsets.all(15),
            child: Image.asset('assets/icon-Leyli AI.png', fit: BoxFit.contain),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardMetrics(double width) {
    final columns = width >= 1280
        ? 5
        : width >= 850
        ? 3
        : 2;
    final cardWidth = (width - (columns - 1) * 12) / columns;
    final metrics = [
      _buildMetricTile(
        label: 'Buugaag la daabacay',
        value: '$_publishedBooksCount',
        helper: '$_draftBooksCount qabyo',
        icon: Icons.auto_stories_rounded,
        color: const Color(0xFF3157D5),
        onTap: () => _openWorkspace(1),
      ),
      _buildMetricTile(
        label: 'AI diyaar ah',
        value: '$_readyAiModelsCount',
        helper: '$_activeAiModelsCount firfircoon',
        icon: Icons.smart_toy_rounded,
        color: const Color(0xFF7654D6),
        onTap: () => _openWorkspace(2),
      ),
      _buildMetricTile(
        label: 'Ardayda',
        value: '${_users.length}',
        helper: 'profile-yo la maamulo',
        icon: Icons.people_alt_rounded,
        color: const Color(0xFF3478B9),
        onTap: () => _openWorkspace(5),
      ),
      _buildMetricTile(
        label: 'Fariimaha AI-ga',
        value: '$_totalMessagesCount',
        helper: 'wadarta telemetry-ga',
        icon: Icons.forum_outlined,
        color: const Color(0xFF0F9B78),
        onTap: () => _openWorkspace(3),
      ),
      _buildAgentMetricTile(),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: metrics
          .map((tile) => SizedBox(width: cardWidth, child: tile))
          .toList(),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required String helper,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return _DashboardPanel(
      padding: const EdgeInsets.all(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            _DashboardIcon(icon: icon, color: color, size: 40),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF17223B),
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    helper,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_outward_rounded,
              size: 15,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentMetricTile() {
    return ValueListenableBuilder<List<AgentLiveExecution>>(
      valueListenable: _agentTraceStorage.liveExecutionsNotifier,
      builder: (context, executions, _) {
        final count = executions.where((item) => !item.isCompleted).length;
        return _buildMetricTile(
          label: 'Agent socda',
          value: '$count',
          helper: count == 0 ? 'hawl socota ma jirto' : 'Realtime monitoring',
          icon: Icons.bolt_rounded,
          color: const Color(0xFFD88427),
          onTap: () => _openWorkspace(4),
        );
      },
    );
  }

  Widget _buildSectionHeading(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF17223B),
            letterSpacing: -0.25,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildWorkspaceCard({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    required String metric,
    required String detail,
    required VoidCallback onTap,
  }) {
    return _DashboardPanel(
      padding: const EdgeInsets.all(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _DashboardIcon(icon: icon, color: color, size: 42),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 17,
                  color: Colors.grey.shade500,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF17223B),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: Text(
                    metric,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentWorkspaceCard() {
    return ValueListenableBuilder<List<AgentLiveExecution>>(
      valueListenable: _agentTraceStorage.liveExecutionsNotifier,
      builder: (context, executions, _) {
        final count = executions.where((item) => !item.isCompleted).length;
        return _buildWorkspaceCard(
          icon: Icons.psychology_alt_rounded,
          color: const Color(0xFFD88427),
          title: 'Agent Center',
          description:
              'La soco shaqooyinka AI-ga inta ay socdaan iyo raad-raacyadooda.',
          metric: '$count hawlood oo socda',
          detail: 'Live',
          onTap: () => _openWorkspace(4),
        );
      },
    );
  }

  Widget _buildSystemOverviewCard() {
    return _DashboardPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeading(
            'Xaaladda nidaamka',
            'Dulmar kooban oo adeegyada ah.',
          ),
          const SizedBox(height: 15),
          _buildStatusRow(
            icon: Icons.menu_book_rounded,
            color: const Color(0xFF3157D5),
            title: 'Maktabadda',
            value: '$_publishedBooksCount la daabacay',
          ),
          const SizedBox(height: 12),
          _buildStatusRow(
            icon: Icons.smart_toy_rounded,
            color: const Color(0xFF7654D6),
            title: 'AI models',
            value: '$_readyAiModelsCount diyaar',
          ),
          const SizedBox(height: 12),
          _buildStatusRow(
            icon: Icons.monitor_heart_rounded,
            color: const Color(0xFF0F9B78),
            title: 'Telemetry',
            value: '${_telemetrySummary?.totalModelFailures ?? 0} fashil',
          ),
          const SizedBox(height: 12),
          _buildStatusRow(
            icon: Icons.people_alt_rounded,
            color: const Color(0xFF3478B9),
            title: 'Ardayda',
            value: '${_users.length} profile',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
  }) {
    return Row(
      children: [
        _DashboardIcon(icon: icon, color: color, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF29354F),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildQuickActionsCard() {
    return _DashboardPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeading(
            'Hawlaha degdegga ah',
            'Hal gujin ku gal shaqada.',
          ),
          const SizedBox(height: 12),
          _buildQuickAction(
            icon: Icons.upload_file_rounded,
            title: 'Buug cusub geli',
            color: const Color(0xFF3157D5),
            onTap: () => _openWorkspace(1),
          ),
          const SizedBox(height: 8),
          _buildQuickAction(
            icon: Icons.settings_suggest_rounded,
            title: 'Habee AI-ga',
            color: const Color(0xFF7654D6),
            onTap: () => _openWorkspace(2),
          ),
          if (widget.onBackToChat != null) ...[
            const SizedBox(height: 8),
            _buildQuickAction(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Ku noqo AI Chat-ka',
              color: const Color(0xFF0F9B78),
              onTap: widget.onBackToChat!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF7F8FC),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF29354F),
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EAF1)),
      ),
      child: child,
    );
  }
}

class _DashboardIcon extends StatelessWidget {
  const _DashboardIcon({
    required this.icon,
    required this.color,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}
