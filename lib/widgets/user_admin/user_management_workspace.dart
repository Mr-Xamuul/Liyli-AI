import 'package:flutter/material.dart';
import '../../models/user_profile.dart';
import '../../services/chat_history_storage.dart';
import '../../services/user_auth_service.dart';
import '../google_logo_widget.dart';
import 'user_detail_history_dialog.dart';

/// UserManagementWorkspace
/// Admin control suite for managing and monitoring registered students,
/// inspecting their academic progress, and drilling into their study chat history.
class UserManagementWorkspace extends StatefulWidget {
  const UserManagementWorkspace({super.key});

  @override
  State<UserManagementWorkspace> createState() => _UserManagementWorkspaceState();
}

class _UserManagementWorkspaceState extends State<UserManagementWorkspace> {
  final _authService = UserAuthService.instance;
  final _historyStorage = const ChatHistoryStorage();

  List<UserProfile> _users = [];
  Map<String, int> _userSessionCounts = {};
  bool _loading = true;

  String _searchQuery = '';
  String _selectedFormFilter = 'All'; // 'All', 'Form 1', 'Form 2', 'Form 3', 'Form 4'
  String _selectedTierFilter = 'All'; // 'All', 'Free', 'Paid'

  static const _availableForms = ['Form 1', 'Form 2', 'Form 3', 'Form 4'];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    final users = await _authService.getAllUsers();
    final sessionCounts = <String, int>{};

    for (final u in users) {
      try {
        final sessions = await _historyStorage.loadAll(forUserId: u.id);
        sessionCounts[u.id] = sessions.length;
      } catch (_) {
        sessionCounts[u.id] = 0;
      }
    }

