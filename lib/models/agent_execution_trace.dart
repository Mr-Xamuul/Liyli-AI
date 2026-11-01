import 'dart:convert';

/// Helper to format latency durations consistently into seconds ('s') and minutes ('min').
/// Examples:
///   450ms -> '0.45s'
///   4500ms -> '4.5s'
///   381069ms -> '6min 21s'
String formatTraceDuration(int ms) {
  if (ms <= 0) return '0s';
  if (ms < 1000) {
    final sec = (ms / 1000).toStringAsFixed(2);
    return '${sec}s';
  }
  final totalSeconds = ms ~/ 1000;
  if (totalSeconds < 60) {
    final sec = (ms / 1000).toStringAsFixed(1);
    return '${sec}s';
  }
  final minutes = totalSeconds ~/ 60;
  final remainingSeconds = totalSeconds % 60;
  if (remainingSeconds == 0) {
    return '${minutes}min';
  }
  return '${minutes}min ${remainingSeconds}s';
}

enum AgentVerificationStatus {
  searching,
  pendingConfirmation,
  accepted,
  rejected,
  failed,
}

class AgentModelCallLog {
  const AgentModelCallLog({
    required this.stepIndex,
    required this.callType,
    required this.latencyMs,
    required this.isSuccess,
    this.modelName,
    this.errorMessage,
    required this.timestamp,
  });

  final int stepIndex;
  final String callType;
  final int latencyMs;
  final bool isSuccess;
  final String? modelName;
  final String? errorMessage;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'stepIndex': stepIndex,
    'callType': callType,
    'latencyMs': latencyMs,
    'isSuccess': isSuccess,
    if (modelName != null) 'modelName': modelName,
    if (errorMessage != null) 'errorMessage': errorMessage,
    'timestamp': timestamp.toIso8601String(),
  };

  factory AgentModelCallLog.fromJson(Map<String, dynamic> json) =>
      AgentModelCallLog(
        stepIndex: json['stepIndex'] as int? ?? 1,
        callType: json['callType'] as String? ?? 'Model API Call',
        latencyMs: json['latencyMs'] as int? ?? 0,
        isSuccess: json['isSuccess'] as bool? ?? true,
        modelName: json['modelName'] as String?,
        errorMessage: json['errorMessage'] as String?,
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
}

class AgentToolCallLog {
  const AgentToolCallLog({
    required this.toolId,
    required this.toolName,
    required this.arguments,
    this.outputSummary,
    this.rawOutput,
    required this.latencyMs,
    required this.isSuccess,
    this.errorMessage,
    required this.timestamp,
  });

  final String toolId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final String? outputSummary;
  final dynamic rawOutput;
  final int latencyMs;
  final bool isSuccess;
  final String? errorMessage;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'toolId': toolId,
    'toolName': toolName,
    'arguments': arguments,
    'outputSummary': outputSummary,
    if (rawOutput != null) 'rawOutput': rawOutput,
    'latencyMs': latencyMs,
    'isSuccess': isSuccess,
    if (errorMessage != null) 'errorMessage': errorMessage,
    'timestamp': timestamp.toIso8601String(),
  };

  factory AgentToolCallLog.fromJson(Map<String, dynamic> json) =>
      AgentToolCallLog(
        toolId: json['toolId'] as String? ?? '',
        toolName: json['toolName'] as String? ?? '',
        arguments: json['arguments'] as Map<String, dynamic>? ?? const {},
        outputSummary: json['outputSummary'] as String?,
        rawOutput: json['rawOutput'],
        latencyMs: json['latencyMs'] as int? ?? 0,
        isSuccess: json['isSuccess'] as bool? ?? false,
        errorMessage: json['errorMessage'] as String?,
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
}

