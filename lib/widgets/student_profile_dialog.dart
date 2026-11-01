import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/user_auth_service.dart';
import 'google_logo_widget.dart';
import 'payment_subscription_dialog.dart';

/// Modal dialog or bottom sheet for viewing and editing student profile,
/// changing academic form, and switching local Google accounts.
class StudentProfileDialog extends StatefulWidget {
  const StudentProfileDialog({super.key, this.onAccountChanged});

  final VoidCallback? onAccountChanged;

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onAccountChanged,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) =>
          StudentProfileDialog(onAccountChanged: onAccountChanged),
    );
  }

  @override
  State<StudentProfileDialog> createState() => _StudentProfileDialogState();
}

class _StudentProfileDialogState extends State<StudentProfileDialog> {
  final _authService = UserAuthService.instance;
  static const _availableForms = ['Form 1', 'Form 2', 'Form 3', 'Form 4'];

  @override
  void initState() {
    super.initState();
  }

  Future<void> _editName(UserProfile user) async {
    final controller = TextEditingController(text: user.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Beddel Magaca'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Magaca Buuxa',
            hintText: 'Tusaale: Axmed Cali',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Jooji'),
          ),
          FilledButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) {
                Navigator.pop(ctx, val);
              }
            },
            child: const Text('Keydi'),
          ),
        ],
      ),
    );

    if (newName != null && newName != user.displayName) {
      await _authService.updateCurrentProfile(displayName: newName);
      setState(() {});
      widget.onAccountChanged?.call();
    }
  }

  Future<void> _changeForm(String newForm) async {
    await _authService.updateCurrentProfile(selectedForm: newForm);
    setState(() {});
    widget.onAccountChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fasalka waxaa loo beddelay $newForm'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _showAddOrSwitchAccountSheet() async {
    final accounts = _authService.savedAccounts;
    final current = _authService.currentUser;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    GoogleLogoWidget(size: 20),
                    SizedBox(width: 10),
                    Text(
                      'Dooro Akoonka Google',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: accounts.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (ctx, index) {
                      final acc = accounts[index];
                      final isCurrent = acc.id == current?.id;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Color(acc.avatarColorValue),
                          child: Text(
                            acc.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          acc.displayName,
                          style: TextStyle(
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          '${acc.email} • ${acc.selectedForm}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: isCurrent
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF0022FF),
                              )
                            : null,
                        onTap: () async {
                          Navigator.pop(sheetCtx);
                          if (!isCurrent) {
                            await _authService.switchAccount(acc.id);
                            widget.onAccountChanged?.call();
                            if (mounted) {
                              Navigator.pop(context);
                            }
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetCtx);
                    await _showAddNewGoogleAccountDialog();
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Ku gal akoon kale oo Google'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAddNewGoogleAccountDialog() async {
    final nav = Navigator.of(context);
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String chosenForm = 'Form 1';

    final created = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              GoogleLogoWidget(size: 22),
              SizedBox(width: 10),
              Text('Akoon Google Cusub', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Geli macluumaadka akoonkaaga Google si aad wax ugu barato:',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Magacaaga',
                    hintText: 'Tusaale: Faadumo Maxamed',
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
                  'Dooro Fasalkaaga:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: chosenForm,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: _availableForms
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDlgState(() => chosenForm = val);
                    }
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
              child: const Text('Ku gal'),
            ),
          ],
        ),
      ),
    );

    if (created == true) {
      await _authService.registerOrSignInGoogle(
        email: emailCtrl.text.trim(),
        displayName: nameCtrl.text.trim().isEmpty
            ? 'Arday'
            : nameCtrl.text.trim(),
        form: chosenForm,
      );
      widget.onAccountChanged?.call();
      if (mounted) {
        nav.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    if (user == null) {
      return AlertDialog(
        title: const Text('Ma jiro Akoon galay'),
        content: const Text(
          'Fadlan ku gal Google si aad u aragto Profile-kaaga.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      elevation: 3,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Title & Close
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.badge_rounded,
                        color: Color(0xFF0022FF),
                        size: 22,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Profile-ka Ardayga',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Avatar & Name Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: Color(user.avatarColorValue),
                          foregroundImage:
                              user.photoUrl != null && user.photoUrl!.isNotEmpty
                              ? NetworkImage(user.photoUrl!)
                              : null,
                          child: user.photoUrl == null || user.photoUrl!.isEmpty
                              ? Text(
                                  user.initials,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        const Positioned(
                          bottom: -2,
                          right: -2,
                          child: CircleAvatar(
                            radius: 11,
                            backgroundColor: Colors.white,
                            child: GoogleLogoWidget(size: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  user.displayName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                tooltip: 'Beddel Magaca',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _editName(user),
                              ),
                            ],
                          ),
                          Text(
                            user.email,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8ECFF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.school_rounded,
                                      size: 14,
                                      color: Color(0xFF0022FF),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      user.selectedForm,
                                      style: const TextStyle(
                                        color: Color(0xFF0022FF),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: user.isSubscriptionActive
                                      ? const Color(0xFFFEF3C7)
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      user.isSubscriptionActive
                                          ? Icons.workspace_premium_rounded
                                          : Icons.bolt_rounded,
                                      size: 14,
                                      color: user.isSubscriptionActive
                                          ? const Color(0xFFD97706)
                                          : Colors.grey.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      user.tierLabel,
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
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Account information
              const Text(
                'Macluumaadka Akoonka',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildProfileInfoRow(
                icon: Icons.verified_user_rounded,
                label: 'Xaaladda akoonka',
                value: user.isSubscriptionActive
                    ? 'Firfircoon · ${user.tierLabel}'
                    : 'Firfircoon · Free Tier',
                color: const Color(0xFF16A34A),
              ),
              const SizedBox(height: 8),
              _buildProfileInfoRow(
                icon: Icons.school_rounded,
                label: 'Fasalka',
                value: user.selectedForm,
                color: const Color(0xFF0022FF),
              ),
              const SizedBox(height: 14),
              const Text(
                'Fasalkaaga',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: _availableForms.map((f) {
                  final isSelected = user.selectedForm == f;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: InkWell(
                        onTap: () => _changeForm(f),
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF0022FF)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF0022FF)
                                  : Colors.grey.shade300,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            f,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isSelected ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),

              // Subscription & Paid Tier Card
              _buildSubscriptionTierCard(user),
              const SizedBox(height: 18),

              // Switch Account Button
              OutlinedButton.icon(
                onPressed: _showAddOrSwitchAccountSheet,
                icon: const Icon(Icons.switch_account_rounded, size: 18),
                label: const Text('Beddel Akoonka Google (Switch)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Logout Button
              TextButton.icon(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Ma hubtaa inaad ka baxdo?'),
                      content: const Text(
                        'Waxaad ka baxaysaa akoonkaaga Google ee hadda.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Maya'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('Ka bax'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await _authService.signOut();
                    widget.onAccountChanged?.call();
                    if (mounted) {
                      nav.pop();
                    }
                  }
                },
                icon: const Icon(
                  Icons.logout_rounded,
                  size: 18,
                  color: Colors.red,
                ),
                label: const Text(
                  'Ka bax Akoonka',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionTierCard(UserProfile user) {
    final isPaid = user.isSubscriptionActive;

    if (isPaid) {
      final expiry = user.subscriptionExpiresAt;
      final expiryStr = expiry != null
          ? '${expiry.day}/${expiry.month}/${expiry.year}'
          : 'Aan dhicin';

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD97706).withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Paid Tier (VIP)',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF92400E),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16A34A),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'FURAN',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Routing: Moodallada sare ee VIP ayaa kuu shaqeynaya',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.brown.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Qorshahaaga:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        user.planName == 'yearly'
                            ? 'Sannadle (\$40/yr)'
                            : 'Bille (\$5/mo)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Habka Lacag-bixinta:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        '${user.paymentMethod ?? 'EVC Plus'} ${user.paymentPhone != null ? '(${user.paymentPhone})' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Wuxuu dhacayaa:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        expiryStr,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      PaymentSubscriptionDialog.show(
                        context,
                        user: user,
                        onSubscriptionActivated: () {
                          widget.onAccountChanged?.call();
                          setState(() {});
                        },
                      );
                    },
                    icon: const Icon(Icons.autorenew_rounded, size: 16),
                    label: const Text('Cusbooneysii'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF92400E),
                      side: const BorderSide(color: Color(0xFFD97706)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Jooji Subscription-ka?'),
                        content: const Text(
                          'Haddii aad joojiso waxaad dib ugu laaban doontaa Free Tier, moodallada VIP-dana way xirmi doonaan.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Maya'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text('Haa, Jooji'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      await _authService.cancelSubscription(user.id);
                      widget.onAccountChanged?.call();
                      setState(() {});
                    }
                  },
                  child: const Text(
                    'Jooji VIP',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Free Tier View
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0022FF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.lock_open_rounded,
                  color: Color(0xFF0022FF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paid Tier (Qorshaha VIP)',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Fur moodallada ugu awoodda badan ee AI Routing',
                      style: TextStyle(fontSize: 11.5, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBenefitItem(
                  Icons.auto_awesome_rounded,
                  'Gemini 2.5 Pro & GPT-4o Models',
                ),
                const SizedBox(height: 5),
                _buildBenefitItem(
                  Icons.bolt_rounded,
                  'Xawaare sare oo aan xad lahayn',
                ),
                const SizedBox(height: 5),
                _buildBenefitItem(
                  Icons.menu_book_rounded,
                  'Sharaxaad qoto dheer oo su\'aalaha casharada',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              PaymentSubscriptionDialog.show(
                context,
                user: user,
                onSubscriptionActivated: () {
                  widget.onAccountChanged?.call();
                  setState(() {});
                },
              );
            },
            icon: const Icon(
              Icons.workspace_premium_rounded,
              size: 18,
              color: Colors.white,
            ),
            label: const Text(
              'Ku biir Paid Tier (\$5 / Bishiiba)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0022FF),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF0022FF)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