    if (!mounted) return;
    setState(() {
      _users = users;
      _userSessionCounts = sessionCounts;
      _loading = false;
    });
  }

  List<UserProfile> get _filteredUsers {
    return _users.where((u) {
      if (_selectedFormFilter != 'All' && u.selectedForm != _selectedFormFilter) {
        return false;
      }
      if (_selectedTierFilter == 'Free' && u.isSubscriptionActive) {
        return false;
      }
      if (_selectedTierFilter == 'Paid' && !u.isSubscriptionActive) {
        return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final matchesName = u.displayName.toLowerCase().contains(q);
        final matchesEmail = u.email.toLowerCase().contains(q);
        if (!matchesName && !matchesEmail) return false;
      }
      return true;
    }).toList();
  }

  int get _totalSessionsAllUsers {
    int sum = 0;
    for (final count in _userSessionCounts.values) {
      sum += count;
    }
    return sum;
  }

  int get _totalPaidUsers {
    return _users.where((u) => u.isSubscriptionActive).length;
  }

  Future<void> _showAddUserDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String chosenForm = 'Form 1';

    final created = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              GoogleLogoWidget(size: 22),
              SizedBox(width: 10),
              Text('Ku dar Arday Cusub', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Geli macluumaadka akoonka Google ee ardayga si loogu daro nidaamka:',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Magaca Ardayga (Full Name)',
                    hintText: 'Tusaale: Xasan Cali',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Google Email (Gmail)',
                    hintText: 'arday@gmail.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Dooro Fasalka (Form):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: chosenForm,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: _availableForms
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setDlgState(() => chosenForm = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx, false),
              child: const Text('Jooji'),
            ),
            FilledButton(
              onPressed: () {
                final email = emailCtrl.text.trim();
                if (email.isNotEmpty && email.contains('@')) {
                  Navigator.pop(dlgCtx, true);
                }
              },
              child: const Text('Ku dar'),
            ),
          ],
        ),
      ),
    );

    if (created == true) {
      await _authService.registerOrSignInGoogle(
        email: emailCtrl.text.trim(),
        displayName: nameCtrl.text.trim().isEmpty ? 'Arday' : nameCtrl.text.trim(),
        form: chosenForm,
      );
      await _loadUsers();
    }
  }

  Future<void> _deleteUser(UserProfile user) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tirtir Ardaygan?'),
        content: Text(
          'Ma hubtaa inaad tirtirto ardayga "${user.displayName}" (${user.email})? Dhammaan duruusta iyo chat history-giisa waa la tirtirayaa.',
        ),
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
      await _historyStorage.clearAll(forUserId: user.id);
      await _authService.removeAccount(user.id);
      await _loadUsers();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Ardayga "${user.displayName}" waa la tirtiray.')),
        );
      }
    }
  }

  Future<void> _quickChangeForm(UserProfile user) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Beddel Fasalka: ${user.displayName}'),
        children: _availableForms.map((f) {
          final isSelected = user.selectedForm == f;
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, f),
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                  color: isSelected ? const Color(0xFF0022FF) : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  f,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (chosen != null && chosen != user.selectedForm) {
      final updated = user.copyWith(selectedForm: chosen);
      await _authService.updateUser(updated);
      await _loadUsers();
    }
  }

  Future<void> _quickToggleTier(UserProfile user) async {
    if (user.isSubscriptionActive) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('Ka qaad Paid VIP?'),
            ],
          ),
          content: Text(
            'Ma hubtaa inaad ardayga ${user.displayName} ka qaaddo Paid Tier VIP oo aad dib ugu celiso Free Tier?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Maya'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Haa, Ka qaad'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await _authService.cancelSubscription(user.id);
        await _loadUsers();
      }
    } else {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Fasax Paid Tier: ${user.displayName}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'monthly'),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.workspace_premium_rounded, color: Color(0xFFD97706)),
                    SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Fasax Bille VIP (30 Maalmood)', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Paid Tier - Gemini 2.5 Pro & GPT-4o', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'yearly'),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.stars_rounded, color: Color(0xFFD97706)),
                    SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Fasax Sannadle VIP (1 Sanno)', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Paid Tier - 365 Maalmood oo VIP ah', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

      if (choice != null) {
        await _authService.activateSubscription(
          userId: user.id,
          planName: choice,
          paymentMethod: 'Admin Override',
          paymentPhone: 'Admin Grant',
        );
        await _loadUsers();
      }
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filteredUsers;
    final activeUserId = _authService.currentUserId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ==================== 1. Metric Overview Cards ====================
        _buildMetricCardsRow(activeUserId),
        const SizedBox(height: 18),

        // ==================== 2. Search & Filter Bar ====================
        _buildSearchAndFilterBar(),
        const SizedBox(height: 16),

        // ==================== 3. Users List / Table ====================
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState()
              : _buildUsersList(filtered, activeUserId),
        ),
      ],
    );
  }

  Widget _buildMetricCardsRow(String? activeUserId) {
    final form1Count = _users.where((u) => u.selectedForm == 'Form 1').length;
    final form2Count = _users.where((u) => u.selectedForm == 'Form 2').length;
    final form3Count = _users.where((u) => u.selectedForm == 'Form 3').length;
    final form4Count = _users.where((u) => u.selectedForm == 'Form 4').length;

    return Row(
      children: [
        // Total Users Card
        Expanded(
          flex: 3,
          child: _buildMetricCard(
            title: 'Wadarta Ardayda',
            value: '${_users.length}',
            subtitle: 'Ardayda kukeedsan Local-ka',
            icon: Icons.people_alt_rounded,
            color: const Color(0xFF0022FF),
          ),
        ),
        const SizedBox(width: 12),

        // Paid Tier Subscribers Card
        Expanded(
          flex: 3,
          child: _buildMetricCard(
            title: 'Paid Tier (VIP)',
            value: '$_totalPaidUsers',
            subtitle: 'Xubnaha VIP ee furay Paid Models',
            icon: Icons.workspace_premium_rounded,
            color: const Color(0xFFD97706),
          ),
        ),
        const SizedBox(width: 12),

        // Total Study Sessions
        Expanded(
          flex: 3,
          child: _buildMetricCard(
            title: 'Wadarta Duruusta',
            value: '$_totalSessionsAllUsers',
            subtitle: 'Sheekooyinka & casharrada la bartay',
            icon: Icons.auto_stories_rounded,
            color: const Color(0xFF10B981),
          ),
        ),
        const SizedBox(width: 12),

        // Academic Distribution
        Expanded(
          flex: 4,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Row(
                  children: [
                    Icon(Icons.school_rounded, size: 16, color: Color(0xFF6366F1)),
                    SizedBox(width: 6),
                    Text(
                      'Kala-qeybsanaanta Fasallada (Forms)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildFormBadge('F1', form1Count),
                    _buildFormBadge('F2', form2Count),
                    _buildFormBadge('F3', form3Count),
                    _buildFormBadge('F4', form4Count),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormBadge(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF0022FF),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
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
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Search Input
          Expanded(
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Ka raadi ardayda magac ama email...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Form Filter Chips
          Wrap(
            spacing: 6,
            children: ['All', ..._availableForms].map((formName) {
              final isSelected = _selectedFormFilter == formName;
              final label = formName == 'All' ? 'Fasallada' : formName;
              return ChoiceChip(
                label: Text(label),
                selected: isSelected,
                selectedColor: const Color(0xFF0022FF),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedFormFilter = formName);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(width: 10),

          // Tier Filter Chips (All, Free, Paid)
          Wrap(
            spacing: 6,
            children: [
              {'id': 'All', 'label': 'All Tier'},
              {'id': 'Free', 'label': 'Free'},
              {'id': 'Paid', 'label': 'Paid VIP'},
            ].map((tier) {
              final isSelected = _selectedTierFilter == tier['id'];
              final isPaid = tier['id'] == 'Paid';
              return ChoiceChip(
                avatar: isPaid
                    ? Icon(
                        Icons.workspace_premium_rounded,
                        size: 14,
                        color: isSelected ? Colors.white : const Color(0xFFD97706),
                      )
                    : null,
                label: Text(tier['label']!),
                selected: isSelected,
                selectedColor: isPaid ? const Color(0xFFD97706) : const Color(0xFF0F172A),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedTierFilter = tier['id']!);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(width: 14),

          // Add User Button
          FilledButton.icon(
            onPressed: _showAddUserDialog,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0022FF),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
            label: const Text(
              'Ku dar Arday',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),

          IconButton(
            tooltip: 'Dib u cusbooneysii',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadUsers,
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList(List<UserProfile> users, String? activeUserId) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: users.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (ctx, index) {
          final user = users[index];
          final isActive = user.id == activeUserId;
          final sessionsCount = _userSessionCounts[user.id] ?? 0;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Row(
              children: [
                // Student Avatar with Google badge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Color(user.avatarColorValue),
                      child: Text(
                        user.initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Positioned(
                      bottom: -2,
                      right: -2,
                      child: CircleAvatar(
                        radius: 8,
                        backgroundColor: Colors.white,
                        child: GoogleLogoWidget(size: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),

                // Name & Email
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text(
                                'Active Hadda',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),

                // Academic Form Badge
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: () => _quickChangeForm(user),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0022FF).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              user.selectedForm,
                              style: const TextStyle(
                                color: Color(0xFF0022FF),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down_rounded, size: 18, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ),

                // Tier Badge (Free vs Paid VIP) with Quick Click Action
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: () => _quickToggleTier(user),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: user.isSubscriptionActive
                                  ? const Color(0xFFFEF3C7)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: user.isSubscriptionActive
                                    ? const Color(0xFFFDE68A)
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  user.isSubscriptionActive
                                      ? Icons.workspace_premium_rounded
                                      : Icons.bolt_rounded,
                                  size: 13,
                                  color: user.isSubscriptionActive
                                      ? const Color(0xFFD97706)
                                      : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  user.isSubscriptionActive ? 'Paid VIP' : 'Free Tier',
                                  style: TextStyle(
                                    color: user.isSubscriptionActive
                                        ? const Color(0xFFB45309)
                                        : Colors.grey.shade800,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(Icons.swap_vert_rounded, size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ),

                // Total History Sessions Badge
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Colors.black54),
                          const SizedBox(width: 5),
                          Text(
                            '$sessionsCount Sheeko',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Dhowaan: ${_formatDate(user.lastLoginAt)}',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),

                // Actions: Inspect History (Primary), Delete
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0022FF),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        UserDetailHistoryDialog.show(
                          context,
                          user: user,
                          onUserUpdated: _loadUsers,
                        );
                      },
                      icon: const Icon(Icons.history_edu_rounded, size: 16),
                      label: const Text(
                        'Kormeero History-ga',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      tooltip: 'Tirtir Ardayga',
                      color: Colors.red.shade400,
                      onPressed: () => _deleteUser(user),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_search_rounded, size: 42, color: Colors.grey),
          ),
          const SizedBox(height: 14),
          const Text(
            'Lama helin wax arday ah',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 6),
          Text(
            _searchQuery.isNotEmpty
                ? 'Wax arday ah kuma habboona raadinta "$_searchQuery".'
                : 'Weli ma jiraan arday iska diiwaangelisay app-ka.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _showAddUserDialog,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
            label: const Text('Ku dar Ardaygii Koowaad'),
          ),
        ],
      ),
    );
  }
}
