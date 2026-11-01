class ModelAttemptLog {
  const ModelAttemptLog({
    required this.modelName,
    required this.modelId,
    required this.isSuccess,
    required this.latencyMs,
    this.errorMessage,
    required this.timestamp,
  });

  final String modelName;
  final String modelId;
  final bool isSuccess;
  final int latencyMs;
  final String? errorMessage;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'modelName': modelName,
    'modelId': modelId,
    'isSuccess': isSuccess,
    'latencyMs': latencyMs,
    if (errorMessage != null) 'errorMessage': errorMessage,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ModelAttemptLog.fromJson(Map<String, dynamic> json) =>
      ModelAttemptLog(
        modelName: json['modelName'] as String? ?? 'Aqoonta AI',
        modelId: json['modelId'] as String? ?? '',
        isSuccess: json['isSuccess'] as bool? ?? false,
        latencyMs: json['latencyMs'] as int? ?? 0,
        errorMessage: json['errorMessage'] as String?,
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
}

class AppTelemetryLog {
  const AppTelemetryLog({
    required this.id,
    required this.timestamp,
    required this.userMessage,
    this.bookId,
    this.bookTitle,
    this.bookCategory,
    this.focusChapter,
    this.focusLesson,
    this.focusSection,
    this.scopeLabel,
    this.answeredModelName,
    this.answeredModelId,
    this.responseTimeMs,
    required this.isSuccess,
    this.finalErrorMessage,
    this.attempts = const [],
  });

  final String id;
  final DateTime timestamp;
  final String userMessage;
  final String? bookId;
  final String? bookTitle;
  final String? bookCategory;
  final String? focusChapter;
  final String? focusLesson;
  final String? focusSection;
  final String? scopeLabel;
  final String? answeredModelName;
  final String? answeredModelId;
  final int? responseTimeMs;
  final bool isSuccess;
  final String? finalErrorMessage;
  final List<ModelAttemptLog> attempts;

  bool get hadFailover =>
      isSuccess && attempts.where((a) => !a.isSuccess).isNotEmpty;

  List<ModelAttemptLog> get failedAttempts =>
      attempts.where((a) => !a.isSuccess).toList();

  int get failedAttemptsCount => failedAttempts.length;

  String get formattedTime {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final second = timestamp.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String get formattedDate {
    final year = timestamp.year;
    final month = timestamp.month.toString().padLeft(2, '0');
    final day = timestamp.day.toString().padLeft(2, '0');
    return '$day/$month/$year';
  }

  String get formattedDateTime => '$formattedDate $formattedTime';

  String get bookAndScopeSummary {
    if (bookTitle == null || bookTitle!.trim().isEmpty) {
      return 'Guud (Buug lama dooran)';
    }
    final buffer = StringBuffer(bookTitle!);
    if (bookCategory != null && bookCategory!.isNotEmpty) {
      buffer.write(' (${bookCategory!})');
    }
    if (focusChapter != null && focusChapter!.isNotEmpty) {
      buffer.write(' • $focusChapter');
    }
    if (focusLesson != null && focusLesson!.isNotEmpty) {
      buffer.write(' • $focusLesson');
    }
    if (focusSection != null && focusSection!.isNotEmpty) {
      buffer.write(' • $focusSection');
    }
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'userMessage': userMessage,
    if (bookId != null) 'bookId': bookId,
    if (bookTitle != null) 'bookTitle': bookTitle,
    if (bookCategory != null) 'bookCategory': bookCategory,
    if (focusChapter != null) 'focusChapter': focusChapter,
    if (focusLesson != null) 'focusLesson': focusLesson,
    if (focusSection != null) 'focusSection': focusSection,
    if (scopeLabel != null) 'scopeLabel': scopeLabel,
    if (answeredModelName != null) 'answeredModelName': answeredModelName,
    if (answeredModelId != null) 'answeredModelId': answeredModelId,
    if (responseTimeMs != null) 'responseTimeMs': responseTimeMs,
    'isSuccess': isSuccess,
    if (finalErrorMessage != null) 'finalErrorMessage': finalErrorMessage,
    if (attempts.isNotEmpty)
      'attempts': attempts.map((a) => a.toJson()).toList(),
  };

  factory AppTelemetryLog.fromJson(Map<String, dynamic> json) => AppTelemetryLog(
    id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    userMessage: json['userMessage'] as String? ?? '',
    bookId: json['bookId'] as String?,
    bookTitle: json['bookTitle'] as String?,
    bookCategory: json['bookCategory'] as String?,
    focusChapter: json['focusChapter'] as String?,
    focusLesson: json['focusLesson'] as String?,
    focusSection: json['focusSection'] as String?,
    scopeLabel: json['scopeLabel'] as String?,
    answeredModelName: json['answeredModelName'] as String?,
    answeredModelId: json['answeredModelId'] as String?,
    responseTimeMs: json['responseTimeMs'] as int?,
    isSuccess: json['isSuccess'] as bool? ?? false,
    finalErrorMessage: json['finalErrorMessage'] as String?,
    attempts: (json['attempts'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ModelAttemptLog.fromJson)
        .toList(),
  );
}

class TelemetrySummary {
  const TelemetrySummary({
    required this.totalMessages,
    required this.totalSuccess,
    required this.totalFailed,
    required this.totalModelFailures,
    required this.avgLatencyMs,
    required this.modelSuccessCounts,
    required this.modelFailureCounts,
    required this.modelAvgLatencies,
    required this.bookUsageCounts,
    required this.recentFailures,
  });

  final int totalMessages;
  final int totalSuccess;
  final int totalFailed;
  final int totalModelFailures;
  final double avgLatencyMs;
  final Map<String, int> modelSuccessCounts;
  final Map<String, int> modelFailureCounts;
  final Map<String, double> modelAvgLatencies;
  final Map<String, int> bookUsageCounts;
  final List<ModelAttemptLog> recentFailures;

  double get successRatePercent {
    if (totalMessages == 0) return 100.0;
    return (totalSuccess / totalMessages) * 100.0;
  }
}
