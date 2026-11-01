import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/finance_models.dart';

/// Modal dialog displaying a world-class official payment receipt / invoice
class TransactionReceiptDialog extends StatelessWidget {
  const TransactionReceiptDialog({
    super.key,
    required this.transaction,
    this.onRefundRequested,
  });

  final PaymentTransaction transaction;
  final VoidCallback? onRefundRequested;

  static Future<void> show(
    BuildContext context, {
    required PaymentTransaction transaction,
    VoidCallback? onRefundRequested,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => TransactionReceiptDialog(
        transaction: transaction,
        onRefundRequested: onRefundRequested,
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} • ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isRefunded = transaction.isRefunded;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Bar & Close
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                          Icons.receipt_long_rounded,
                          color: Color(0xFF0022FF),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rasiidka Lacag-bixinta',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Official Digital Invoice • Leyli AI',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
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
              const SizedBox(height: 18),

              // Receipt Ticket Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isRefunded
                            ? Colors.red.shade50
                            : const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isRefunded ? Colors.red.shade200 : const Color(0xFF10B981),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isRefunded
                                ? Icons.replay_circle_filled_rounded
                                : Icons.check_circle_rounded,
                            size: 14,
                            color: isRefunded ? Colors.red : const Color(0xFF059669),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isRefunded ? 'LACAGTA WAA LA CELIYAY (REFUNDED)' : 'LACAGTA WAA LA BIXIYAY (COMPLETED)',
                            style: TextStyle(
                              color: isRefunded ? Colors.red.shade700 : const Color(0xFF059669),
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Amount
                    Text(
                      '\$${transaction.amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: isRefunded ? Colors.grey.shade600 : const Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      '(${transaction.planLabel})',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0022FF),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 14),

                    // Key Details
                    _buildReceiptRow('Transaction ID', transaction.id, canCopy: true, context: context),
                    _buildReceiptRow('Receipt No.', transaction.receiptNumber ?? 'N/A'),
                    _buildReceiptRow('Ardayga', transaction.studentName),
                    _buildReceiptRow('Email', transaction.studentEmail),
                    _buildReceiptRow('Habka Bixinta', transaction.paymentMethod),
                    if (transaction.paymentPhone != null && transaction.paymentPhone!.isNotEmpty)
                      _buildReceiptRow('Nambarka / Card', transaction.paymentPhone!),
                    if (transaction.couponCode != null && transaction.couponCode!.isNotEmpty)
                      _buildReceiptRow('Coupon Code', '${transaction.couponCode} (-\$${transaction.discountAmount.toStringAsFixed(2)})'),
                    _buildReceiptRow('Taariikhda', _formatDate(transaction.createdAt)),
                    if (transaction.notes != null && transaction.notes!.isNotEmpty)
                      _buildReceiptRow('Faallo', transaction.notes!),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text: 'Leyli AI Receipt: ${transaction.receiptNumber}\nTxn: ${transaction.id}\nStudent: ${transaction.studentName}\nAmount: \$${transaction.amount}\nMethod: ${transaction.paymentMethod}\nDate: ${_formatDate(transaction.createdAt)}',
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Rasiidka waxaa lagu koobiyeeyay clipboard-ka!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Koobiyeyso'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  if (!isRefunded && onRefundRequested != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onRefundRequested,
                        icon: const Icon(Icons.replay_rounded, size: 16),
                        label: const Text('Celi Lacagta'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool canCopy = false, BuildContext? context}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                if (canCopy && context != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$value waa la koobiyeeyay')),
                      );
                    },
                    child: const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF0022FF)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
