import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/finance_models.dart';
import 'user_auth_service.dart';

/// Storage and business service for Financial Management, Transactions Ledger,
/// and Pricing/Gateway Configurations.
class FinanceStorage {
  const FinanceStorage();

  static const _transactionsKey = 'leyli_finance_transactions_v1';
  static const _settingsKey = 'leyli_finance_settings_v1';

  static final ValueNotifier<List<PaymentTransaction>> transactionsNotifier =
      ValueNotifier<List<PaymentTransaction>>([]);

  /// Load global finance settings
  Future<FinanceSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) {
      final defaults = FinanceSettings(
        coupons: [
          CouponDiscount(
            code: 'RAMADAN2026',
            discountPercent: 50,
            maxUses: 200,
            usedCount: 38,
            expiresAt: DateTime.now().add(const Duration(days: 60)),
            description: '50% Qiimo dhimis bisha barakaysan ee Ramadaan',
          ),
          CouponDiscount(
            code: 'ARDAY20',
            discountPercent: 20,
            maxUses: 100,
            usedCount: 15,
            expiresAt: DateTime.now().add(const Duration(days: 90)),
            description: '20% Qiimo dhimis gaar ah oo ardayda dugsiga sare',
          ),
          CouponDiscount(
            code: 'SOMALIA',
            discountPercent: 30,
            maxUses: 50,
            usedCount: 12,
            expiresAt: DateTime.now().add(const Duration(days: 30)),
            description: '30% Qiimo dhimis xayeysiis qaran',
          ),
        ],
      );
      await saveSettings(defaults);
      return defaults;
    }

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return FinanceSettings.fromJson(map);
    } catch (_) {
      return const FinanceSettings();
    }
  }

  /// Save global finance settings
  Future<void> saveSettings(FinanceSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  /// Load all transactions, auto-seeding if empty
  Future<List<PaymentTransaction>> getTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_transactionsKey);

    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        final items = list
            .map((item) => PaymentTransaction.fromJson(item as Map<String, dynamic>))
            .toList();
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        transactionsNotifier.value = items;
        return items;
      } catch (e) {
        debugPrint('Error parsing transactions: $e');
      }
    }

    // Auto-seed realistic transactions for the demo/live testing
    final seeded = await _seedInitialTransactions();
    await _persistTransactions(seeded);
    transactionsNotifier.value = seeded;
    return seeded;
  }

  /// Record a new payment transaction
  Future<PaymentTransaction> recordTransaction({
    required String userId,
    required String studentName,
    required String studentEmail,
    required double amount,
    required String planName,
    required String paymentMethod,
    String? paymentPhone,
    String? couponCode,
    double discountAmount = 0.0,
    String? notes,
    bool activateStudent = true,
  }) async {
    final current = await getTransactions();
    final now = DateTime.now();
    final txnId = 'TXN-${now.year}${now.month.toString().padLeft(2, '0')}-${(current.length + 1).toString().padLeft(4, '0')}';
    final receiptNumber = 'REC-${now.millisecondsSinceEpoch.toString().substring(5)}';

    final txn = PaymentTransaction(
      id: txnId,
      userId: userId,
      studentName: studentName,
      studentEmail: studentEmail,
      amount: amount,
      currency: 'USD',
      planName: planName,
      paymentMethod: paymentMethod,
      paymentPhone: paymentPhone,
      status: 'completed',
      createdAt: now,
      receiptNumber: receiptNumber,
      notes: notes,
      couponCode: couponCode,
      discountAmount: discountAmount,
    );

    final updated = [txn, ...current];
    await _persistTransactions(updated);
    transactionsNotifier.value = updated;

    if (activateStudent) {
      final days = planName == 'yearly' ? 365 : 30;
      await UserAuthService.instance.activateSubscription(
        userId: userId,
        planName: planName,
        paymentMethod: paymentMethod,
        paymentPhone: paymentPhone,
        durationDays: days,
      );
    }

    return txn;
  }

  /// Mark transaction as refunded
  Future<void> refundTransaction(String transactionId, {String? reason}) async {
    final current = await getTransactions();
    final index = current.indexWhere((t) => t.id == transactionId);
    if (index < 0) return;

    final target = current[index];
    final updatedTxn = target.copyWith(
      status: 'refunded',
      notes: reason != null ? '${target.notes ?? ''} [Refunded: $reason]' : target.notes,
    );

    final list = List<PaymentTransaction>.from(current);
    list[index] = updatedTxn;
    await _persistTransactions(list);
    transactionsNotifier.value = list;

    // Revoke student subscription if active
    await UserAuthService.instance.cancelSubscription(target.userId);
  }

  /// Delete transaction permanently
  Future<void> deleteTransaction(String transactionId) async {
    final current = await getTransactions();
    final list = current.where((t) => t.id != transactionId).toList();
    await _persistTransactions(list);
    transactionsNotifier.value = list;
  }

  /// Create or update coupon
  Future<void> saveCoupon(CouponDiscount coupon) async {
    final settings = await getSettings();
    final currentCoupons = List<CouponDiscount>.from(settings.coupons);
    final index = currentCoupons.indexWhere((c) => c.code.toUpperCase() == coupon.code.toUpperCase());

    if (index >= 0) {
      currentCoupons[index] = coupon;
    } else {
      currentCoupons.insert(0, coupon);
    }

    await saveSettings(settings.copyWith(coupons: currentCoupons));
  }

  /// Toggle coupon active state
  Future<void> toggleCoupon(String code) async {
    final settings = await getSettings();
    final currentCoupons = List<CouponDiscount>.from(settings.coupons);
    final index = currentCoupons.indexWhere((c) => c.code.toUpperCase() == code.toUpperCase());

    if (index >= 0) {
      final target = currentCoupons[index];
      currentCoupons[index] = target.copyWith(isActive: !target.isActive);
      await saveSettings(settings.copyWith(coupons: currentCoupons));
    }
  }

  /// Delete coupon
  Future<void> deleteCoupon(String code) async {
    final settings = await getSettings();
    final updated = settings.coupons.where((c) => c.code.toUpperCase() != code.toUpperCase()).toList();
    await saveSettings(settings.copyWith(coupons: updated));
  }

  Future<void> _persistTransactions(List<PaymentTransaction> items) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(items.map((i) => i.toJson()).toList());
    await prefs.setString(_transactionsKey, raw);
  }

  Future<List<PaymentTransaction>> _seedInitialTransactions() async {
    final users = await UserAuthService.instance.getAllUsers();
    final now = DateTime.now();

    final list = <PaymentTransaction>[
      PaymentTransaction(
        id: 'TXN-2026-0001',
        userId: users.isNotEmpty ? users.first.id : 'user_seed_1',
        studentName: users.isNotEmpty ? users.first.displayName : 'Xasan Cali Nuur',
        studentEmail: users.isNotEmpty ? users.first.email : 'xasan.cali@gmail.com',
        amount: 40.0,
        currency: 'USD',
        planName: 'yearly',
        paymentMethod: 'EVC Plus',
        paymentPhone: '0615551234',
        status: 'completed',
        createdAt: now.subtract(const Duration(days: 12)),
        receiptNumber: 'REC-98231',
        notes: 'Diiwaangelinta VIP Sannadle ee Hormuud EVC Plus',
      ),
      PaymentTransaction(
        id: 'TXN-2026-0002',
        userId: users.length > 1 ? users[1].id : 'user_seed_2',
        studentName: users.length > 1 ? users[1].displayName : 'Faadumo Axmed',
        studentEmail: users.length > 1 ? users[1].email : 'faadumo.axmed@gmail.com',
        amount: 5.0,
        currency: 'USD',
        planName: 'monthly',
        paymentMethod: 'Zaad Service',
        paymentPhone: '0634449876',
        status: 'completed',
        createdAt: now.subtract(const Duration(days: 8)),
        receiptNumber: 'REC-98232',
        notes: 'VIP Bille - Telesom Zaad',
      ),
      PaymentTransaction(
        id: 'TXN-2026-0003',
        userId: 'user_seed_3',
        studentName: 'Cabdiraxmaan Jaamac',
        studentEmail: 'c.jaamac@gmail.com',
        amount: 5.0,
        currency: 'USD',
        planName: 'monthly',
        paymentMethod: 'Sahal',
        paymentPhone: '0647773210',
        status: 'completed',
        createdAt: now.subtract(const Duration(days: 5)),
        receiptNumber: 'REC-98233',
        notes: 'Golis Sahal Service',
      ),
      PaymentTransaction(
        id: 'TXN-2026-0004',
        userId: 'user_seed_4',
        studentName: 'Maryan Yuusuf',
        studentEmail: 'maryan.y@gmail.com',
        amount: 40.0,
        currency: 'USD',
        planName: 'yearly',
        paymentMethod: 'Waafi',
        paymentPhone: '0623334455',
        status: 'completed',
        createdAt: now.subtract(const Duration(days: 2)),
        receiptNumber: 'REC-98234',
        notes: 'Dahabshiil Waafi Payment',
      ),
      PaymentTransaction(
        id: 'TXN-2026-0005',
        userId: 'user_seed_5',
        studentName: 'Maxamed Cumar',
        studentEmail: 'm.cumar@gmail.com',
        amount: 5.0,
        currency: 'USD',
        planName: 'monthly',
        paymentMethod: 'Stripe Card',
        paymentPhone: 'Visa ending 4242',
        status: 'completed',
        createdAt: now.subtract(const Duration(hours: 4)),
        receiptNumber: 'REC-98235',
        notes: 'International Visa Card payment',
      ),
    ];

    return list;
  }
}
