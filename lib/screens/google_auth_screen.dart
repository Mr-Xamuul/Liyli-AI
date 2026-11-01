import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/user_auth_service.dart';
import '../widgets/google_logo_widget.dart';

/// Google Registration and Authentication Screen
/// Exclusive Google Sign-In with mandatory Form/Grade selection and local multi-account profile creation.
class GoogleAuthScreen extends StatefulWidget {
  const GoogleAuthScreen({super.key, required this.onAuthenticated});

  final VoidCallback onAuthenticated;

  @override
  State<GoogleAuthScreen> createState() => _GoogleAuthScreenState();
}

class _GoogleAuthScreenState extends State<GoogleAuthScreen> {
  final _authService = UserAuthService.instance;

  // Step 0: Google Sign-in / Account Chooser
  // Step 1: Academic Form Selection (Form 1 - Form 4)
  int _step = 0;

  String _email = '';
  String _displayName = '';
  String _selectedForm = 'Form 1';
  bool _isSigningIn = false;

  final _formOptions = const [
    {
      'form': 'Form 1',
      'label': 'Fasalka 1-aad',
      'desc': 'Bilaabidda Dugsiga Sare & Aasaaska Culuumta',
      'icon': Icons.menu_book_rounded,
    },
    {
      'form': 'Form 2',
      'label': 'Fasalka 2-aad',
      'desc': 'Fasalka Labaad ee Dugsiga Sare',
      'icon': Icons.auto_stories_rounded,
    },
    {
      'form': 'Form 3',
      'label': 'Fasalka 3-aad',
      'desc': 'Xoojinta & Fahamka Qoto-dheer ee Casharrada',
      'icon': Icons.psychology_rounded,
    },
    {
      'form': 'Form 4',
      'label': 'Fasalka 4-aad',
      'desc': 'Imtixaanka Shahaadiga & Qalinjebinta Dugsiga Sare',
      'icon': Icons.military_tech_rounded,
    },
  ];

  Future<void> _handleGoogleButtonTapped() async {
    if (_authService.usesSupabase) {
      if (_isSigningIn) return;
      setState(() => _isSigningIn = true);
      try {
        final launched = await _authService.signInWithGoogle();
        if (!launched && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Google sign-in lama bilaabi karin.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Google sign-in wuu fashilmay: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isSigningIn = false);
      }
      return;
    }
    final accounts = _authService.savedAccounts;
    if (accounts.isNotEmpty) {
      _showGoogleAccountChooserModal(accounts);
    } else {
      _showGooglePromptSheet();
    }
  }

