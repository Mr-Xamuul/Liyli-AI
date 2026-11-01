/// Represents a single payment transaction recorded in Leyli AI
class PaymentTransaction {
  const PaymentTransaction({
    required this.id,
    required this.userId,
    required this.studentName,
    required this.studentEmail,
    required this.amount,
    this.currency = 'USD',
    required this.planName, // 'monthly', 'yearly', or 'custom'
    required this.paymentMethod, // 'EVC Plus', 'Zaad Service', 'Sahal', 'Waafi / e-Dahab', 'Stripe Card', 'Admin Grant'
    this.paymentPhone,
    this.status = 'completed', // 'completed', 'pending', 'refunded', 'failed'
    required this.createdAt,
    this.receiptNumber,
    this.notes,
    this.couponCode,
    this.discountAmount = 0.0,
  });

  final String id;
  final String userId;
  final String studentName;
  final String studentEmail;
  final double amount;
  final String currency;
  final String planName;
  final String paymentMethod;
  final String? paymentPhone;
  final String status;
  final DateTime createdAt;
  final String? receiptNumber;
  final String? notes;
  final String? couponCode;
  final double discountAmount;

  bool get isCompleted => status == 'completed';
  bool get isRefunded => status == 'refunded';

  String get planLabel {
    switch (planName) {
      case 'yearly':
        return 'Sannadle (Yearly VIP)';
      case 'monthly':
        return 'Bille (Monthly VIP)';
      default:
        return 'Gaar ah ($planName)';
    }
  }

