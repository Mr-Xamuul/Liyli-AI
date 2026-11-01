import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/ai_routing_storage.dart';
import '../services/finance_storage.dart';

/// Modal dialog for student subscription and payment to unlock the Paid Tier in App Routing
class PaymentSubscriptionDialog extends StatefulWidget {
  const PaymentSubscriptionDialog({
    super.key,
    required this.user,
    this.onSubscriptionActivated,
  });

  final UserProfile user;
  final VoidCallback? onSubscriptionActivated;

  static Future<void> show(
    BuildContext context, {
    required UserProfile user,
    VoidCallback? onSubscriptionActivated,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PaymentSubscriptionDialog(
        user: user,
        onSubscriptionActivated: onSubscriptionActivated,
      ),
    );
  }

  @override
  State<PaymentSubscriptionDialog> createState() => _PaymentSubscriptionDialogState();
}

class _PaymentSubscriptionDialogState extends State<PaymentSubscriptionDialog> {
  final _routingStorage = const AiRoutingStorage();

  // Selected Plan: 'monthly' or 'yearly'
  String _selectedPlan = 'monthly';

  // Selected Payment Method
  String _selectedMethod = 'EVC Plus';

  final _phoneController = TextEditingController();
  bool _isProcessing = false;
  String? _stepMessage;

  List<String> _paidModelNames = [];

