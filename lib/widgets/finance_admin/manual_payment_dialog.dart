import 'package:flutter/material.dart';
import '../../models/user_profile.dart';
import '../../services/finance_storage.dart';

/// Modal dialog for Admin to record a manual/cash/merchant payment for any student
class ManualPaymentDialog extends StatefulWidget {
  const ManualPaymentDialog({
    super.key,
    required this.students,
    this.initialStudent,
    this.onPaymentRecorded,
  });

  final List<UserProfile> students;
  final UserProfile? initialStudent;
  final VoidCallback? onPaymentRecorded;

  static Future<void> show(
    BuildContext context, {
    required List<UserProfile> students,
    UserProfile? initialStudent,
    VoidCallback? onPaymentRecorded,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ManualPaymentDialog(
        students: students,
        initialStudent: initialStudent,
        onPaymentRecorded: onPaymentRecorded,
      ),
    );
  }

  @override
  State<ManualPaymentDialog> createState() => _ManualPaymentDialogState();
}

class _ManualPaymentDialogState extends State<ManualPaymentDialog> {
  final _financeStorage = const FinanceStorage();
  UserProfile? _selectedStudent;

  String _planName = 'monthly';
  String _paymentMethod = 'EVC Plus';
  final _amountController = TextEditingController(text: '5.00');
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  bool _isSaving = false;

  static const _paymentMethods = [
    'EVC Plus',
    'Zaad Service',
    'Sahal',
    'Waafi',
    'Lacag Caddaan ah (Cash)',
    'Xawilaad / Bank',
    'Admin Grant',
  ];

  @override
  void initState() {
    super.initState();
    _selectedStudent = widget.initialStudent ?? (widget.students.isNotEmpty ? widget.students.first : null);
  }

  void _onPlanChanged(String plan) {
    setState(() {
      _planName = plan;
      if (plan == 'monthly') {
        _amountController.text = '5.00';
      } else if (plan == 'yearly') {
        _amountController.text = '40.00';
      }
    });
  }

  Future<void> _submitPayment() async {
    if (_selectedStudent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fadlan dooro ardayga')),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.trim()) ?? 5.0;

    setState(() => _isSaving = true);
    final nav = Navigator.of(context);

    try {
      await _financeStorage.recordTransaction(
        userId: _selectedStudent!.id,
        studentName: _selectedStudent!.displayName,
        studentEmail: _selectedStudent!.email,
        amount: amount,
        planName: _planName,
        paymentMethod: _paymentMethod,
        paymentPhone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : 'Manual payment recorded by Admin',
        activateStudent: true,
      );

      widget.onPaymentRecorded?.call();
      if (mounted) {
        nav.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lacag-bixinta ardayga ${_selectedStudent!.displayName} si guul leh ayaa loo diiwaangeliyay, VIP-diina waa la furay!'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Khalad: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.add_card_rounded, color: Color(0xFF0022FF), size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Diiwaangeli Lacag-bixin Cusub',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
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

              // Student Selector
              const Text(
                'Ardayga Lacagta Bixiyay:',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<UserProfile>(
                initialValue: _selectedStudent,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                ),
                items: widget.students.map((u) {
                  return DropdownMenuItem(
                    value: u,
                    child: Text(
                      '${u.displayName} (${u.selectedForm} • ${u.email})',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedStudent = val),
              ),
              const SizedBox(height: 14),

              // Plan Selection
              const Text(
                'Qorshaha VIP (Plan):',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Bille (\$5 / mo)')),
                      selected: _planName == 'monthly',
                      selectedColor: const Color(0xFF0022FF),
                      labelStyle: TextStyle(
                        color: _planName == 'monthly' ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) => _onPlanChanged('monthly'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Sannadle (\$40 / yr)')),
                      selected: _planName == 'yearly',
                      selectedColor: const Color(0xFF0022FF),
                      labelStyle: TextStyle(
                        color: _planName == 'yearly' ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) => _onPlanChanged('yearly'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Amount & Payment Method Row
              Row(
                children: [
                  // Amount
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Qiimaha (\$ USD):',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixText: '\$ ',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Gateway / Method
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Habka Bixinta:',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _paymentMethod,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: _paymentMethods.map((m) {
                            return DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12.5)));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _paymentMethod = val);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Mobile Phone / Transaction Reference
              const Text(
                'Nambarka Telefoonka ama Tixraaca (Reference):',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _phoneController,
                decoration: InputDecoration(
                  hintText: 'Tusaale: 061XXXXXXX ama Bank Ref No.',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.phone_android_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 14),

              // Admin Notes
              const Text(
                'Faahfaahin Dheeraad ah (Notes):',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Tusaale: Waxaa lagu bixiyay xafiiska xarunta dhexe...',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),

              // Submit Button
              FilledButton.icon(
                onPressed: _isSaving ? null : _submitPayment,
                icon: _isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_rounded, size: 18),
                label: Text(
                  _isSaving ? 'Waa la keydinayaa...' : 'Diiwaangeli & Fasax Paid Tier VIP',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0022FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
