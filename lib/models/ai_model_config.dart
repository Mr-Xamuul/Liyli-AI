import 'dart:convert';

class AiModelConfig {
  const AiModelConfig({
    required this.id,
    required this.displayName,
    required this.modelId,
    required this.baseUrl,
    required this.apiKey,
    required this.company,
    this.isFree = true,
    this.isVerified = false,
    this.isActive = true,
    required this.createdAt,
    this.status = 'ready', // 'models' (draft), 'testing', 'ready'
    this.apiKeyId,
    this.isTts = false,
  });

  final String id;
  final String displayName;
  final String modelId;
  final String baseUrl;
  final String apiKey;
  final String company;
  final bool isFree;
  final bool isVerified;
  final bool isActive;
  final DateTime createdAt;
  final String status; // 'models', 'testing', 'ready'
  final String? apiKeyId;
  final bool isTts;

  bool get isOpenAiCompatible {
    final comp = company.trim().toLowerCase();
    final url = baseUrl.trim().toLowerCase();
    if (comp.contains('google') || url.contains('generativelanguage.googleapis.com')) {
      return false;
    }
    return true;
  }

  bool get isReady => status == 'ready';
  bool get isTesting => status == 'testing';
  bool get isDraft => status == 'models' || status == 'draft';

  AiModelConfig copyWith({
    String? id,
    String? displayName,
    String? modelId,
    String? baseUrl,
    String? apiKey,
    String? company,
    bool? isFree,
    bool? isVerified,
    bool? isActive,
    DateTime? createdAt,
    String? status,
    String? apiKeyId,
    bool? isTts,
  }) {
    return AiModelConfig(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      modelId: modelId ?? this.modelId,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      company: company ?? this.company,
      isFree: isFree ?? this.isFree,
      isVerified: isVerified ?? this.isVerified,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      apiKeyId: apiKeyId ?? this.apiKeyId,
      isTts: isTts ?? this.isTts,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'modelId': modelId,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'company': company,
      'isFree': isFree,
      'isVerified': isVerified,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'status': status,
      'apiKeyId': apiKeyId,
      'isTts': isTts,
    };
  }

  factory AiModelConfig.fromMap(Map<String, dynamic> map) {
    return AiModelConfig(
      id: map['id'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      modelId: map['modelId'] as String? ?? '',
      baseUrl: map['baseUrl'] as String? ?? '',
      apiKey: map['apiKey'] as String? ?? '',
      company: map['company'] as String? ?? 'Google',
      isFree: map['isFree'] as bool? ?? true,
      isVerified: map['isVerified'] as bool? ?? false,
      isActive: map['isActive'] as bool? ?? true,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      status: map['status'] as String? ??
          (map['isVerified'] == true ? 'ready' : 'models'),
      apiKeyId: map['apiKeyId'] as String?,
      isTts: map['isTts'] as bool? ?? false,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory AiModelConfig.fromJson(String source) =>
      AiModelConfig.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
