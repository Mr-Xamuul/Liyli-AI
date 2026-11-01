class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.avatarColorValue = 0xFF1A73E8,
    required this.selectedForm,
    required this.createdAt,
    required this.lastLoginAt,
    this.isPaid = false,
    this.planName,
    this.paymentMethod,
    this.paymentPhone,
    this.paidAt,
    this.subscriptionExpiresAt,
  });

  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final int avatarColorValue;
  final String selectedForm;
  final DateTime createdAt;
  final DateTime lastLoginAt;

  final bool isPaid;
  final String? planName;
  final String? paymentMethod;
  final String? paymentPhone;
  final DateTime? paidAt;
  final DateTime? subscriptionExpiresAt;

  bool get isSubscriptionActive {
    if (!isPaid) return false;
    if (subscriptionExpiresAt == null) return true;
    return subscriptionExpiresAt!.isAfter(DateTime.now());
  }

  String get tierLabel => isSubscriptionActive ? 'Paid Tier (VIP)' : 'Free Tier';

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'A';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    if (photoUrl != null) 'photoUrl': photoUrl,
    'avatarColorValue': avatarColorValue,
    'selectedForm': selectedForm,
    'createdAt': createdAt.toIso8601String(),
    'lastLoginAt': lastLoginAt.toIso8601String(),
    'isPaid': isPaid,
    if (planName != null) 'planName': planName,
    if (paymentMethod != null) 'paymentMethod': paymentMethod,
    if (paymentPhone != null) 'paymentPhone': paymentPhone,
    if (paidAt != null) 'paidAt': paidAt!.toIso8601String(),
    if (subscriptionExpiresAt != null)
      'subscriptionExpiresAt': subscriptionExpiresAt!.toIso8601String(),
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String? ?? 'user_${DateTime.now().millisecondsSinceEpoch}',
    email: json['email'] as String? ?? 'arday@gmail.com',
    displayName: json['displayName'] as String? ?? 'Arday',
    photoUrl: json['photoUrl'] as String?,
    avatarColorValue: json['avatarColorValue'] as int? ?? 0xFF1A73E8,
    selectedForm: json['selectedForm'] as String? ?? 'Form 1',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    lastLoginAt: DateTime.tryParse(json['lastLoginAt'] as String? ?? '') ?? DateTime.now(),
    isPaid: json['isPaid'] as bool? ?? false,
    planName: json['planName'] as String?,
    paymentMethod: json['paymentMethod'] as String?,
    paymentPhone: json['paymentPhone'] as String?,
    paidAt: DateTime.tryParse(json['paidAt'] as String? ?? ''),
    subscriptionExpiresAt:
        DateTime.tryParse(json['subscriptionExpiresAt'] as String? ?? ''),
  );

  UserProfile copyWith({
    String? id,
    String? email,
    String? displayName,
    String? photoUrl,
    int? avatarColorValue,
    String? selectedForm,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    bool? isPaid,
    String? planName,
    String? paymentMethod,
    String? paymentPhone,
    DateTime? paidAt,
    DateTime? subscriptionExpiresAt,
  }) => UserProfile(
    id: id ?? this.id,
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
    photoUrl: photoUrl ?? this.photoUrl,
    avatarColorValue: avatarColorValue ?? this.avatarColorValue,
    selectedForm: selectedForm ?? this.selectedForm,
    createdAt: createdAt ?? this.createdAt,
    lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    isPaid: isPaid ?? this.isPaid,
    planName: planName ?? this.planName,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    paymentPhone: paymentPhone ?? this.paymentPhone,
    paidAt: paidAt ?? this.paidAt,
    subscriptionExpiresAt: subscriptionExpiresAt ?? this.subscriptionExpiresAt,
  );
}