  void _showGoogleAccountChooserModal(List<UserProfile> accounts) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
                    width: 38,
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
                    GoogleLogoWidget(size: 22),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dooro akoon Google',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'si aad ugu sii socoto Leyli AI',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
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
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
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
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${acc.email} • ${acc.selectedForm}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        onTap: () async {
                          Navigator.pop(sheetCtx);
                          await _authService.switchAccount(acc.id);
                          widget.onAuthenticated();
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    _showGooglePromptSheet();
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Isticmaal akoon kale oo Google ah'),
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

  void _showGooglePromptSheet() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  GoogleLogoWidget(size: 24),
                  SizedBox(width: 12),
                  Text(
                    _authService.usesSupabase
                        ? 'Ku gal email-kaaga'
                        : 'Ku gal Akoonkaaga Google',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _authService.usesSupabase
                    ? 'Geli email-kaaga iyo magacaaga. Waxaan kuu soo diraynaa link ammaan ah oo aad ku xaqiijiso akoonkaaga.'
                    : 'Geli email-kaaga Google iyo magacaaga si aad ugu diiwaangashato app-ka.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Magaca Ardayga (Full Name)',
                  hintText: 'Tusaale: Axmed Cabdi',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: _authService.usesSupabase
                      ? 'Email-kaaga'
                      : 'Google Email (Gmail)',
                  hintText: 'arday@gmail.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () async {
                  final email = emailCtrl.text.trim();
                  final name = nameCtrl.text.trim();
                  if (email.isEmpty || !email.contains('@')) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Fadlan geli email sax ah (tusaale: arday@gmail.com)',
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(sheetCtx);
                  setState(() {
                    _email = email;
                    _displayName = name.isEmpty ? 'Arday' : name;
                    _step = 1; // Move to Grade Selection Step
                  });
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0022FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _authService.usesSupabase
                      ? 'Ii soo dir link-ga xaqiijinta'
                      : 'Sii soco (Next)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _completeRegistration() async {
    setState(() => _isSigningIn = true);
    try {
      await _authService.registerOrSignInGoogle(
        email: _email,
        displayName: _displayName,
        form: _selectedForm,
      );
      if (mounted) {
        widget.onAuthenticated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Cillad ayaa dhacday: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _step == 0
                  ? _buildGoogleSignInView(theme)
                  : _buildGradeSelectionView(theme),
            ),
          ),
        ),
      ),
    );
  }

  /// Step 0: Google Sign In Landing
  Widget _buildGoogleSignInView(ThemeData theme) {
    final savedAccounts = _authService.savedAccounts;

    return SingleChildScrollView(
      key: const ValueKey('step_google_sign_in'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo & Branding
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE8ECFF),
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                'assets/icon-Leyli AI.png',
                height: 72,
                width: 72,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              'Leyli AI',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Macallinkaaga Gaarka ah ee Dugsiga Sare',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 36),

          // Google Card Box
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade300, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.login_rounded,
                      color: Color(0xFF0022FF),
                      size: 22,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Diiwaangelin & Soo Galid',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _authService.usesSupabase
                      ? 'Ku soo gal akoonkaaga Google si aad u hesho buugaagta iyo chat history-gaaga.'
                      : 'Si aad u hesho buugaagtaada, su\'aalahaaga iyo chat history-gaaga, fadlan ku soo gal akoonkaaga Google.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                // Authentic Google Sign-In Button
                InkWell(
                  onTap: _isSigningIn ? null : _handleGoogleButtonTapped,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF747775),
                        width: 1.1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isSigningIn)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          const GoogleLogoWidget(size: 22),
                        const SizedBox(width: 12),
                        Text(
                          'Ku gal Google (Sign in with Google)',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F1F1F),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Quick selector for existing local accounts
                if (savedAccounts.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'Ama akoomada hore',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...savedAccounts.take(2).map((acc) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 0,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: Color(acc.avatarColorValue),
                          child: Text(
                            acc.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          acc.displayName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          '${acc.email} • ${acc.selectedForm}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                        ),
                        onTap: () async {
                          await _authService.switchAccount(acc.id);
                          widget.onAuthenticated();
                        },
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 15,
                color: Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                'Xogtaada waxay ku kaydsan tahay akoonkaaga local-ka',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Step 1: Mandatory Academic Grade Selection
  Widget _buildGradeSelectionView(ThemeData theme) {
    return SingleChildScrollView(
      key: const ValueKey('step_grade_selection'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _step = 0),
              ),
              const SizedBox(width: 4),
              const Text(
                'Tallaabada 2 / 2',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Dooro Fasalkaaga 🎓',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ku soo dhawoow $_displayName! Dooro fasalka aad hadda dhigato si buugaagta iyo AI-ga loogu habeeyo duruustaada.',
            style: TextStyle(
              fontSize: 13.5,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // Form Options Cards
          ...List.generate(_formOptions.length, (idx) {
            final item = _formOptions[idx];
            final formName = item['form'] as String;
            final isSelected = _selectedForm == formName;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () => setState(() => _selectedForm = formName),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFE8ECFF) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF0022FF)
                          : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF0022FF)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          item['icon'] as IconData,
                          color: isSelected ? Colors.white : Colors.black87,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  item['label'] as String,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? const Color(0xFF0022FF)
                                        : Colors.black,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(
                                            0xFF0022FF,
                                          ).withValues(alpha: 0.15)
                                        : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    formName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? const Color(0xFF0022FF)
                                          : Colors.black54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item['desc'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_off_rounded,
                        color: isSelected
                            ? const Color(0xFF0022FF)
                            : Colors.grey.shade400,
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 20),

          // Complete Button
          FilledButton(
            onPressed: _isSigningIn ? null : _completeRegistration,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0022FF),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isSigningIn
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Dhammee oo Bilow Waxbarashada',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