  PaymentTransaction copyWith({
    String? id,
    String? userId,
    String? studentName,
    String? studentEmail,
    double? amount,
    String? currency,
    String? planName,
    String? paymentMethod,
    String? paymentPhone,
    String? status,
    DateTime? createdAt,
    String? receiptNumber,
    String? notes,
    String? couponCode,
    double? discountAmount,
  }) {
    return PaymentTransaction(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      studentName: studentName ?? this.studentName,
      studentEmail: studentEmail ?? this.studentEmail,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      planName: planName ?? this.planName,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentPhone: paymentPhone ?? this.paymentPhone,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      notes: notes ?? this.notes,
      couponCode: couponCode ?? this.couponCode,
      discountAmount: discountAmount ?? this.discountAmount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'studentName': studentName,
      'studentEmail': studentEmail,
      'amount': amount,
      'currency': currency,
      'planName': planName,
      'paymentMethod': paymentMethod,
      'paymentPhone': paymentPhone,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'receiptNumber': receiptNumber,
      'notes': notes,
      'couponCode': couponCode,
      'discountAmount': discountAmount,
    };
  }

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) {
    return PaymentTransaction(
      id: json['id'] as String,
      userId: json['userId'] as String? ?? 'unknown',
      studentName: json['studentName'] as String? ?? 'Arday',
      studentEmail: json['studentEmail'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 5.0,
      currency: json['currency'] as String? ?? 'USD',
      planName: json['planName'] as String? ?? 'monthly',
      paymentMethod: json['paymentMethod'] as String? ?? 'EVC Plus',
      paymentPhone: json['paymentPhone'] as String?,
      status: json['status'] as String? ?? 'completed',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      receiptNumber: json['receiptNumber'] as String?,
      notes: json['notes'] as String?,
      couponCode: json['couponCode'] as String?,
      discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Coupon / Discount code configuration
class CouponDiscount {
  const CouponDiscount({
    required this.code,
    required this.discountPercent, // e.g. 20 for 20%
    this.maxUses = 100,
    this.usedCount = 0,
    this.expiresAt,
    this.isActive = true,
    this.description,
  });

  final String code;
  final int discountPercent;
  final int maxUses;
  final int usedCount;
  final DateTime? expiresAt;
  final bool isActive;
  final String? description;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isAvailable => isActive && !isExpired && usedCount < maxUses;

  CouponDiscount copyWith({
    String? code,
    int? discountPercent,
    int? maxUses,
    int? usedCount,
    DateTime? expiresAt,
    bool? isActive,
    String? description,
  }) {
    return CouponDiscount(
      code: code ?? this.code,
      discountPercent: discountPercent ?? this.discountPercent,
      maxUses: maxUses ?? this.maxUses,
      usedCount: usedCount ?? this.usedCount,
      expiresAt: expiresAt ?? this.expiresAt,
      isActive: isActive ?? this.isActive,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'discountPercent': discountPercent,
      'maxUses': maxUses,
      'usedCount': usedCount,
      'expiresAt': expiresAt?.toIso8601String(),
      'isActive': isActive,
      'description': description,
    };
  }

  factory CouponDiscount.fromJson(Map<String, dynamic> json) {
    return CouponDiscount(
      code: json['code'] as String,
      discountPercent: json['discountPercent'] as int? ?? 10,
      maxUses: json['maxUses'] as int? ?? 100,
      usedCount: json['usedCount'] as int? ?? 0,
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'] as String)
          : null,
      isActive: json['isActive'] as bool? ?? true,
      description: json['description'] as String?,
    );
  }
}

/// Global financial and pricing settings configured by Admin
class FinanceSettings {
  const FinanceSettings({
    this.monthlyPrice = 5.0,
    this.yearlyPrice = 40.0,
    this.currency = 'USD',
    this.usdToSosRate = 26000.0, // 1 USD = 26,000 Somali Shillings
    this.evcPlusEnabled = true,
    this.evcMerchantNumber = '*712*61XXXXXXX*AMOUNT#',
    this.zaadEnabled = true,
    this.zaadMerchantNumber = '*220*063XXXXXXX*AMOUNT#',
    this.sahalEnabled = true,
    this.sahalMerchantNumber = '*888*064XXXXXXX*AMOUNT#',
    this.waafiEnabled = true,
    this.waafiMerchantNumber = 'MERCHANT_LEYLI_WAAFI',
    this.stripeEnabled = true,
    this.paypalEnabled = false,
    this.coupons = const [],
  });

  final double monthlyPrice;
  final double yearlyPrice;
  final String currency;
  final double usdToSosRate;

  // Gateways
  final bool evcPlusEnabled;
  final String evcMerchantNumber;
  final bool zaadEnabled;
  final String zaadMerchantNumber;
  final bool sahalEnabled;
  final String sahalMerchantNumber;
  final bool waafiEnabled;
  final String waafiMerchantNumber;
  final bool stripeEnabled;
  final bool paypalEnabled;

  final List<CouponDiscount> coupons;

  FinanceSettings copyWith({
    double? monthlyPrice,
    double? yearlyPrice,
    String? currency,
    double? usdToSosRate,
    bool? evcPlusEnabled,
    String? evcMerchantNumber,
    bool? zaadEnabled,
    String? zaadMerchantNumber,
    bool? sahalEnabled,
    String? sahalMerchantNumber,
    bool? waafiEnabled,
    String? waafiMerchantNumber,
    bool? stripeEnabled,
    bool? paypalEnabled,
    List<CouponDiscount>? coupons,
  }) {
    return FinanceSettings(
      monthlyPrice: monthlyPrice ?? this.monthlyPrice,
      yearlyPrice: yearlyPrice ?? this.yearlyPrice,
      currency: currency ?? this.currency,
      usdToSosRate: usdToSosRate ?? this.usdToSosRate,
      evcPlusEnabled: evcPlusEnabled ?? this.evcPlusEnabled,
      evcMerchantNumber: evcMerchantNumber ?? this.evcMerchantNumber,
      zaadEnabled: zaadEnabled ?? this.zaadEnabled,
      zaadMerchantNumber: zaadMerchantNumber ?? this.zaadMerchantNumber,
      sahalEnabled: sahalEnabled ?? this.sahalEnabled,
      sahalMerchantNumber: sahalMerchantNumber ?? this.sahalMerchantNumber,
      waafiEnabled: waafiEnabled ?? this.waafiEnabled,
      waafiMerchantNumber: waafiMerchantNumber ?? this.waafiMerchantNumber,
      stripeEnabled: stripeEnabled ?? this.stripeEnabled,
      paypalEnabled: paypalEnabled ?? this.paypalEnabled,
      coupons: coupons ?? this.coupons,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'monthlyPrice': monthlyPrice,
      'yearlyPrice': yearlyPrice,
      'currency': currency,
      'usdToSosRate': usdToSosRate,
      'evcPlusEnabled': evcPlusEnabled,
      'evcMerchantNumber': evcMerchantNumber,
      'zaadEnabled': zaadEnabled,
      'zaadMerchantNumber': zaadMerchantNumber,
      'sahalEnabled': sahalEnabled,
      'sahalMerchantNumber': sahalMerchantNumber,
      'waafiEnabled': waafiEnabled,
      'waafiMerchantNumber': waafiMerchantNumber,
      'stripeEnabled': stripeEnabled,
      'paypalEnabled': paypalEnabled,
      'coupons': coupons.map((c) => c.toJson()).toList(),
    };
  }

  factory FinanceSettings.fromJson(Map<String, dynamic> json) {
    return FinanceSettings(
      monthlyPrice: (json['monthlyPrice'] as num?)?.toDouble() ?? 5.0,
      yearlyPrice: (json['yearlyPrice'] as num?)?.toDouble() ?? 40.0,
      currency: json['currency'] as String? ?? 'USD',
      usdToSosRate: (json['usdToSosRate'] as num?)?.toDouble() ?? 26000.0,
      evcPlusEnabled: json['evcPlusEnabled'] as bool? ?? true,
      evcMerchantNumber: json['evcMerchantNumber'] as String? ?? '*712*61XXXXXXX*AMOUNT#',
      zaadEnabled: json['zaadEnabled'] as bool? ?? true,
      zaadMerchantNumber: json['zaadMerchantNumber'] as String? ?? '*220*063XXXXXXX*AMOUNT#',
      sahalEnabled: json['sahalEnabled'] as bool? ?? true,
      sahalMerchantNumber: json['sahalMerchantNumber'] as String? ?? '*888*064XXXXXXX*AMOUNT#',
      waafiEnabled: json['waafiEnabled'] as bool? ?? true,
      waafiMerchantNumber: json['waafiMerchantNumber'] as String? ?? 'MERCHANT_LEYLI_WAAFI',
      stripeEnabled: json['stripeEnabled'] as bool? ?? true,
      paypalEnabled: json['paypalEnabled'] as bool? ?? false,
      coupons: (json['coupons'] as List<dynamic>?)
              ?.map((item) => CouponDiscount.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
