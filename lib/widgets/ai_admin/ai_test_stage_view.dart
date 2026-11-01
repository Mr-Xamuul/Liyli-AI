import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/ai_model_config.dart';
import '../../models/book_knowledge.dart';
import '../../models/prepared_book.dart';
import '../../services/ai_model_storage.dart';
import '../../services/ai_routing_storage.dart';
import '../../services/book_knowledge_storage.dart';
import '../../services/gemini_book_chat_service.dart';
import '../../services/gemini_tts_service.dart';
import '../../services/prepared_book_storage.dart';
import '../rich_tutor_markdown.dart';

class AiTestStageView extends StatefulWidget {
  const AiTestStageView({
    super.key,
    this.storage = const AiModelStorage(),
    this.bookStorage = const PreparedBookStorage(),
    this.routingStorage = const AiRoutingStorage(),
    this.knowledgeStorage = const BookKnowledgeStorage(),
    this.initialModel,
    this.onPromotedToReady,
  });

  final AiModelStorage storage;
  final PreparedBookStorage bookStorage;
  final AiRoutingStorage routingStorage;
  final BookKnowledgeStorage knowledgeStorage;
  final AiModelConfig? initialModel;
  final void Function(AiModelConfig model)? onPromotedToReady;

  @override
  State<AiTestStageView> createState() => _AiTestStageViewState();
}

class _AiTestStageViewState extends State<AiTestStageView> {
  final _chatService = GeminiBookChatService();
  final _ttsService = GeminiTtsService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _customTtsTextController = TextEditingController();

  // Models filtered for testing: only testing models + models in App Routing
  List<AiModelConfig> _testableModels = [];
  List<AiModelConfig> _routingTextModels = [];
  Set<String> _routingModelIds = {};

  // Selected models
  AiModelConfig? _selectedModel;
  AiModelConfig? _ttsInputTextModel; // Text generator model for voice testing

  // Books: Only published books from the library (exactly 1 book selected)
  List<PreparedBook> _publishedBooks = [];
  PreparedBook? _selectedBook;
  PreparedChapter? _selectedChapter;
  PreparedLesson? _selectedLesson;
  PreparedSection? _selectedSection;

  bool _isLoading = true;
  bool _isGenerating = false;
  String _currentProgressStatus = '';
  CancellationToken? _cancellationToken;

  // Chat message history for student chat simulation
  final List<_TestMessage> _messages = [];

