import 'dart:convert';

/// Configuration for intelligent AI model routing and automatic failover/fallback
class AiRoutingConfig {
  const AiRoutingConfig({
    this.freeModelIds = const [],
    this.paidModelIds = const [],
    this.ttsModelIds = const [],
    this.autoFallbackEnabled = true,
    this.ttsAutoFallbackEnabled = true,
    this.hideModelPickerFromChat = true,
    this.activeTier = 'free', // 'free' or 'paid'
    this.lastFailoverTimestamp,
    this.lastFailoverReason,
    this.lastTtsFailoverTimestamp,
    this.lastTtsFailoverReason,
  });

  /// Ordered list of model IDs for Free users: index 0 is Primary, index 1+ are Fallbacks
  final List<String> freeModelIds;

  /// Ordered list of model IDs for Paid users: index 0 is Primary, index 1+ are Fallbacks
  final List<String> paidModelIds;

  /// Ordered list of TTS model IDs for ALL students (unified, no free/paid split):
  /// index 0 is Primary Voice, index 1+ are sequential Fallbacks
  final List<String> ttsModelIds;

  /// Whether to automatically fall back to the next model if primary fails or hits rate limits
  final bool autoFallbackEnabled;

  /// Whether to automatically fall back to next TTS model if primary voice fails
  final bool ttsAutoFallbackEnabled;

  /// Hide manual model dropdown from student chat topbar
  final bool hideModelPickerFromChat;

  /// Which tier the current app session is running: 'free' or 'paid'
  final String activeTier;

  final DateTime? lastFailoverTimestamp;
  final String? lastFailoverReason;

  final DateTime? lastTtsFailoverTimestamp;
  final String? lastTtsFailoverReason;

  AiRoutingConfig copyWith({
    List<String>? freeModelIds,
    List<String>? paidModelIds,
    List<String>? ttsModelIds,
    bool? autoFallbackEnabled,
    bool? ttsAutoFallbackEnabled,
    bool? hideModelPickerFromChat,
    String? activeTier,
    DateTime? lastFailoverTimestamp,
    String? lastFailoverReason,
    DateTime? lastTtsFailoverTimestamp,
    String? lastTtsFailoverReason,
  }) {
    return AiRoutingConfig(
      freeModelIds: freeModelIds ?? this.freeModelIds,
      paidModelIds: paidModelIds ?? this.paidModelIds,
      ttsModelIds: ttsModelIds ?? this.ttsModelIds,
      autoFallbackEnabled: autoFallbackEnabled ?? this.autoFallbackEnabled,
      ttsAutoFallbackEnabled:
          ttsAutoFallbackEnabled ?? this.ttsAutoFallbackEnabled,
      hideModelPickerFromChat:
          hideModelPickerFromChat ?? this.hideModelPickerFromChat,
      activeTier: activeTier ?? this.activeTier,
      lastFailoverTimestamp:
          lastFailoverTimestamp ?? this.lastFailoverTimestamp,
      lastFailoverReason: lastFailoverReason ?? this.lastFailoverReason,
      lastTtsFailoverTimestamp:
          lastTtsFailoverTimestamp ?? this.lastTtsFailoverTimestamp,
      lastTtsFailoverReason:
          lastTtsFailoverReason ?? this.lastTtsFailoverReason,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'freeModelIds': freeModelIds,
      'paidModelIds': paidModelIds,
      'ttsModelIds': ttsModelIds,
      'autoFallbackEnabled': autoFallbackEnabled,
      'ttsAutoFallbackEnabled': ttsAutoFallbackEnabled,
      'hideModelPickerFromChat': hideModelPickerFromChat,
      'activeTier': activeTier,
      'lastFailoverTimestamp': lastFailoverTimestamp?.toIso8601String(),
      'lastFailoverReason': lastFailoverReason,
      'lastTtsFailoverTimestamp': lastTtsFailoverTimestamp?.toIso8601String(),
      'lastTtsFailoverReason': lastTtsFailoverReason,
    };
  }

  factory AiRoutingConfig.fromMap(Map<String, dynamic> map) {
    return AiRoutingConfig(
      freeModelIds: (map['freeModelIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      paidModelIds: (map['paidModelIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      ttsModelIds: (map['ttsModelIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      autoFallbackEnabled: map['autoFallbackEnabled'] as bool? ?? true,
      ttsAutoFallbackEnabled: map['ttsAutoFallbackEnabled'] as bool? ?? true,
      hideModelPickerFromChat:
          map['hideModelPickerFromChat'] as bool? ?? true,
      activeTier: map['activeTier'] as String? ?? 'free',
      lastFailoverTimestamp: map['lastFailoverTimestamp'] != null
          ? DateTime.tryParse(map['lastFailoverTimestamp'] as String)
          : null,
      lastFailoverReason: map['lastFailoverReason'] as String?,
      lastTtsFailoverTimestamp: map['lastTtsFailoverTimestamp'] != null
          ? DateTime.tryParse(map['lastTtsFailoverTimestamp'] as String)
          : null,
      lastTtsFailoverReason: map['lastTtsFailoverReason'] as String?,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory AiRoutingConfig.fromJson(String source) =>
      AiRoutingConfig.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
