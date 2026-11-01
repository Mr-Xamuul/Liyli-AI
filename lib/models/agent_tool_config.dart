/// Represents a tool available to the educational AI agent.
class AgentToolConfig {
  const AgentToolConfig({
    required this.id,
    required this.name,
    required this.somaliTitle,
    required this.description,
    this.isEnabled = true,
    this.category = 'curriculum',
    this.parameters = const {},
  });

  final String id;
  final String name;
  final String somaliTitle;
  final String description;
  final bool isEnabled;
  final String category;
  final Map<String, dynamic> parameters;

  AgentToolConfig copyWith({
    String? id,
    String? name,
    String? somaliTitle,
    String? description,
    bool? isEnabled,
    String? category,
    Map<String, dynamic>? parameters,
  }) {
    return AgentToolConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      somaliTitle: somaliTitle ?? this.somaliTitle,
      description: description ?? this.description,
      isEnabled: isEnabled ?? this.isEnabled,
      category: category ?? this.category,
      parameters: parameters ?? this.parameters,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'somaliTitle': somaliTitle,
    'description': description,
    'isEnabled': isEnabled,
    'category': category,
    'parameters': parameters,
  };

  factory AgentToolConfig.fromJson(Map<String, dynamic> json) =>
      AgentToolConfig(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        somaliTitle: json['somaliTitle'] as String? ?? '',
        description: json['description'] as String? ?? '',
        isEnabled: json['isEnabled'] as bool? ?? true,
        category: json['category'] as String? ?? 'curriculum',
        parameters: json['parameters'] as Map<String, dynamic>? ?? const {},
      );

  static List<AgentToolConfig> get defaultTools => const [
    AgentToolConfig(
      id: 'search_curriculum',
      name: 'Curriculum Catalog Search',
      somaliTitle: 'Baaraha Manhajka Fasalka',
      description:
          'Wuxuu buugaagta, cutubyada iyo casharrada fasalka hadda lagu jiro (Form) ka dhex raadiyaa mawduuca uu ardaygu soo codsaday.',
      isEnabled: true,
      category: 'search',
      parameters: {'strictFormFilter': true, 'maxCandidates': 3},
    ),
    AgentToolConfig(
      id: 'get_lesson_pdf',
      name: 'PDF Slice Content Retriever',
      somaliTitle: 'Soo Saare & Gooye PDF',
      description:
          'Wuxuu toos u aadaa faylka PDF-ka ee manhajka, wuxuuna soo gooyaa oo soo saaraa bogagga saxda ah ee casharka khuseeya.',
      isEnabled: true,
      category: 'retrieval',
      parameters: {'includeKnowledgeSummary': true, 'maxPages': 10},
    ),
    AgentToolConfig(
      id: 'intent_router',
      name: 'Model-Driven Intent Router',
      somaliTitle: 'Fahmiyaha Ujeeddada Ardayga',
      description:
          'Model-ka ayaa fahma fariinta iyo macnaha wada-hadalka, kadibna go\'aamiya in la raadiyo manhajka ama si toos ah looga jawaabo.',
      isEnabled: true,
      category: 'reasoning',
      parameters: {
        'usesConversationContext': true,
        'routesToCurriculumTools': true,
      },
    ),
    AgentToolConfig(
      id: 'conversation_memory',
      name: 'Chat Context Memory',
      somaliTitle: 'Xusuusta Wada-hadalka',
      description:
          'Wuxuu model-ka la wadaagaa fariimihii dhowaa si uu ula socdo casharka, sharaxaaddii hore, iyo waxa ardaygu hadda ula jeedo.',
      isEnabled: true,
      category: 'memory',
      parameters: {
        'recentTurns': 12,
        'maxCharacters': 6000,
        'persistedWithChatHistory': true,
      },
    ),
    AgentToolConfig(
      id: 'deep_tutor',
      name: 'Socratic Deep Tutor',
      somaliTitle: 'Macallinka Qotada Dheer',
      description:
          'Wuxuu si toos ah u sharxaa casharka marka AI-gu fahmo codsiga, wuxuuna dabagalka ardayga uga jawaabaa isagoo adeegsanaya xogta iyo macnaha chat-ka.',
      isEnabled: true,
      category: 'tutoring',
      parameters: {'mode': 'socratic', 'enableVisualExplanation': true},
    ),
    AgentToolConfig(
      id: 'clarification_guide',
      name: 'Clarification & Alternative Picker',
      somaliTitle: 'Hagaha Dib-u-habeynta & Talobixinta',
      description:
          'Marka codsiga ardaygu mugdi yahay, wuxuu si dabiici ah u weydiiyaa faahfaahinta ka maqan ama soo jeediyaa doorashooyin manhaj oo u dhow.',
      isEnabled: true,
      category: 'guidance',
      parameters: {'suggestMaxAlternatives': 4},
    ),
  ];
}
