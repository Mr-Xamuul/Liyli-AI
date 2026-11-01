import 'package:flutter/material.dart';
import '../../models/chat_session.dart';
import '../../models/user_profile.dart';
import '../../services/chat_history_storage.dart';
import '../../services/user_auth_service.dart';
import '../google_logo_widget.dart';
import '../rich_tutor_markdown.dart';

/// Modal dialog for detailed inspection of a student's profile,
/// academic class, and full history of lessons and AI conversations.
class UserDetailHistoryDialog extends StatefulWidget {
  const UserDetailHistoryDialog({
    super.key,
    required this.user,
    required this.onUserUpdated,
  });

  final UserProfile user;
  final VoidCallback onUserUpdated;

  static Future<void> show(
    BuildContext context, {
    required UserProfile user,
    required VoidCallback onUserUpdated,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => UserDetailHistoryDialog(
        user: user,
        onUserUpdated: onUserUpdated,
      ),
    );
  }

  @override
  State<UserDetailHistoryDialog> createState() => _UserDetailHistoryDialogState();
}

class _UserDetailHistoryDialogState extends State<UserDetailHistoryDialog> {
  final _historyStorage = const ChatHistoryStorage();
  final _authService = UserAuthService.instance;

  late UserProfile _currentUser;
  List<ChatSession> _sessions = [];
  bool _loading = true;
  ChatSession? _selectedSession;