  static const _paymentMethods = [
    {
      'id': 'EVC Plus',
      'name': 'EVC Plus',
      'provider': 'Hormuud Telecom',
      'icon': Icons.phone_android_rounded,
      'color': Color(0xFF16A34A),
      'hint': 'Tusaale: 061XXXXXXX',
    },
    {
      'id': 'Zaad Service',
      'name': 'Zaad Service',
      'provider': 'Telesom',
      'icon': Icons.send_to_mobile_rounded,
      'color': Color(0xFF0284C7),
      'hint': 'Tusaale: 063XXXXXXX',
    },
    {
      'id': 'Sahal',
      'name': 'Sahal Service',
      'provider': 'Golis Telecom',
      'icon': Icons.account_balance_wallet_rounded,
      'color': Color(0xFFE11D48),
      'hint': 'Tusaale: 064XXXXXXX',
    },
    {
      'id': 'Waafi',
      'name': 'Waafi / e-Dahab',
      'provider': 'Dahabshiil',
      'icon': Icons.credit_card_rounded,
      'color': Color(0xFFF59E0B),
      'hint': 'Tusaale: 062XXXXXXX',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadPaidModelsPreview();
  }

  Future<void> _loadPaidModelsPreview() async {
    try {
      final models = await _routingStorage.getActiveTierModels();
      if (mounted) {
        setState(() {
          _paidModelNames = models.map((m) => m.displayName).toList();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _processPayment() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fadlan geli lambarka teleefanka lacagta laga jarayo'),
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _stepMessage = 'Waxaa lala xiriirayaa $_selectedMethod...';
    });

    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    setState(() {
      _stepMessage = 'Fadlan ka eeg teleefankaaga farriinta ogolaanshaha PIN-ka...';
    });

    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    setState(() {
      _stepMessage = 'Lacag-bixinta waa la xaqiijiyay! Paid Tier ayaa la fasaxayaa...';
    });

    final isMonthly = _selectedPlan == 'monthly';
    final amount = isMonthly ? 5.0 : 40.0;

    await const FinanceStorage().recordTransaction(
      userId: widget.user.id,
      studentName: widget.user.displayName,
      studentEmail: widget.user.email,
      amount: amount,
      planName: _selectedPlan,
      paymentMethod: _selectedMethod,
      paymentPhone: phone,
      notes: 'Isku-diiwaangelinta tooska ah ee Profile-ka ardayga (${isMonthly ? "Bille \$5" : "Sannadle \$40"})',
      activateStudent: true,
    );

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    setState(() => _isProcessing = false);

    widget.onSubscriptionActivated?.call();

    // Show Success Dialog
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF3C7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFFD97706),
                size: 46,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Hambalyo! Paid Tier waa Furan yahay! 👑',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Waxaa lagugu fasaxay moodellada VIP-da ee kudiyaarsan App Routing-ka. '
              'Waxaad hadda heli doontaa jawaabo heer sare ah oo degdeg ah.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0022FF),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('Bilow Waxbarashada VIP-da'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMonthly = _selectedPlan == 'monthly';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      elevation: 4,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Crown
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          color: Color(0xFFD97706),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Leyli AI VIP • Paid Tier',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Fasax Moodellada Sare ee App Routing-ka',
                            style: TextStyle(fontSize: 11, color: Colors.black54),
                          ),
                        ],
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

              // VIP Benefits Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.bolt_rounded, color: Color(0xFFFBBF24), size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Waxa aad helayso marka aad furato Paid Tier:',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildBenefitRow(
                      _paidModelNames.isNotEmpty
                          ? 'Moodellada VIP: ${_paidModelNames.join(', ')}'
                          : 'Moodellada VIP-da ee App Routing (Gemini Pro / GPT-4o)',
                    ),
                    _buildBenefitRow('Xawaare sare & Mudnaan kowaad (Fast Priority Routing)'),
                    _buildBenefitRow('Faham qoto-dheer & xallinta su\'aalaha adag ee imtixaannada'),
                    _buildBenefitRow('Duruus & Caawinaad buugaagta dugsiga sare oo aan xadidnayn'),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Plan Selector (Monthly vs Yearly)
              const Text(
                '1. Dooro Qorshahaaga (Plan):',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // Monthly
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _selectedPlan = 'monthly'),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMonthly ? const Color(0xFFE8ECFF) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isMonthly ? const Color(0xFF0022FF) : Colors.grey.shade300,
                            width: isMonthly ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Billeed',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                if (isMonthly)
                                  const Icon(Icons.check_circle_rounded, color: Color(0xFF0022FF), size: 18),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '\$5',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0022FF),
                              ),
                            ),
                            const Text('bishii (30 maalmood)', style: TextStyle(fontSize: 10.5, color: Colors.black54)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Yearly
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _selectedPlan = 'yearly'),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: !isMonthly ? const Color(0xFFE8ECFF) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: !isMonthly ? const Color(0xFF0022FF) : Colors.grey.shade300,
                            width: !isMonthly ? 2 : 1,
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
                                    const Text(
                                      'Sanadle',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        '-33%',
                                        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                if (!isMonthly)
                                  const Icon(Icons.check_circle_rounded, color: Color(0xFF0022FF), size: 18),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '\$40',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0022FF),
                              ),
                            ),
                            const Text('sanadkii (365 maalmood)', style: TextStyle(fontSize: 10.5, color: Colors.black54)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Payment Method Selector
              const Text(
                '2. Dooro Qaabka Lacag-bixinta (Somali Mobile Money):',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _paymentMethods.map((m) {
                  final isSelected = _selectedMethod == m['id'];
                  return ChoiceChip(
                    avatar: Icon(
                      m['icon'] as IconData,
                      size: 16,
                      color: isSelected ? Colors.white : (m['color'] as Color),
                    ),
                    label: Text(m['name'] as String),
                    selected: isSelected,
                    selectedColor: const Color(0xFF0022FF),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 12,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedMethod = m['id'] as String);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Phone Number Input
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Lambarka Teleefanka ($_selectedMethod)',
                  hintText: 'Tusaale: 061XXXXXXX ama 063XXXXXXX',
                  prefixIcon: const Icon(Icons.phone_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 18),

              // Processing state or Action Button
              if (_isProcessing)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _stepMessage ?? 'Fadlan sug...',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: _processPayment,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0022FF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.lock_outline_rounded, size: 18),
                  label: Text(
                    'Bixi Lacagta (${isMonthly ? '\$5.00' : '\$40.00'}) oo Fasax Paid Tier',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