  // Dedicated Voice/TTS Test State
  String _selectedVoice = 'Puck';
  double _playbackSpeed = 1.0;
  String _generatedTtsText = '';
  int? _lastTtsTextLatencyMs;
  int? _lastTtsAudioLatencyMs;
  bool _isGeneratingVoice = false;
  String _voiceProgressStep = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant AiTestStageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialModel != null &&
        widget.initialModel?.id != oldWidget.initialModel?.id) {
      _selectedModel = widget.initialModel;
      _loadData();
    }
  }

  @override
  void dispose() {
    _cancellationToken?.cancel();
    _ttsService.dispose();
    _textController.dispose();
    _customTtsTextController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // 1. Load Routing Config to identify App Routing models
    final routingConfig = await widget.routingStorage.getConfig();
    final routingIds = <String>{
      ...routingConfig.freeModelIds,
      ...routingConfig.paidModelIds,
    };

    // 2. Load Chat Models and TTS Models
    final chatModels = await widget.storage.getModels();
    final ttsModels = await widget.storage.getTtsModels();
    final allRegisteredModels = [...chatModels, ...ttsModels];

    // Filter ONLY models in testing status OR models in App Routing
    final testable = allRegisteredModels.where((m) {
      final isTestingStatus = m.status == 'testing' || m.isTesting;
      final isInRouting = routingIds.contains(m.id);
      return isTestingStatus || isInRouting;
    }).toList();

    // Text models available in routing for TTS input generation
    final routingText = chatModels
        .where((m) => routingIds.contains(m.id) && !m.isTts)
        .toList();
    if (routingText.isEmpty) {
      routingText.addAll(chatModels.where((m) => !m.isTts && m.isActive));
    }

    // 3. Load published books from library (seed if empty)
    await widget.bookStorage.seedSampleBooksIfEmpty(widget.knowledgeStorage);
    final allBooks = await widget.bookStorage.loadAll();
    final published = allBooks.where((b) => b.isPublished).toList();

    // Default book selection: exactly 1 book
    final currentBookId = _selectedBook?.id;
    PreparedBook? activeBook =
        published.where((b) => b.id == currentBookId).firstOrNull;
    activeBook ??= published.firstOrNull;

    // Default chapter and lesson
    final currentChapterId = _selectedChapter?.id;
    PreparedChapter? activeChapter = activeBook?.chapters
        .where((c) => c.id == currentChapterId)
        .firstOrNull;
    activeChapter ??= activeBook?.chapters.firstOrNull;

    PreparedLesson? activeLesson;
    if (activeChapter != null && activeChapter.lessons.isNotEmpty) {
      final currentLessonId = _selectedLesson?.id;
      activeLesson = activeChapter.lessons
          .where((l) => l.id == currentLessonId)
          .firstOrNull;
      activeLesson ??= activeChapter.lessons.firstOrNull;
    }

    // Default model selection
    final currentModelId = widget.initialModel?.id ?? _selectedModel?.id;
    AiModelConfig? activeModel =
        testable.where((m) => m.id == currentModelId).firstOrNull;
    activeModel ??= testable.where((m) => m.isTesting).firstOrNull;
    activeModel ??= testable.firstOrNull;

    // Default TTS text generator model from routing
    final currentTtsTextId = _ttsInputTextModel?.id;
    AiModelConfig? activeTtsTextModel =
        routingText.where((m) => m.id == currentTtsTextId).firstOrNull;
    activeTtsTextModel ??= routingText.firstOrNull;

    final savedVoice = await GeminiTtsService.getSavedVoice();
    final savedSpeed = await GeminiTtsService.getSavedSpeed();

    if (!mounted) return;
    setState(() {
      _routingModelIds = routingIds;
      _testableModels = testable;
      _routingTextModels = routingText;
      _selectedModel = activeModel;
      _ttsInputTextModel = activeTtsTextModel;
      _publishedBooks = published;
      _selectedBook = activeBook;
      _selectedChapter = activeChapter;
      _selectedLesson = activeLesson;
      _selectedSection = activeLesson?.sections.isNotEmpty == true
          ? activeLesson!.sections.first
          : null;
      _selectedVoice = savedVoice;
      _playbackSpeed = savedSpeed;
      _isLoading = false;
    });

    if (_messages.isEmpty && _selectedModel != null && !_selectedModel!.isTts) {
      _addSystemWelcomeMessage();
    }
  }

  void _addSystemWelcomeMessage() {
    final modelName = _selectedModel?.displayName ?? 'AI Model';
    final bookTitle = _selectedBook?.title ?? 'Buugga Manhajka';
    final isTesting = _selectedModel?.isTesting ?? false;

    _messages.add(
      _TestMessage(
        text:
            '🧪 **Xarunta Tijaabada & Qiimeynta (Stage 2: Model Testing Lab)**\n\n'
            'Waxaad hadda si toos ah u tijaabinaysaa: **$modelName** '
            '(${isTesting ? 'Marxaladda Tijaabada' : 'Kujira App Routing'}).\n\n'
            'Buugga la doortay: **$bookTitle**.\n'
            'Hab-dhaqanka chat-kan wuxuu la mid yahay chat-ka dhabta ah ee ardayga, '
            'isagoo model-ka ku xakameynaya manhajka rasmiga ah, cutubka, iyo casharka aad dooratay.',
        isUser: false,
        isSystem: true,
      ),
    );
  }

  // ==================== STUDENT CHAT SIMULATION ====================

  Future<void> _sendStudentChatPrompt({
    String? explicitText,
    TutorMode mode = TutorMode.freeChat,
  }) async {
    final text = explicitText ?? _textController.text.trim();
    if (text.isEmpty || _selectedModel == null || _isGenerating) return;

    if (explicitText == null) {
      _textController.clear();
    }

    _cancellationToken?.cancel();
    final token = CancellationToken();
    _cancellationToken = token;

    setState(() {
      _messages.add(_TestMessage(text: text, isUser: true));
      _isGenerating = true;
      _currentProgressStatus = 'Diyaarinta macluumaadka buugga & manhajka...';
    });
    _scrollToBottom();

    final stopwatch = Stopwatch()..start();
    try {
      BookKnowledge? knowledge;
      if (_selectedBook != null) {
        knowledge = await widget.knowledgeStorage.load(_selectedBook!.id);
      }

      final reply = await _chatService.ask(
        book: _selectedBook,
        knowledge: knowledge,
        focusChapter: _selectedChapter?.title,
        focusLesson: _selectedLesson?.title,
        focusSection: _selectedSection?.title,
        question: text,
        mode: mode,
        modelConfig: _selectedModel,
        studentFormLevel: _selectedBook?.category,
        availableBookTitles: _publishedBooks.map((b) => b.title).toList(),
        cancellationToken: token,
        onProgress: (msg, step) {
          if (mounted && !token.isCancelled) {
            setState(() => _currentProgressStatus = msg);
          }
        },
      );

      stopwatch.stop();
      if (!mounted || token.isCancelled) return;

      setState(() {
        _isGenerating = false;
        _messages.add(
          _TestMessage(
            text: reply,
            isUser: false,
            latencyMs: stopwatch.elapsedMilliseconds,
            modelName: _selectedModel?.displayName,
            company: _selectedModel?.company,
          ),
        );
      });
      _scrollToBottom();
    } catch (e) {
      stopwatch.stop();
      if (!mounted || token.isCancelled) return;
      setState(() {
        _isGenerating = false;
        _messages.add(
          _TestMessage(
            text: '⚠️ Fashil intii lagu jiray tijaabada: $e',
            isUser: false,
            isError: true,
            modelName: _selectedModel?.displayName,
          ),
        );
      });
      _scrollToBottom();
    }
  }

  void _stopGenerating() {
    _cancellationToken?.cancel();
    setState(() {
      _isGenerating = false;
      _currentProgressStatus = '';
    });
  }

  void _clearChatHistory() {
    setState(() {
      _messages.clear();
      _addSystemWelcomeMessage();
    });
  }

  // ==================== DEDICATED VOICE (TTS) MODEL TESTING ====================

  Future<void> _runVoiceModelTest({String? customText}) async {
    final voiceModel = _selectedModel;
    final textModel = _ttsInputTextModel;
    final book = _selectedBook;

    if (voiceModel == null || !voiceModel.isTts) return;
    if (textModel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Fadlan dooro Model-ka qoraalka (App Routing) ee casharka soo saaraya.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isGeneratingVoice = true;
      _voiceProgressStep =
          'Tallaabada 1/2: Model-ka "${textModel.displayName}" ayaa diyaarinaya cashar buugga ah...';
    });

    final totalStopwatch = Stopwatch()..start();
    int textLatency = 0;
    int audioLatency = 0;
    String lessonText = customText ?? _customTtsTextController.text.trim();

    try {
      // Step 1: If no custom text was specified, generate an authentic teaching lesson from the book
      if (lessonText.isEmpty) {
        final chapterTitle = _selectedChapter?.title ?? 'Cutubka Koowaad';
        final lessonTitle = _selectedLesson?.title ?? chapterTitle;
        final scopeDesc =
            'Buugga "${book?.title ?? 'Manhajka'}", Cutubka "$chapterTitle", Casharka "$lessonTitle"';

        final lessonPrompt =
            'Fadlan ardayga u sharrax casharkan si nidaamsan oo xiiso leh: $scopeDesc. '
            'Bixi cashar kooban oo dabiici ah oo ku qoran af-Soomaali fudud oo aad ugu habboon in cod macallin lagu akhriyo. '
            'Ha isticmaalin jaantusyo ama calaamado adag, si toos ah casharka u bilow adigoo ardayga salaamaya.';

        BookKnowledge? knowledge;
        if (book != null) {
          knowledge = await widget.knowledgeStorage.load(book.id);
        }

        final textStopwatch = Stopwatch()..start();
        lessonText = await _chatService.ask(
          book: book,
          knowledge: knowledge,
          focusChapter: _selectedChapter?.title,
          focusLesson: _selectedLesson?.title,
          focusSection: _selectedSection?.title,
          question: lessonPrompt,
          mode: TutorMode.teach,
          modelConfig: textModel,
          studentFormLevel: book?.category,
        );
        textStopwatch.stop();
        textLatency = textStopwatch.elapsedMilliseconds;
      }

      if (!mounted) return;
      setState(() {
        _generatedTtsText = lessonText;
        _customTtsTextController.text = lessonText;
        _lastTtsTextLatencyMs = textLatency > 0 ? textLatency : null;
        _voiceProgressStep =
            'Tallaabada 2/2: Model-ka Codka "${voiceModel.displayName}" ayaa hadda u rogeya cod...';
      });

      // Step 2: Synthesize audio using the voice model under test
      final audioStopwatch = Stopwatch()..start();
      await _ttsService.speak(
        id: 'voice_test_${DateTime.now().millisecondsSinceEpoch}',
        text: lessonText,
        modelConfig: voiceModel,
        voiceName: _selectedVoice,
      );
      audioStopwatch.stop();
      audioLatency = audioStopwatch.elapsedMilliseconds;

      totalStopwatch.stop();
      if (!mounted) return;
      setState(() {
        _lastTtsAudioLatencyMs = audioLatency;
        _isGeneratingVoice = false;
        _voiceProgressStep = '';
      });
    } catch (e) {
      totalStopwatch.stop();
      if (!mounted) return;
      setState(() {
        _isGeneratingVoice = false;
        _voiceProgressStep = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Fashil intii lagu jiray tijaabada codka: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  // ==================== PROMOTION TO READY ====================

  Future<void> _promoteToReady() async {
    final model = _selectedModel;
    if (model == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.verified_rounded, color: Color(0xFF16A34A)),
            SizedBox(width: 10),
            Text('Fasax Model-kan (Promote to Ready)?'),
          ],
        ),
        content: Text(
          'Ma xaqiijinaysaa in model-ka "${model.displayName}" uu ku guuleystay tijaabada '
          'oo uu diyaar u yahay in loo gudbiyo Qaybta 3 (Models Diyaar ah)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Jooji'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Haa, Fasax & Gudbi'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final ttsModels = await widget.storage.getTtsModels();
      final isTts = model.isTts || ttsModels.any((m) => m.id == model.id);
      await widget.storage.promoteModelToReady(model.id, isTts: isTts);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Hambalyo! Model-ka "${model.displayName}" waxaa loo gudbiyay Qaybta 3 (Models Diyaar ah)!',
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );

      await _loadData();
      widget.onPromotedToReady?.call(model);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ==================== BUILD UI ====================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isVoiceModel = _selectedModel?.isTts == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Control Header Bar: Model Selector + Published Book Selector + Scope Selector
        _buildConfigHeader(isVoiceModel),
        const SizedBox(height: 12),

        // 2. Main Workspace Body: Either Voice Testing Lab or Student Chat Simulation
        Expanded(
          child: isVoiceModel
              ? _buildVoiceTestingLab()
              : _buildStudentChatSandbox(),
        ),
      ],
    );
  }

  /// Top Configuration Bar
  Widget _buildConfigHeader(bool isVoiceModel) {
    final isTestingStage = _selectedModel?.isTesting ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Title Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isVoiceModel
                      ? const Color(0xFF7C3AED).withValues(alpha: 0.1)
                      : const Color(0xFF0284C7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isVoiceModel
                      ? Icons.record_voice_over_rounded
                      : Icons.science_rounded,
                  color: isVoiceModel
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF0284C7),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isVoiceModel
                              ? 'Tijaabada Model-ka Codka (Voice AI Test Lab)'
                              : 'Tijaabada & Qiimeynta (Stage 2: Student Chat Simulation)',
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isTestingStage
                                ? const Color(0xFF0284C7).withValues(alpha: 0.1)
                                : const Color(0xFF16A34A).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isTestingStage ? 'In Testing' : 'App Routing',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: isTestingStage
                                  ? const Color(0xFF0284C7)
                                  : const Color(0xFF16A34A),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isVoiceModel
                          ? 'Model-ka codka waxaa casharka buugga ugu soo saaraya model-ka App Routing, kadibna codka ayaa lagu tijaabinayaa.'
                          : 'Tijaabi fahamka buugga, xawaaraha, iyo hab-dhismeedka jawaabaha ardayga ka hor inta aan la fasixin.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),

              // Promote button if model is in testing
              if (isTestingStage) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _promoteToReady,
                  icon: const Icon(Icons.verified_rounded, size: 16),
                  label: const Text('Fasax & U Gudbi Diyaar ah'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Selector Row: Model Picker + Book Picker (Published only) + Chapter Picker
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 1. Model Selector Dropdown (Only testing models + App Routing models)
              SizedBox(
                width: 320,
                child: DropdownButtonFormField<String>(
                  value: _selectedModel?.id,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Model-ka la Tijaabinayo',
                    prefixIcon: Icon(
                      isVoiceModel
                          ? Icons.record_voice_over_rounded
                          : Icons.smart_toy_rounded,
                      size: 18,
                      color: isVoiceModel
                          ? const Color(0xFF7C3AED)
                          : const Color(0xFF0284C7),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: _testableModels.map((m) {
                    final inTest = m.status == 'testing' || m.isTesting;
                    final inRouting = _routingModelIds.contains(m.id);
                    final tag = inTest
                        ? '★ Test'
                        : (inRouting ? '⚡ Routing' : '');

                    return DropdownMenuItem(
                      value: m.id,
                      child: Row(
                        children: [
                          Icon(
                            m.isTts
                                ? Icons.mic_rounded
                                : Icons.smart_toy_outlined,
                            size: 15,
                            color: m.isTts
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFF0284C7),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${m.displayName} (${m.company})',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: inTest
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (tag.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              tag,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: inTest
                                    ? const Color(0xFF0284C7)
                                    : const Color(0xFFEA580C),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (id) {
                    final found =
                        _testableModels.where((m) => m.id == id).firstOrNull;
                    if (found != null) {
                      setState(() {
                        _selectedModel = found;
                      });
                      if (!found.isTts && _messages.isEmpty) {
                        _addSystemWelcomeMessage();
                      }
                    }
                  },
                ),
              ),

              // 2. Book Selector (ONLY Published Books in the library)
              SizedBox(
                width: 300,
                child: DropdownButtonFormField<String>(
                  value: _selectedBook?.id,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Buugga Maktabadda (1 Book)',
                    prefixIcon: const Icon(
                      Icons.menu_book_rounded,
                      size: 18,
                      color: Color(0xFF0022FF),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: _publishedBooks.isEmpty
                      ? [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Ma jiro buug lasoo fasaxay'),
                          ),
                        ]
                      : _publishedBooks.map((b) {
                          return DropdownMenuItem(
                            value: b.id,
                            child: Text(
                              '${b.title} (${b.category})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                  onChanged: (id) {
                    final found =
                        _publishedBooks.where((b) => b.id == id).firstOrNull;
                    if (found != null) {
                      setState(() {
                        _selectedBook = found;
                        _selectedChapter = found.chapters.isNotEmpty
                            ? found.chapters.first
                            : null;
                        _selectedLesson =
                            _selectedChapter?.lessons.isNotEmpty == true
                                ? _selectedChapter!.lessons.first
                                : null;
                        _selectedSection =
                            _selectedLesson?.sections.isNotEmpty == true
                                ? _selectedLesson!.sections.first
                                : null;
                      });
                    }
                  },
                ),
              ),

              // 3. Chapter Selector
              if (_selectedBook != null &&
                  _selectedBook!.chapters.isNotEmpty) ...[
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String?>(
                    value: _selectedChapter?.id,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Cutubka (Chapter)',
                      prefixIcon: const Icon(
                        Icons.bookmark_outline_rounded,
                        size: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'Dhammaan Cutubyada',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                      ..._selectedBook!.chapters.map((c) {
                        return DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(
                            c.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        );
                      }),
                    ],
                    onChanged: (chId) {
                      setState(() {
                        _selectedChapter = _selectedBook!.chapters
                            .where((c) => c.id == chId)
                            .firstOrNull;
                        _selectedLesson =
                            _selectedChapter?.lessons.isNotEmpty == true
                                ? _selectedChapter!.lessons.first
                                : null;
                        _selectedSection =
                            _selectedLesson?.sections.isNotEmpty == true
                                ? _selectedLesson!.sections.first
                                : null;
                      });
                    },
                  ),
                ),
              ],

              // 4. Lesson Selector (if chapter has lessons)
              if (_selectedChapter != null &&
                  _selectedChapter!.lessons.isNotEmpty) ...[
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String?>(
                    value: _selectedLesson?.id,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Casharka (Lesson)',
                      prefixIcon: const Icon(
                        Icons.school_outlined,
                        size: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'Dhammaan Casharrada',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                      ..._selectedChapter!.lessons.map((l) {
                        return DropdownMenuItem<String?>(
                          value: l.id,
                          child: Text(
                            l.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        );
                      }),
                    ],
                    onChanged: (lId) {
                      setState(() {
                        _selectedLesson = _selectedChapter!.lessons
                            .where((l) => l.id == lId)
                            .firstOrNull;
                        _selectedSection =
                            _selectedLesson?.sections.isNotEmpty == true
                                ? _selectedLesson!.sections.first
                                : null;
                      });
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ==================== DEDICATED VOICE TESTING LAB ====================

  Widget _buildVoiceTestingLab() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Voice Configuration Strip
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFBF8FF),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Input Text Model Dropdown (App Routing Text Model)
                SizedBox(
                  width: 300,
                  child: DropdownButtonFormField<String>(
                    value: _ttsInputTextModel?.id,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Model-ka Soo Saaraya Qoraalka (App Routing)',
                      prefixIcon: const Icon(
                        Icons.alt_route_rounded,
                        size: 18,
                        color: Color(0xFFEA580C),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: _routingTextModels.map((m) {
                      return DropdownMenuItem(
                        value: m.id,
                        child: Text(
                          '${m.displayName} (${m.company})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      );
                    }).toList(),
                    onChanged: (id) {
                      final found =
                          _routingTextModels.where((m) => m.id == id).firstOrNull;
                      if (found != null) {
                        setState(() => _ttsInputTextModel = found);
                      }
                    },
                  ),
                ),

                // Voice Selector Dropdown
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    value: _selectedVoice,
                    decoration: InputDecoration(
                      labelText: 'Calaamadda Codka (Voice)',
                      prefixIcon: const Icon(
                        Icons.graphic_eq_rounded,
                        size: 18,
                        color: Color(0xFF7C3AED),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: GeminiTtsService.availableVoices.map((v) {
                      return DropdownMenuItem(
                        value: v['id'],
                        child: Text(
                          '${v['title']} (${v['type']})',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _selectedVoice = v);
                        GeminiTtsService.saveVoice(v);
                      }
                    },
                  ),
                ),

                // Playback Speed
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<double>(
                    value: _playbackSpeed,
                    decoration: InputDecoration(
                      labelText: 'Xawaaraha (Speed)',
                      prefixIcon: const Icon(Icons.speed_rounded, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0.75, child: Text('0.75x Deggan')),
                      DropdownMenuItem(value: 1.0, child: Text('1.0x Caadi')),
                      DropdownMenuItem(value: 1.25, child: Text('1.25x Dhaqso')),
                    ],
                    onChanged: (s) {
                      if (s != null) {
                        setState(() => _playbackSpeed = s);
                        GeminiTtsService.saveSpeed(s);
                      }
                    },
                  ),
                ),

                // Generate & Speak Action Button
                FilledButton.icon(
                  onPressed: _isGeneratingVoice ? null : () => _runVoiceModelTest(),
                  icon: _isGeneratingVoice
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_circle_fill_rounded, size: 20),
                  label: Text(
                    _isGeneratingVoice
                        ? 'Waa la diyaarinayaa...'
                        : 'Soo Saar Cashar & Dhegeyso Codka',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Voice Status or Progress Alert
          if (_isGeneratingVoice && _voiceProgressStep.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFF3E8FF),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _voiceProgressStep,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B21A8),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Voice Content & Player Area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Audio Playback & Latency Bar (if generated)
                  if (_generatedTtsText.isNotEmpty ||
                      _lastTtsAudioLatencyMs != null) ...[
                    _buildVoicePlaybackCard(),
                    const SizedBox(height: 16),
                  ],

                  // Editable Transcript of the Lesson Text
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Qoraalka Casharka ee Codka lagu Tijaabinayo:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      if (_generatedTtsText.isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: _generatedTtsText),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Qoraalka waa la koobiyay!'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Koobiyeey Qoraalka'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    controller: _customTtsTextController,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText:
                          'Halkan waxaa kusoo bixi doona casharka uu model-ka qoraalku kasoo saaro buugga "${_selectedBook?.title ?? ''}". '
                          'Sidoo kale waad wax ka beddeli kartaa ama qoraal kasta oo aad rabto waad ku tijaabin kartaa...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFFAFAFA),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _isGeneratingVoice
                          ? null
                          : () {
                              final text = _customTtsTextController.text.trim();
                              if (text.isNotEmpty) {
                                _runVoiceModelTest(customText: text);
                              }
                            },
                      icon: const Icon(Icons.volume_up_rounded, size: 18),
                      label: const Text('Ku Dhegeyso Qoraalkan la Beddelay'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Voice playback card showing real-time player and latency metrics
  Widget _buildVoicePlaybackCard() {
    return ValueListenableBuilder<TtsPlaybackState>(
      valueListenable: _ttsService.stateNotifier,
      builder: (context, ttsState, _) {
        final isPlaying = ttsState.status == TtsStatus.playing;
        final isLoading = ttsState.status == TtsStatus.loading;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2E1065), Color(0xFF4C1D95)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4C1D95).withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  // Play/Pause Action Button
                  IconButton.filled(
                    onPressed: isLoading
                        ? null
                        : () {
                            if (isPlaying) {
                              _ttsService.stop();
                            } else {
                              final text =
                                  _customTtsTextController.text.trim().isNotEmpty
                                      ? _customTtsTextController.text.trim()
                                      : _generatedTtsText;
                              if (text.isNotEmpty) {
                                _ttsService.speak(
                                  id: 'replay_${text.hashCode}',
                                  text: text,
                                  modelConfig: _selectedModel,
                                  voiceName: _selectedVoice,
                                );
                              }
                            }
                          },
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 26,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF4C1D95),
                      padding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _selectedModel?.displayName ?? 'Voice Model',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Voice: $_selectedVoice',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isPlaying
                              ? 'Codka ayaa hadda socda (Playing)...'
                              : (isLoading
                                  ? 'Diyaarinta codka...'
                                  : 'Codka wuu diyaar yahay. Guji play si aad u dhegeysato.'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Stop button
                  if (isPlaying)
                    IconButton(
                      tooltip: 'Jooji',
                      icon: const Icon(Icons.stop_rounded, color: Colors.white),
                      onPressed: () => _ttsService.stop(),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 10),

              // Latency Performance Metrics Strip
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  if (_lastTtsTextLatencyMs != null)
                    _buildLatencyPill(
                      label: 'Qoraalka (${_ttsInputTextModel?.displayName ?? 'LLM'})',
                      latencyMs: _lastTtsTextLatencyMs!,
                      color: const Color(0xFFFDE047),
                    ),
                  if (_lastTtsAudioLatencyMs != null)
                    _buildLatencyPill(
                      label: 'Codka (${_selectedModel?.displayName ?? 'TTS'})',
                      latencyMs: _lastTtsAudioLatencyMs!,
                      color: const Color(0xFF86EFAC),
                    ),
                  if (_lastTtsTextLatencyMs != null &&
                      _lastTtsAudioLatencyMs != null)
                    _buildLatencyPill(
                      label: 'Wadarta Guud (Total)',
                      latencyMs: _lastTtsTextLatencyMs! + _lastTtsAudioLatencyMs!,
                      color: Colors.white,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLatencyPill({
    required String label,
    required int latencyMs,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          Text(
            '$latencyMs ms',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== STUDENT CHAT SANDBOX (TEXT MODEL) ====================

  Widget _buildStudentChatSandbox() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Student Tutor Mode Action Bar
          _buildStudentActionModesBar(),

          // Chat Messages List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isGenerating ? 1 : 0),
              itemBuilder: (context, idx) {
                if (idx < _messages.length) {
                  return _buildTestMessageCard(_messages[idx]);
                }
                return _buildGeneratingBubble();
              },
            ),
          ),

          // Student Input Bar
          _buildStudentInputBar(),
        ],
      ),
    );
  }

  /// Student Tutor Action Modes Bar matching student chat
  Widget _buildStudentActionModesBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text(
              'Hababka Ardayga: ',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 8),

            _buildStudentModeChip(
              icon: Icons.school_rounded,
              label: 'Baro qaybtaan',
              tooltip: 'Cashar nidaamsan oo tillaabo-tillaabo ah',
              onTap: () {
                final scope = _selectedLesson?.title ??
                    _selectedChapter?.title ??
                    _selectedBook?.title ??
                    'qaybtan';
                _sendStudentChatPrompt(
                  explicitText: 'Fadlan i bar $scope si qoto dheer oo tillaabo-tillaabo ah.',
                  mode: TutorMode.teach,
                );
              },
            ),
            const SizedBox(width: 6),

            _buildStudentModeChip(
              icon: Icons.lightbulb_outline_rounded,
              label: 'I sharax',
              tooltip: 'Sharaxaad kooban iyo tusaale nololeed',
              onTap: () {
                final scope = _selectedLesson?.title ??
                    _selectedChapter?.title ??
                    _selectedBook?.title ??
                    'cutubkan';
                _sendStudentChatPrompt(
                  explicitText: 'Fadlan si faahfaahsan oo fudud iigu sharrax $scope adigoo tusaale nololeed bixinaya.',
                  mode: TutorMode.explain,
                );
              },
            ),
            const SizedBox(width: 6),

            _buildStudentModeChip(
              icon: Icons.quiz_outlined,
              label: 'Is-tijaabi (Quiz)',
              tooltip: '3 Su\'aalood oo Multiple Choice ah',
              onTap: () {
                final scope = _selectedLesson?.title ??
                    _selectedChapter?.title ??
                    _selectedBook?.title ??
                    'casharkan';
                _sendStudentChatPrompt(
                  explicitText: 'Fadlan iga weydii 3 su\'aalood oo xulasho ah (Multiple Choice Quiz: A, B, C, D) oo ku saabsan $scope.',
                  mode: TutorMode.quiz,
                );
              },
            ),
            const SizedBox(width: 6),

            _buildStudentModeChip(
              icon: Icons.summarize_outlined,
              label: 'Dulucda (Summary)',
              tooltip: 'Qodobbada muhiimka ah ee la koobay',
              onTap: () {
                final scope = _selectedLesson?.title ??
                    _selectedChapter?.title ??
                    _selectedBook?.title ??
                    'cutubkan';
                _sendStudentChatPrompt(
                  explicitText: 'Fadlan i sii dulucda iyo qodobbada ugu muhiimsan ee $scope.',
                  mode: TutorMode.summary,
                );
              },
            ),
            const SizedBox(width: 6),

            _buildStudentModeChip(
              icon: Icons.image_search_rounded,
              label: 'Sharax Sawirrada',
              tooltip: 'Falanqee jaantusyada iyo shaxannada',
              onTap: () {
                final scope = _selectedLesson?.title ??
                    _selectedChapter?.title ??
                    _selectedBook?.title ??
                    'casharkan';
                _sendStudentChatPrompt(
                  explicitText: 'Fadlan si gaar ah u falanqee oo sharrax jaantusyada ama sawirrada ku jira $scope.',
                  mode: TutorMode.visuals,
                );
              },
            ),
            const SizedBox(width: 12),

            // Clear chat action
            InkWell(
              onTap: _clearChatHistory,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.refresh_rounded,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Nadiifi',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentModeChip({
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: ActionChip(
        avatar: Icon(icon, size: 14, color: const Color(0xFF0022FF)),
        label: Text(label, style: const TextStyle(fontSize: 11.5)),
        onPressed: _isGenerating ? null : onTap,
        visualDensity: VisualDensity.compact,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade300),
        ),
      ),
    );
  }

  /// Student Chat Input Bar
  Widget _buildStudentInputBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              enabled: !_isGenerating,
              onSubmitted: (_) => _sendStudentChatPrompt(),
              decoration: InputDecoration(
                hintText: _selectedLesson != null
                    ? 'Qor su\'aal ku saabsan "${_selectedLesson!.title}"...'
                    : (_selectedChapter != null
                        ? 'Qor su\'aal ku saabsan "${_selectedChapter!.title}"...'
                        : 'Qor su\'aasha aad ku tijaabinayso model-ka...'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Send / Cancel button
          _isGenerating
              ? IconButton.filled(
                  tooltip: 'Jooji',
                  onPressed: _stopGenerating,
                  icon: const Icon(Icons.stop_rounded, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(12),
                  ),
                )
              : IconButton.filled(
                  tooltip: 'Dir',
                  onPressed: () => _sendStudentChatPrompt(),
                  icon: const Icon(Icons.send_rounded, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF0022FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(12),
                  ),
                ),
        ],
      ),
    );
  }

  /// Message Bubble Card
  Widget _buildTestMessageCard(_TestMessage msg) {
    if (msg.isSystem) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: Color(0xFF16A34A),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg.text,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Color(0xFF166534),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 550),
          margin: const EdgeInsets.only(bottom: 12, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0022FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SelectableText(
            msg.text,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
          ),
        ),
      );
    }

    // AI Response card
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 780),
        margin: const EdgeInsets.only(bottom: 16, right: 40),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: msg.isError ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: msg.isError ? const Color(0xFFFECACA) : Colors.grey.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header stats
            Row(
              children: [
                Icon(
                  Icons.smart_toy_rounded,
                  size: 16,
                  color: msg.isError ? Colors.red : const Color(0xFF0022FF),
                ),
                const SizedBox(width: 6),
                Text(
                  msg.modelName ?? (_selectedModel?.displayName ?? 'AI Model'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (msg.company != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      msg.company!,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),

                // Latency Badge
                if (msg.latencyMs != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '⚡ ${msg.latencyMs} ms',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // TTS Audio Listen Button
                ValueListenableBuilder<TtsPlaybackState>(
                  valueListenable: _ttsService.stateNotifier,
                  builder: (context, ttsState, _) {
                    final msgId = 'test_msg_${msg.text.hashCode}';
                    final isPlaying = ttsState.isPlayingFor(msgId);
                    final isLoading = ttsState.isLoadingFor(msgId);

                    return IconButton(
                      tooltip: isPlaying ? 'Jooji Codka' : 'Dhegeyso Codka TTS',
                      icon: isLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              isPlaying
                                  ? Icons.stop_circle_rounded
                                  : Icons.volume_up_rounded,
                              size: 18,
                              color: isPlaying
                                  ? const Color(0xFF7C3AED)
                                  : Colors.grey.shade700,
                            ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        if (isPlaying) {
                          _ttsService.stop();
                        } else {
                          _ttsService.speak(
                            id: msgId,
                            text: msg.text,
                            modelConfig: _selectedModel?.isTts == true
                                ? _selectedModel
                                : null,
                          );
                        }
                      },
                    );
                  },
                ),

                // Copy Text Button
                IconButton(
                  tooltip: 'Koobiyeey',
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: msg.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Jawaabta waa la koobiyay!'),
                      ),
                    );
                  },
                ),
              ],
            ),
            const Divider(height: 14),

            // Content rendered in Rich Tutor Markdown
            RichTutorMarkdown(text: msg.text, isUser: false),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              _currentProgressStatus.isNotEmpty
                  ? _currentProgressStatus
                  : 'Model-ka ayaa diyaarinaya jawaabta & falanqaynta...',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestMessage {
  _TestMessage({
    required this.text,
    required this.isUser,
    this.isSystem = false,
    this.isError = false,
    this.latencyMs,
    this.modelName,
    this.company,
  });

  final String text;
  final bool isUser;
  final bool isSystem;
  final bool isError;
  final int? latencyMs;
  final String? modelName;
  final String? company;
}