  static const _availableForms = ['Form 1', 'Form 2', 'Form 3', 'Form 4'];

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _loadUserHistory();
  }

  Future<void> _loadUserHistory() async {
    setState(() => _loading = true);
    try {
      final list = await _historyStorage.loadAll(forUserId: _currentUser.id);
      if (mounted) {
        setState(() {
          _sessions = list;
          _loading = false;
          if (_selectedSession != null) {
            _selectedSession = list.where((s) => s.id == _selectedSession!.id).firstOrNull;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int get _totalQuestionsAsked {
    int count = 0;
    for (final s in _sessions) {
      count += s.messages.where((m) => m.isUser).length;
    }
    return count;
  }

  Set<String> get _booksStudied {
    final set = <String>{};
    for (final s in _sessions) {
      if (s.bookTitle != null && s.bookTitle!.trim().isNotEmpty) {
        set.add(s.bookTitle!.trim());
      }
    }
    return set;
  }

  Future<void> _changeUserForm(String newForm) async {
    final messenger = ScaffoldMessenger.of(context);
    final updated = _currentUser.copyWith(selectedForm: newForm);
    await _authService.updateUser(updated);
    setState(() => _currentUser = updated);
    widget.onUserUpdated();
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Fasalka ${_currentUser.displayName} waxaa loo beddelay $newForm'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _editUserName() async {
    final ctrl = TextEditingController(text: _currentUser.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Beddel Magaca Ardayga'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Magaca Buuxa',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Jooji'),
          ),
          FilledButton(
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) Navigator.pop(ctx, val);
            },
            child: const Text('Keydi'),
          ),
        ],
      ),
    );

    if (newName != null && newName != _currentUser.displayName) {
      final updated = _currentUser.copyWith(displayName: newName);
      await _authService.updateUser(updated);
      setState(() => _currentUser = updated);
      widget.onUserUpdated();
    }
  }

  Future<void> _deleteSession(ChatSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ma hubtaa inaad tirtirto sheekadan?'),
        content: Text('Sheekada "${session.title}" gabi ahaanba waa la tirtirayaa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Maya'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Tirtir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _historyStorage.deleteSession(session.id, forUserId: _currentUser.id);
      if (_selectedSession?.id == session.id) {
        setState(() => _selectedSession = null);
      }
      await _loadUserHistory();
      widget.onUserUpdated();
    }
  }

  Future<void> _clearAllUserHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tirtir Dhammaan History-ga?'),
        content: Text(
          'Ma hubtaa inaad tirtirto dhammaan ${_sessions.length} sheeko ee uu ${_currentUser.displayName} la yeeshay AI-ga?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Maya'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Tirtir Dhammaan'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _historyStorage.clearAll(forUserId: _currentUser.id);
      setState(() => _selectedSession = null);
      await _loadUserHistory();
      widget.onUserUpdated();
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = _authService.currentUserId == _currentUser.id;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 960,
          maxHeight: 720,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Modal Bar
            _buildHeader(theme, isActive),
            const Divider(height: 1),

            // Main Body: User Profile Card & Study History split
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Side: User Profile & Metrics Panel (width 320)
                  SizedBox(
                    width: 320,
                    child: _buildLeftProfilePanel(theme, isActive),
                  ),
                  const VerticalDivider(width: 1),

                  // Right Side: History Sessions List or Full Chat Inspector
                  Expanded(
                    child: _selectedSession == null
                        ? _buildHistorySessionsList(theme)
                        : _buildSessionChatInspector(theme, _selectedSession!),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isActive) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Color(_currentUser.avatarColorValue),
            child: Text(
              _currentUser.initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _currentUser.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0022FF).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _currentUser.selectedForm,
                        style: const TextStyle(
                          color: Color(0xFF0022FF),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _currentUser.isSubscriptionActive
                            ? const Color(0xFFFEF3C7)
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _currentUser.isSubscriptionActive
                                ? Icons.workspace_premium_rounded
                                : Icons.bolt_rounded,
                            size: 12,
                            color: _currentUser.isSubscriptionActive
                                ? const Color(0xFFD97706)
                                : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _currentUser.tierLabel,
                            style: TextStyle(
                              color: _currentUser.isSubscriptionActive
                                  ? const Color(0xFFB45309)
                                  : Colors.grey.shade800,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Kuxiran (Active Hadda)',
                          style: TextStyle(
                            color: Color(0xFF059669),
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  'Kormeerka xogta ardayga & waxyaabihii uu bartay (Study History)',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Xir',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftProfilePanel(ThemeData theme, bool isActive) {
    final books = _booksStudied;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Google Account Badge Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    GoogleLogoWidget(size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Google Account',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _currentUser.email,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${_currentUser.id}',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Diiwaangashay:',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    Text(
                      _formatDate(_currentUser.createdAt),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Dhowaan galay:',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    Text(
                      _formatDate(_currentUser.lastLoginAt),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Subscription & Paid Tier Admin Controls
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _currentUser.isSubscriptionActive
                  ? const Color(0xFFFFFBEB)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _currentUser.isSubscriptionActive
                    ? const Color(0xFFFDE68A)
                    : Colors.grey.shade300,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _currentUser.isSubscriptionActive
                              ? Icons.workspace_premium_rounded
                              : Icons.bolt_rounded,
                          size: 18,
                          color: _currentUser.isSubscriptionActive
                              ? const Color(0xFFD97706)
                              : Colors.grey.shade700,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _currentUser.isSubscriptionActive
                              ? 'Paid Tier (VIP)'
                              : 'Free Tier',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _currentUser.isSubscriptionActive
                                ? const Color(0xFF92400E)
                                : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _currentUser.isSubscriptionActive
                            ? const Color(0xFF16A34A)
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _currentUser.isSubscriptionActive ? 'ACTIVE' : 'FREE',
                        style: TextStyle(
                          color: _currentUser.isSubscriptionActive
                              ? Colors.white
                              : Colors.grey.shade800,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_currentUser.isSubscriptionActive) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Qorshaha: ${_currentUser.planName == 'yearly' ? 'Sannadle (\$40/yr)' : 'Bille (\$5/mo)'}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    'Habka: ${_currentUser.paymentMethod ?? 'Direct'} (${_currentUser.paymentPhone ?? ''})',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                  if (_currentUser.subscriptionExpiresAt != null)
                    Text(
                      'Dhicitaanka: ${_formatDate(_currentUser.subscriptionExpiresAt!)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFFB45309)),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _authService.cancelSubscription(_currentUser.id);
                        final updated = await _authService.getUserById(_currentUser.id);
                        if (updated != null && mounted) {
                          setState(() => _currentUser = updated);
                          widget.onUserUpdated();
                        }
                      },
                      icon: const Icon(Icons.cancel_outlined, size: 14, color: Colors.red),
                      label: const Text('Ka qaad VIP (Dib ugu celi Free)', style: TextStyle(fontSize: 11, color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 6),
                  Text(
                    'Ardaygani wuxuu isticmaalayaa Free Tier. Ma helo moodallada VIP-da ee Paid Tier.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await _authService.activateSubscription(
                          userId: _currentUser.id,
                          planName: 'monthly',
                          paymentMethod: 'Admin Override',
                          paymentPhone: 'Admin Direct Grant',
                        );
                        final updated = await _authService.getUserById(_currentUser.id);
                        if (updated != null && mounted) {
                          setState(() => _currentUser = updated);
                          widget.onUserUpdated();
                        }
                      },
                      icon: const Icon(Icons.workspace_premium_rounded, size: 15),
                      label: const Text('Fasax Paid Tier (Grant VIP)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Academic Class Quick Control
          const Text(
            'Fasalka Ardayga (Form):',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _currentUser.selectedForm,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            items: _availableForms
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: (val) {
              if (val != null && val != _currentUser.selectedForm) {
                _changeUserForm(val);
              }
            },
          ),
          const SizedBox(height: 16),

          // Overview Statistics
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Wadarta Sheekooyinka:', style: TextStyle(fontSize: 12)),
                    Text(
                      '${_sessions.length}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0022FF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Su\'aalaha uu weydiiyay AI:', style: TextStyle(fontSize: 12)),
                    Text(
                      '$_totalQuestionsAsked',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Buugaagta uu furtay:', style: TextStyle(fontSize: 12)),
                    Text(
                      '${books.length}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Books Studied Badges
          if (books.isNotEmpty) ...[
            const Text(
              'Buugaagta uu bartay:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: books.map((b) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.book_outlined, size: 13, color: Color(0xFF0022FF)),
                      const SizedBox(width: 4),
                      Text(
                        b,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Action Buttons
          OutlinedButton.icon(
            onPressed: _editUserName,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Beddel Magaca Ardayga'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 8),

          if (!isActive)
            FilledButton.tonalIcon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await _authService.switchAccount(_currentUser.id);
                widget.onUserUpdated();
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Waxaa loo wareegay akoonka ${_currentUser.displayName}'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.switch_account_rounded, size: 16),
              label: const Text('U wareeg Akoonkan'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),

          if (_sessions.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _clearAllUserHistory,
              icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: Colors.red),
              label: const Text(
                'Tirtir Dhammaan Duruusta',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistorySessionsList(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_stories_outlined,
                  size: 40,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Ma jiraan duruus uu bartay weli',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ardaygan (${_currentUser.displayName}) weli ma bilaabin waxbarasho ama su\'aalo lama yeelan AI-ga.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Subheader for sessions
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Duruusta & Sheekooyinka Kukeedsan (${_sessions.length})',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              Text(
                'Guji mid kasta si aad u aragto wixii uu baranayay',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // List of Sessions
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _sessions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (ctx, index) {
              final session = _sessions[index];
              final userMsgs = session.messages.where((m) => m.isUser).length;
              final aiMsgs = session.messages.where((m) => !m.isUser).length;

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _selectedSession = session),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0022FF).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.chat_bubble_outline_rounded,
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
                                    session.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      if (session.bookTitle != null) ...[
                                        Icon(
                                          Icons.menu_book_rounded,
                                          size: 13,
                                          color: Colors.grey.shade600,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            session.bookTitle!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Text(
                                        _formatDate(session.updatedAt),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Tag showing total messages
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$userMsgs Qs • $aiMsgs As',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                              color: Colors.grey.shade500,
                              tooltip: 'Tirtir sheekadan',
                              onPressed: () => _deleteSession(session),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF0022FF)),
                          ],
                        ),

                        // Focus Chapter / Lesson / Section pill if present
                        if (session.focusChapter != null || session.focusLesson != null) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (session.focusChapter != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Cutubka: ${session.focusChapter}',
                                    style: const TextStyle(fontSize: 10.5, color: Colors.black87),
                                  ),
                                ),
                              if (session.focusLesson != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Casharka: ${session.focusLesson}',
                                    style: const TextStyle(fontSize: 10.5, color: Colors.black87),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Full transcript inspector: shows every message the student sent and the AI's response
  Widget _buildSessionChatInspector(ThemeData theme, ChatSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Back bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: const Color(0xFFF8FAFC),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _selectedSession = null),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Ku noqo Duruusta'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                tooltip: 'Tirtir sheekadan',
                onPressed: () => _deleteSession(session),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Messages transcript view
        Expanded(
          child: session.messages.isEmpty
              ? const Center(child: Text('Ma jiraan fariimo kukeedsan sheekadan.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: session.messages.length,
                  itemBuilder: (ctx, idx) {
                    final msg = session.messages[idx];
                    final isUser = msg.isUser;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: isUser
                                ? Color(_currentUser.avatarColorValue)
                                : const Color(0xFF0022FF),
                            child: isUser
                                ? Text(
                                    _currentUser.initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : const Icon(Icons.smart_toy_rounded, size: 14, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? const Color(0xFFF1F5F9)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isUser
                                      ? Colors.grey.shade300
                                      : const Color(0xFF0022FF).withValues(alpha: 0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        isUser
                                            ? '${_currentUser.displayName} (Ardayga)'
                                            : 'Leyli AI (Macallinka)',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: isUser ? Colors.black87 : const Color(0xFF0022FF),
                                        ),
                                      ),
                                      if (msg.scopeLabel != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            msg.scopeLabel!,
                                            style: const TextStyle(fontSize: 10, color: Colors.black54),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  RichTutorMarkdown(
                                    text: msg.text,
                                    isUser: isUser,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
