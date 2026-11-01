import 'dart:convert';

/// Represents a stored API Key entry for AI model providers
class ApiKeyConfig {
  const ApiKeyConfig({
    required this.id,
    required this.name,
    required this.provider,
    required this.apiKey,
    this.baseUrl = '',
    this.isActive = true,
    required this.createdAt,
    this.notes = '',
    this.hasSecret = false,
  });

  final String id;
  final String name; // e.g. "Gemini Official API 1", "Groq Production Key"
  final String
  provider; // "Google", "OpenAI", "Groq", "DeepSeek", "Anthropic", "Custom"
  final String apiKey;
  final String baseUrl;
  final bool isActive;
  final DateTime createdAt;
  final String notes;
  final bool hasSecret;

  ApiKeyConfig copyWith({
    String? id,
    String? name,
    String? provider,
    String? apiKey,
    String? baseUrl,
    bool? isActive,
    DateTime? createdAt,
    String? notes,
    bool? hasSecret,
  }) {
    return ApiKeyConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      notes: notes ?? this.notes,
      hasSecret: hasSecret ?? this.hasSecret,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'provider': provider,
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'notes': notes,
      'hasSecret': hasSecret,
    };
  }

  factory ApiKeyConfig.fromMap(Map<String, dynamic> map) {
    return ApiKeyConfig(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      provider: map['provider'] as String? ?? 'Google',
      apiKey: map['apiKey'] as String? ?? '',
      baseUrl: map['baseUrl'] as String? ?? '',
      isActive: map['isActive'] as bool? ?? true,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      notes: map['notes'] as String? ?? '',
      hasSecret:
          map['hasSecret'] as bool? ??
          ((map['apiKey'] as String?)?.isNotEmpty ?? false),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory ApiKeyConfig.fromJson(String source) =>
      ApiKeyConfig.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