class AgentExecutionTrace {
  const AgentExecutionTrace({
    required this.id,
    required this.timestamp,
    required this.userMessage,
    required this.studentForm,
    required this.internalThought,
    this.status = AgentVerificationStatus.searching,
    this.sessionId,
    this.chatTitle,
    this.systemPrompt,
    this.augmentedPrompt,
    this.injectedContext,
    this.finalAnswer,
    this.modelName,
    this.mode,
    this.matchedBookId,
    this.matchedBookTitle,
    this.matchedCategory,
    this.matchedChapterTitle,
    this.matchedLessonTitle,
    this.startPage,
    this.endPage,
    this.concisePreviewAnswer,
    this.verificationQuestion,
    this.studentFeedback,
    this.feedbackTimestamp,
    this.totalLatencyMs = 0,
    this.modelLatencyMs,
    this.modelCalls = const [],
    this.toolCalls = const [],
    this.isSuccess = true,
    this.errorMessage,
  });

  final String id;
  final DateTime timestamp;
  final String userMessage;
  final String studentForm;
  final String internalThought;
  final AgentVerificationStatus status;
  final String? sessionId;
  final String? chatTitle;
  final String? systemPrompt;
  final String? augmentedPrompt;
  final String? injectedContext;
  final String? finalAnswer;
  final String? modelName;
  final String? mode;
  final String? matchedBookId;
  final String? matchedBookTitle;
  final String? matchedCategory;
  final String? matchedChapterTitle;
  final String? matchedLessonTitle;
  final int? startPage;
  final int? endPage;
  final String? concisePreviewAnswer;
  final String? verificationQuestion;
  final String? studentFeedback;
  final DateTime? feedbackTimestamp;
  final int totalLatencyMs;
  final int? modelLatencyMs;
  final List<AgentModelCallLog> modelCalls;
  final List<AgentToolCallLog> toolCalls;
  final bool isSuccess;
  final String? errorMessage;

  int get totalToolLatencyMs =>
      toolCalls.fold(0, (sum, call) => sum + call.latencyMs);

  int get resolvedModelLatencyMs =>
      modelLatencyMs ??
      ((totalLatencyMs - totalToolLatencyMs) > 0
          ? (totalLatencyMs - totalToolLatencyMs)
          : 0);

  double get modelTimePercentage => totalLatencyMs > 0
      ? (resolvedModelLatencyMs / totalLatencyMs) * 100
      : 0.0;

  double get toolsTimePercentage =>
      totalLatencyMs > 0 ? (totalToolLatencyMs / totalLatencyMs) * 100 : 0.0;

  AgentExecutionTrace copyWith({
    String? id,
    DateTime? timestamp,
    String? userMessage,
    String? studentForm,
    String? internalThought,
    AgentVerificationStatus? status,
    String? sessionId,
    String? chatTitle,
    String? systemPrompt,
    String? augmentedPrompt,
    String? injectedContext,
    String? finalAnswer,
    String? modelName,
    String? mode,
    String? matchedBookId,
    String? matchedBookTitle,
    String? matchedCategory,
    String? matchedChapterTitle,
    String? matchedLessonTitle,
    int? startPage,
    int? endPage,
    String? concisePreviewAnswer,
    String? verificationQuestion,
    String? studentFeedback,
    DateTime? feedbackTimestamp,
    int? totalLatencyMs,
    int? modelLatencyMs,
    List<AgentModelCallLog>? modelCalls,
    List<AgentToolCallLog>? toolCalls,
    bool? isSuccess,
    String? errorMessage,
  }) {
    return AgentExecutionTrace(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      userMessage: userMessage ?? this.userMessage,
      studentForm: studentForm ?? this.studentForm,
      internalThought: internalThought ?? this.internalThought,
      status: status ?? this.status,
      sessionId: sessionId ?? this.sessionId,
      chatTitle: chatTitle ?? this.chatTitle,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      augmentedPrompt: augmentedPrompt ?? this.augmentedPrompt,
      injectedContext: injectedContext ?? this.injectedContext,
      finalAnswer: finalAnswer ?? this.finalAnswer,
      modelName: modelName ?? this.modelName,
      mode: mode ?? this.mode,
      matchedBookId: matchedBookId ?? this.matchedBookId,
      matchedBookTitle: matchedBookTitle ?? this.matchedBookTitle,
      matchedCategory: matchedCategory ?? this.matchedCategory,
      matchedChapterTitle: matchedChapterTitle ?? this.matchedChapterTitle,
      matchedLessonTitle: matchedLessonTitle ?? this.matchedLessonTitle,
      startPage: startPage ?? this.startPage,
      endPage: endPage ?? this.endPage,
      concisePreviewAnswer: concisePreviewAnswer ?? this.concisePreviewAnswer,
      verificationQuestion: verificationQuestion ?? this.verificationQuestion,
      studentFeedback: studentFeedback ?? this.studentFeedback,
      feedbackTimestamp: feedbackTimestamp ?? this.feedbackTimestamp,
      totalLatencyMs: totalLatencyMs ?? this.totalLatencyMs,
      modelLatencyMs: modelLatencyMs ?? this.modelLatencyMs,
      modelCalls: modelCalls ?? this.modelCalls,
      toolCalls: toolCalls ?? this.toolCalls,
      isSuccess: isSuccess ?? this.isSuccess,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'userMessage': userMessage,
    'studentForm': studentForm,
    'internalThought': internalThought,
    'status': status.name,
    if (sessionId != null) 'sessionId': sessionId,
    if (chatTitle != null) 'chatTitle': chatTitle,
    if (systemPrompt != null) 'systemPrompt': systemPrompt,
    if (augmentedPrompt != null) 'augmentedPrompt': augmentedPrompt,
    if (injectedContext != null) 'injectedContext': injectedContext,
    if (finalAnswer != null) 'finalAnswer': finalAnswer,
    if (modelName != null) 'modelName': modelName,
    if (mode != null) 'mode': mode,
    if (matchedBookId != null) 'matchedBookId': matchedBookId,
    if (matchedBookTitle != null) 'matchedBookTitle': matchedBookTitle,
    if (matchedCategory != null) 'matchedCategory': matchedCategory,
    if (matchedChapterTitle != null) 'matchedChapterTitle': matchedChapterTitle,
    if (matchedLessonTitle != null) 'matchedLessonTitle': matchedLessonTitle,
    if (startPage != null) 'startPage': startPage,
    if (endPage != null) 'endPage': endPage,
    if (concisePreviewAnswer != null)
      'concisePreviewAnswer': concisePreviewAnswer,
    if (verificationQuestion != null)
      'verificationQuestion': verificationQuestion,
    if (studentFeedback != null) 'studentFeedback': studentFeedback,
    if (feedbackTimestamp != null)
      'feedbackTimestamp': feedbackTimestamp?.toIso8601String(),
    'totalLatencyMs': totalLatencyMs,
    if (modelLatencyMs != null) 'modelLatencyMs': modelLatencyMs,
    'modelCalls': modelCalls.map((m) => m.toJson()).toList(),
    'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
    'isSuccess': isSuccess,
    if (errorMessage != null) 'errorMessage': errorMessage,
  };

  factory AgentExecutionTrace.fromJson(Map<String, dynamic> json) =>
      AgentExecutionTrace(
        id: json['id'] as String? ?? '',
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        userMessage: json['userMessage'] as String? ?? '',
        studentForm: json['studentForm'] as String? ?? 'Form 1',
        internalThought: json['internalThought'] as String? ?? '',
        status: AgentVerificationStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => AgentVerificationStatus.searching,
        ),
        sessionId: json['sessionId'] as String?,
        chatTitle: json['chatTitle'] as String?,
        systemPrompt: json['systemPrompt'] as String?,
        augmentedPrompt: json['augmentedPrompt'] as String?,
        injectedContext: json['injectedContext'] as String?,
        finalAnswer: json['finalAnswer'] as String?,
        modelName: json['modelName'] as String?,
        mode: json['mode'] as String?,
        matchedBookId: json['matchedBookId'] as String?,
        matchedBookTitle: json['matchedBookTitle'] as String?,
        matchedCategory: json['matchedCategory'] as String?,
        matchedChapterTitle: json['matchedChapterTitle'] as String?,
        matchedLessonTitle: json['matchedLessonTitle'] as String?,
        startPage: json['startPage'] as int?,
        endPage: json['endPage'] as int?,
        concisePreviewAnswer: json['concisePreviewAnswer'] as String?,
        verificationQuestion: json['verificationQuestion'] as String?,
        studentFeedback: json['studentFeedback'] as String?,
        feedbackTimestamp: json['feedbackTimestamp'] != null
            ? DateTime.tryParse(json['feedbackTimestamp'] as String)
            : null,
        totalLatencyMs: json['totalLatencyMs'] as int? ?? 0,
        modelLatencyMs: json['modelLatencyMs'] as int?,
        modelCalls: (json['modelCalls'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AgentModelCallLog.fromJson)
            .toList(),
        toolCalls: (json['toolCalls'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AgentToolCallLog.fromJson)
            .toList(),
        isSuccess: json['isSuccess'] as bool? ?? true,
        errorMessage: json['errorMessage'] as String?,
      );

  String encode() => jsonEncode(toJson());

  static AgentExecutionTrace decode(String raw) =>
      AgentExecutionTrace.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

class AgentLiveExecution {
  AgentLiveExecution({
    required this.id,
    required this.sessionId,
    required this.chatTitle,
    required this.userMessage,
    required this.studentForm,
    this.mode,
    required this.startedAt,
    this.currentStatus = 'Bilaabista shaqada...',
    this.activeStepName = 'Tallaabada 1: Diyaarinta',
    this.currentModelName,
    List<AgentToolCallLog>? toolCalls,
    List<AgentModelCallLog>? modelCalls,
    this.isCompleted = false,
    this.isSuccess = true,
    this.finalAnswer,
    this.errorMessage,
  }) : toolCalls = toolCalls ?? [],
       modelCalls = modelCalls ?? [];

  final String id;
  final String sessionId;
  final String chatTitle;
  final String userMessage;
  final String studentForm;
  final String? mode;
  final DateTime startedAt;
  String currentStatus;
  String activeStepName;
  String? currentModelName;
  final List<AgentToolCallLog> toolCalls;
  final List<AgentModelCallLog> modelCalls;
  bool isCompleted;
  bool isSuccess;
  String? finalAnswer;
  String? errorMessage;

  int get elapsedMs => DateTime.now().difference(startedAt).inMilliseconds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'chatTitle': chatTitle,
    'userMessage': userMessage,
    'studentForm': studentForm,
    'mode': mode,
    'startedAt': startedAt.toIso8601String(),
    'currentStatus': currentStatus,
    'activeStepName': activeStepName,
    'currentModelName': currentModelName,
    'toolCalls': toolCalls.map((item) => item.toJson()).toList(),
    'modelCalls': modelCalls.map((item) => item.toJson()).toList(),
    'isCompleted': isCompleted,
    'isSuccess': isSuccess,
    'finalAnswer': finalAnswer,
    'errorMessage': errorMessage,
  };

  factory AgentLiveExecution.fromJson(Map<String, dynamic> json) =>
      AgentLiveExecution(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String? ?? '',
        chatTitle: json['chatTitle'] as String? ?? '',
        userMessage: json['userMessage'] as String? ?? '',
        studentForm: json['studentForm'] as String? ?? '',
        mode: json['mode'] as String?,
        startedAt:
            DateTime.tryParse(json['startedAt'] as String? ?? '') ??
            DateTime.now(),
        currentStatus: json['currentStatus'] as String? ?? '',
        activeStepName: json['activeStepName'] as String? ?? '',
        currentModelName: json['currentModelName'] as String?,
        toolCalls: (json['toolCalls'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(AgentToolCallLog.fromJson)
            .toList(),
        modelCalls: (json['modelCalls'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(AgentModelCallLog.fromJson)
            .toList(),
        isCompleted: json['isCompleted'] as bool? ?? false,
        isSuccess: json['isSuccess'] as bool? ?? true,
        finalAnswer: json['finalAnswer'] as String?,
        errorMessage: json['errorMessage'] as String?,
      );

  AgentLiveExecution copy() {
    return AgentLiveExecution(
      id: id,
      sessionId: sessionId,
      chatTitle: chatTitle,
      userMessage: userMessage,
      studentForm: studentForm,
      mode: mode,
      startedAt: startedAt,
      currentStatus: currentStatus,
      activeStepName: activeStepName,
      currentModelName: currentModelName,
      toolCalls: List.from(toolCalls),
      modelCalls: List.from(modelCalls),
      isCompleted: isCompleted,
      isSuccess: isSuccess,
      finalAnswer: finalAnswer,
      errorMessage: errorMessage,
    );
  }
}
