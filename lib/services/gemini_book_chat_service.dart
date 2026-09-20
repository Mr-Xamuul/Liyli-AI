import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book_knowledge.dart';
import '../models/learning_session.dart';
import '../models/prepared_book.dart';

enum TutorMode {
  teach, // Baro qaybtaan: Cashar nidaamsan oo tillaabo-tillaabo ah
  visuals, // Sharax Sawirrada & Jaantusyada: Si gaar ah u falanqee jaantusyada, shaxannada, iyo sawirrada PDF-ka ku jira
  explain, // I sharax: Sharaxaad fudud iyo tusaalooyin dhab ah
  quiz, // Is-tijaabi: Su'aalo xulasho iyo is-qiimeyn ah
  summary, // Dulucda: Qodobada muhiimka ah ee la koobay
  freeChat, // Su'aasha furan ee ardaygu soo qorto
}

class GeminiBookChatService {
  GeminiBookChatService({http.Client? client, String? apiKey})
    : _customClient = client,
      _apiKey = apiKey;

  static const _prefKey = 'custom_gemini_api_key';
  static const candidateModels = [
    'gemini-3.7-flash',
    'gemini-3.6-flash',
    'gemini-3.5-flash',
  ];

  static const offlineMessage =
      '⚠️ Ma jiro xiriir internet. Fadlan hubi khadkaaga internet-ka.';

  static bool isNetworkOrOfflineError(dynamic error) {
    if (error == null) return false;
    final str = error.toString().toLowerCase();
    return error is SocketException ||
        error is http.ClientException ||
        error is HandshakeException ||
        error is TimeoutException ||
        str.contains('socketexception') ||
        str.contains('failed host lookup') ||
        str.contains('network is unreachable') ||
        str.contains('no address associated with hostname') ||
        str.contains('clientexception') ||
        str.contains('connection refused') ||
        str.contains('connection closed') ||
        str.contains('connection reset') ||
        str.contains('connection timed out') ||
        str.contains('network error') ||
        str.contains('offline') ||
        str.contains('timed out');
  }

  final http.Client? _customClient;
  final String? _apiKey;

  static Future<void> saveCustomApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, key.trim());
  }

  static Future<String?> getCustomApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }

  Future<String> _resolveApiKey() async {
    final key = _apiKey;
    if (key != null && key.isNotEmpty) return key;
    final custom = await getCustomApiKey();
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    const envKey = String.fromEnvironment('GEMINI_API_KEY');
    if (envKey.isNotEmpty) return envKey;
    throw StateError(
      'Gemini API key is not configured. Add one in the app or use '
      '--dart-define=GEMINI_API_KEY=your-key.',
    );
  }

  Future<String> ask({
    PreparedBook? book,
    BookKnowledge? knowledge,
    required String question,
    String? focusChapter,
    String? focusLesson,
    String? focusSection,
    double startPosition = 0.0,
    double endPosition = 1.0,
    Uint8List? slicedPdfBytes,
    TutorMode mode = TutorMode.freeChat,
    LearningScopeType? learningScopeType,
    int? learningPartNumber,
    int? learningPartCount,
    String priorLearningContext = '',
    bool isLessonCompletion = false,
    void Function(String message, int step)? onProgress,
    CancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled == true) {
      throw const GeminiCancelledException();
    }
    onProgress?.call('Diyaarinta xogta & falanqaynta su\'aasha...', 1);
    final apiKey = await _resolveApiKey();
    final systemPrompt = _buildSystemPrompt(mode, learningScopeType);

    if (book == null) {
      final userPrompt =
          '''
Su'aasha Ardayga: $question

Tilmaamaha Macallinka Leyli AI:
- Waxaad tahay Leyli AI, macallin Soomaaliyeed oo caqli badan oo ardayda ka caawiya dhammaan maaddooyinka waxbarashada dugsiyada (Saynis, Xisaab, Fiisigis, Kimistari, Taariikh, Juqraafi, iwm).
- Ugu jawaab su'aashiisa si hufan, cilmiyeysan, saaxiibtinimo leh oo Af-Soomaali sugan ah.
- Haddii su'aashu u baahan tahay xisaab ama qaacidooyin, adeegso qaabka LaTeX (sida \$x\$ ama \$\$...\$\$).
''';
      onProgress?.call('Xiriirinta Google Gemini AI...', 2);
      String? lastError;
      for (final model in candidateModels) {
        if (cancellationToken?.isCancelled == true) {
          throw const GeminiCancelledException();
        }
        try {
          final res = await _callGeminiApi(
            model: model,
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            pdfBytes: null,
            cancellationToken: cancellationToken,
          );
          if (cancellationToken?.isCancelled == true) {
            throw const GeminiCancelledException();
          }
          onProgress?.call('Habaynta sharraxaadda aqooneed ee Leyli AI...', 3);
          return res;
        } on GeminiCancelledException {
          rethrow;
        } catch (e) {
          if (cancellationToken?.isCancelled == true) {
            throw const GeminiCancelledException();
          }
          lastError = e.toString();
        }
      }

      if (cancellationToken?.isCancelled == true) {
        throw const GeminiCancelledException();
      }

      if (isNetworkOrOfflineError(lastError)) {
        return offlineMessage;
      }

      onProgress?.call('Habaynta sharraxaadda aqooneed ee Leyli AI...', 3);
      return '''
### 🤖 Leyli AI

Soo dhawoow! Waxaan ahay Macallinkaaga Leyli AI.

Su'aashaada: *"$question"*

Waxaad i weydiin kartaa su'aal kasta oo ku saabsan maadooyinkaaga iyo casharradaada. Haddii aad rabto inaad buug manhajka ah barato, fadlan **Maktabadda** ka dooro buug si aynu casharradiisa iyo jaantusyadiisa toos u dhuuxno!
''';
    }

    onProgress?.call(
      slicedPdfBytes != null && slicedPdfBytes.isNotEmpty
          ? 'Akhrinta bogagga PDF-ka ee la gooyay...'
          : 'Dhuuxista bogagga casharka ee buugga...',
      1,
    );

    final activeKnowledge =
        knowledge ?? BookKnowledge(bookId: book.id, pages: const {});
    final excerpts = _findRelevantPages(
      book,
      activeKnowledge,
      question,
      focusChapter: focusChapter,
      focusLesson: focusLesson,
      focusSection: focusSection,
    );

    final context = StringBuffer()
      ..writeln('Book: ${book.title}')
      ..writeln('Target Grade: ${book.category}')
      ..writeln('Current Scope:')
      ..writeln('- Chapter: ${focusChapter ?? 'Dhammaan'}')
      ..writeln('- Lesson: ${focusLesson ?? 'Dhammaan'}')
      ..writeln('- Section: ${focusSection ?? 'Dhammaan'}')
      ..writeln('\nRelevant book text fallback/context:');

    for (final page in excerpts) {
      context.writeln('--- Page $page ---');
      context.writeln(activeKnowledge.pages[page] ?? '');
    }
    context.writeln(
      _buildScopeNavigation(
        book,
        learningScopeType,
        focusChapter: focusChapter,
        focusLesson: focusLesson,
      ),
    );
    if (priorLearningContext.isNotEmpty) {
      context
        ..writeln(
          '\nCasharkii hore ee isla session-kan (u adeegso xasuus kooban; ha ku celcelin):',
        )
        ..writeln(priorLearningContext);
    }

    final userPrompt = _buildUserPrompt(
      question: question,
      mode: mode,
      focusChapter: focusChapter,
      focusLesson: focusLesson,
      focusSection: focusSection,
      startPosition: startPosition,
      endPosition: endPosition,
      hasPdf: slicedPdfBytes != null && slicedPdfBytes.isNotEmpty,
      context: context.toString(),
      learningScopeType: learningScopeType,
      learningPartNumber: learningPartNumber,
      learningPartCount: learningPartCount,
      isLessonCompletion: isLessonCompletion,
    );

    // Attempt Gemini call with active models in order
    onProgress?.call('Weydiinta Google Gemini AI & dhuuxista maaddada...', 2);
    String? lastError;
    for (final model in candidateModels) {
      if (cancellationToken?.isCancelled == true) {
        throw const GeminiCancelledException();
      }
      try {
        final res = await _callGeminiApi(
          model: model,
          apiKey: apiKey,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          pdfBytes: slicedPdfBytes,
          cancellationToken: cancellationToken,
        );
        if (cancellationToken?.isCancelled == true) {
          throw const GeminiCancelledException();
        }
        onProgress?.call('Habaynta sharraxaadda aqooneed & koodhka...', 3);
        return res;
      } on GeminiCancelledException {
        rethrow;
      } catch (e) {
        if (cancellationToken?.isCancelled == true) {
          throw const GeminiCancelledException();
        }
        lastError = e.toString();
      }
    }

    if (cancellationToken?.isCancelled == true) {
      throw const GeminiCancelledException();
    }

    if (isNetworkOrOfflineError(lastError)) {
      return offlineMessage;
    }

    // High-fidelity local tutor fallback if online Gemini calls were unavailable
    onProgress?.call(
      'Habaynta sharraxaadda aqooneed ee Macallinka Leyli...',
      3,
    );
    return _generateLocalTutorResponse(
      book: book,
      knowledge: activeKnowledge,
      pages: excerpts,
      question: question,
      mode: mode,
      focusChapter: focusChapter,
      focusLesson: focusLesson,
      focusSection: focusSection,
      learningScopeType: learningScopeType,
      apiErrorMessage: lastError,
    );
  }

  String _buildSystemPrompt(
    TutorMode mode,
    LearningScopeType? learningScopeType,
  ) {
    return '''
Waxaad tahay Leyli AI, macallin Soomaaliyeed oo caqli badan, saaxiibtinimo leh, kuna takhasusay buugaagta manhajka dugsiyada (Form 1 - Form 4).
Hawshaada:
1. Waxaad wax u dhigaysaa arday dugsiga sare ah oo buuggiisu English ku qoran yahay. Marka lesson ama section la baranayo, English-ka iyo Af-Soomaaliga isku lammaanee si ardaygu u fahmo luqadda buugga iyo macnaha casharka labadaba.
2. Marka laguu soo diro qayb PDF ah (la jaray oo ah casharka la doortay oo keliya), dhuux oo si buuxda u aqri dhammaan bogaggeeda:
   - Qoraalka, cinwaannada, qeexitaannada, iyo qodobada ugu muhiimsan.
   - Sawirrada, jaantusyada (diagrams), shaxannada, qaababka (shapes), tusaalooyinka iyo qaacidooyinka ku xusan bogaggaas.
3. Haddii casharka ay ku jiraan jaantusyo ama sawirro (sida unugyada, wareegyada, hab-dhisyada, shaxanka, tijaabooyinka cilmiga ah), si gaar ah u sharax qaybaha jaantuska, waxa calaamad kasta u taagan tahay, iyo sida loogu adeegsado fahamka casharka.
4. Jawaabahaaga u habee qaab qurux badan: adeegso cinwaanno cadcad (###), qodobbo (bullet points), tusaalooyin fudud oo la xiriira nolosha Soomaalida, iyo su'aalo dhiirigelin ah.
5. Haddii xogta la weydiiyay aysan ku jirin qaybta PDF-ka ee la soo diray, si xushmad leh u sheeg in qaybtaan hadda la doortay aysan xogtaas wadan.
6. Ha samayn xigasho dheer oo buugga ah. Adeegso weedho English ah oo gaagaaban, erayo muhiim ah, iyo sharaxaaddaada waxbarasho.
7. ${_scopeRule(learningScopeType)}
8. Haddii PDF-ka qaybta la doortay leeyahay sawir, diagram, shaxan ama graph waxbarasho oo casharka fahankiisa muhiim u ah, ku sharax halka uu ku habboon yahay jawaabta. Ha xusin sawir qurxin ah ama aan waxbarasho lahayn.
9. Qaacidooyinka iyo Xisaabta (Math & Physics Formulas):
   - QAACIDOOYINKA KALI-TAAGAN EE WAAWEYN (Display Math): Ku qor qaabka LaTeX ee \$\$...\$\$, tusaale:
     \$\$y = A \\sin(2\\pi f t)\$\$
     \$\$v = u + at\$\$
     Marnaba ha gelin qaacidooyinka xisaabta iyo fiisigiska code blocks (```).
   - ERAYADA & CALAAMADAHA DHEX-YAALKA AH (Inline Math): Ku qor hal dollar sign \$x\$, sida \$t = 3.1\\text{ s}\$.
   - CINWAANNADA: Markaad cinwaan qorayso, isticmaal `### Magaca Cinwaanka` adigoo xariiq madhan ka hor marinaya cinwaanka, kana fogaanaya meelo bannaan oo u dhexeeya astaamaha (# # #).
''';
  }

  String _buildUserPrompt({
    required String question,
    required TutorMode mode,
    required String? focusChapter,
    required String? focusLesson,
    required String? focusSection,
    double startPosition = 0.0,
    double endPosition = 1.0,
    required bool hasPdf,
    required String context,
    LearningScopeType? learningScopeType,
    int? learningPartNumber,
    int? learningPartCount,
    bool isLessonCompletion = false,
  }) {
    final scopeName =
        focusSection ??
        focusLesson ??
        focusChapter ??
        (learningScopeType == LearningScopeType.book
            ? 'Buugga oo dhan'
            : 'Qaybtaan');
    final hasBoundaryCrop = (startPosition > 0.03) || (endPosition < 0.97);
    final boundaryDetail = (hasPdf && hasBoundaryCrop)
        ? '\n⚠️ XUDUUDDA GAARKA AH EE CASHARKAN: PDF-ka sare waxaa lagu soo gooyay oo lagu xaddiday kaliya inta u dhaxeysa xariiqda ${(startPosition * 100).toInt()}% ilaa ${(endPosition * 100).toInt()}% ee bogagga calaamadeysan. Qoraallada kale ee ka baxsan xariiqahaas (sida qaybta ka horreysa ama qaybta ka dambeysa) KUMA JIRAAN casharkan, fadlan kaliya sharax inta xadkaas ku dhex jirta.\n'
        : '';
    final pdfNotice = hasPdf
        ? 'Lifaaqa sare waa PDF-ka rasmiga ah ee qaybta "$scopeName" oo kaliya (waxaa ku jira qoraalka, sawirrada, jaantusyada, iyo qaababka casharka).$boundaryDetail'
        : 'Fiiro gaar ah: Halkan waxaa ku lifaaqan qoraalka buugga ee qaybta "$scopeName".';
    final learningFormat = _learningFormat(
      learningScopeType,
      scopeName,
      learningPartNumber: learningPartNumber,
      learningPartCount: learningPartCount,
      isLessonCompletion: isLessonCompletion,
    );

    switch (mode) {
      case TutorMode.teach:
        return '''
$pdfNotice
$context

ARAGTIDA MACALLINKA (DEEP LESSON):
$learningFormat
Fadlan ardayga si faahfaahsan, hufan oo xiiso leh ugu dhig casharka/qaybta "$scopeName":
1. Ku bilow horudhac gaaban oo soo jiidasho leh.
2. Qodob-qodob oo tallaabo-tallaabo ah u sharax fikradaha ugu muhiimsan ee ku yaal bogaggaas.
3. Haddii ay casharkan ku jiraan jaantusyo (diagrams), sawirro ama shaxanno ku yaal PDF-ka, si cad u sharax qaybahooda iyo waxa ay muujinayaan.
4. Bixi ugu yaraan 1 tusaale oo la taaban karo oo nolosha dhabta ah ama deegaanka Soomaaliya ku saabsan.
5. Ku soo xir su'aal furan ama layli kooban oo ardaygu kaga fikiro casharka.
6. Haddii PDF-ka lifaaqa ah leeyahay sawir ama diagram waxbarasho oo muhiim ah, geli calaamaddan si sax ah isla markiiba ka dib faqradda sawirkaas sharxaysa: `[[LEYLI_VISUAL page=1; x=0.10; y=0.20; width=0.80; height=0.45; title=Magaca sawirka]]`. `page` waa bogga PDF-ka lifaaqa (bogga koowaad waa 1); x, y, width iyo height waa meelaha sawirka ee u dhexeeya 0 iyo 1. Ku dar ugu badnaan 2 calaamadood, oo keliya marka sawirku/diagram-ku casharka sharxayo. Ha ku darin calaamaddan haddii aan sawir waxbarasho jirin.
''';

      case TutorMode.visuals:
        return '''
$pdfNotice
$context

ARAGTIDA JAANTUSYADA & SAWIRRADA (VISUALS & DIAGRAMS):
Fadlan qaybta "$scopeName" ee PDF-ka ku jira si gaar ah uga soo saar dhammaan jaantusyada, sawirrada, shaxannada, ama jaantusyada cilmiga ah:
1. Jaantus kasta ku bixi cinwaan gaar ah oo ah `### [Magaca diagram-ka]` iyo `**Bogga PDF-ka:** [lambarka bogga ee lifaaqa]`.
2. Magacow ama sheeg sawir kasta / jaantus kasta oo bogagga casharkan ku yaal (haddii uu yahay jaantuska unugga, xubnaha, wareegga walxaha, shaxan xog ah, iwm).
3. Qodob-qodob u qor Labels & Parts: marka hore magaca English-ka ee label-ka, kadib micnihiisa iyo shaqadiisa Af-Soomaali.
4. Sharax dulucda cilmiyeed ee sawirkaas laga baranayo iyo sida uu ula xiriiro casharka.
5. Ku dhammee hal talo oo imtixaan: waxa ardaygu sawirka ka xafido ama ku calaamadiyo.
(Haddii bogaggaas aysan lahayn sawir ama jaantus cad, si cad u sheeg una bixi sharaxaad muuqaal-maskaxeed ah oo uu ardaygu wax ku sawiran karo).
''';

      case TutorMode.explain:
        return '''
$pdfNotice
$context

ARAGTIDA SHARAXAADDA FUDUD:
Fadlan qaybta "$scopeName" u sharax ardayga si aad u fudud oo qof kasta fahami karo.
- Adeegso luqad fudud iyo masaal ama sarbeeb nolosha maalinlaha ah laga fahmi karo.
- Haddii ay jiraan ereyo cilmiyeed adag, ku micnee ereyo Soomaali ah oo fudud.
''';

      case TutorMode.quiz:
        return '''
$pdfNotice
$context

ARAGTIDA QUIZ-KA:
Fadlan samee 3 ilaa 4 su'aalood oo is-tijaabin ah oo ku saabsan "$scopeName" (haddii ay jiraan sawirro ama jaantusyo, ku dar ugu yaraan 1 su'aal oo jaantus ku saabsan):
- Su'aal kasta ha lahaato 4 xulasho oo kala duwan (A, B, C, D).
- Dhamaadka qaybta quiz-ka ku qor jawaabaha saxda ah iyo sababta ay sax u yihiin si ardaygu isu saxo una barto qaladkiisa.
''';

      case TutorMode.summary:
        return '''
$pdfNotice
$context

ARAGTIDA DULOCDA (SUMMARY):
$learningFormat
Fadlan soo koob dhammaan qodobada ugu muhiimsan ee qaybta "$scopeName".
- Ku soo bandhig 4-5 qodob oo xusuusashada iyo imtixaanka u fiican.
- Xus erey-bixinnada muhiimka ah (Key Terms) iyo macnahooda.
''';

      case TutorMode.freeChat:
        return '''
$pdfNotice
$context

Su'aasha Ardayga: $question

Tilmaamaha Macallinka Leyli AI:
- U sharax ardayga su'aashiisa si faahfaahsan, qoto-dheer oo aad u cad.
- Si toos ah u tixraac bogagga PDF-ka la jaray ee qaybta "$scopeName": qoraalka, sawirrada, jaantusyada (diagrams), shaxannada, qaacidooyinka iyo tusaalooyinka ku jira.
- Haddii ardaygu weydiiyo su'aal gaar ah oo ku saabsan qaybta hadda, uga jawaab su'aasha si toos ah; ha ku celin casharka oo dhan. Adeegso casharkii hore ee session-kan kaliya si aad ugu xirto jawaabta.
$learningFormat
''';
    }
  }

  String _scopeRule(LearningScopeType? scopeType) {
    switch (scopeType) {
      case LearningScopeType.book:
        return 'Buugga oo dhan ayaa la doortay: bixi guudmar kooban oo buugga ah, sheeg chapters-ka ku jira, kadibna weydii chapter-ka ama lesson-ka ardaygu rabo. Ha bilaabin sharaxaad buug dhan ah.';
      case LearningScopeType.chapter:
        return 'Chapter ayaa la doortay: bixi guudmar chapter-ka, dulucdiisa, iyo lessons/sections-ka ku jira, kadibna weydii qaybta uu ardaygu rabo. Ha daadin sharaxaad chapter-ka oo dhan hal jawaab.';
      case LearningScopeType.lesson:
      case LearningScopeType.section:
        return 'Lesson ama section ayaa la doortay: jawaabta u habeey hordhac, English-ka muhiimka ah, sharaxaad Soomaali/English isku lammaan, tusaale ama jaantus haddii uu jiro, kadibna fahamsiin kooban oo Soomaali ah.';
      case null:
        return 'Haddii scope la doortay uu jiro, ku koob jawaabta scope-kaas oo ha isku darin casharro kale.';
    }
  }

  String _learningFormat(
    LearningScopeType? scopeType,
    String scopeName, {
    int? learningPartNumber,
    int? learningPartCount,
    bool isLessonCompletion = false,
  }) {
    switch (scopeType) {
      case LearningScopeType.book:
        return '''
QAABKA JAWAABTA BUUGGA:
1. ### Guudmar buugga
2. Chapters-ka iyo mawduuca mid kasta oo kooban
3. Ku soo xir su'aal cad: “Chapter ama lesson kee rabtaa inaan ku bilowno?”
''';
      case LearningScopeType.chapter:
        return '''
QAABKA JAWAABTA CHAPTER-KA:
1. ### Guudmar: $scopeName
2. Dulucda iyo erayada muhiimka ah
3. Lessons/sections-ka ku jira
4. Ku soo xir su'aal cad oo ardayga ka codsanaysa inuu doorto qayb uu baranayo
''';
      case LearningScopeType.lesson:
      case LearningScopeType.section:
        final partInstruction =
            learningPartNumber != null &&
                learningPartCount != null &&
                learningPartCount > 1
            ? 'Waxaad hadda sharxaysaa Qaybta $learningPartNumber/$learningPartCount oo keliya. Ha uga gudbin qayb kale; ardaygu isagaa dalbanaya qaybta xigta.'
            : '';
        final completionInstruction = isLessonCompletion
            ? '''
Waa qaybta ugu dambaysa. Ka dib sharaxaadda ku dar ### Casharka waa dhammaystiran yahay, ### Erayada muhiimka ah (English → Soomaali), iyo ### Is-tijaabi oo leh 3 su'aalood oo gaagaaban. Ha soo bandhigin batoon ama ha sheegin qayb xigta.
'''
            : '';
        return '''
QAABKA CASHARKA LABA-LUQADOODKA AH:
1. ### Hordhac kooban — waxa ardaygu baranayo.
2. ### English from the lesson — dooro 1 ilaa 3 weedhood ama fikrado English ah oo gaagaaban oo muhiim ah; ha koobiyeeyn bogag dheer.
3. ### Sharaxaadda macallinka — fikrad kasta kadib ku bixi sharaxaad Af-Soomaali ah, adigoo ilaalinaya erayga English-ka ee buugga.
4. ### Tusaale / Formula / Diagram — kaliya haddii ay ku jirto qaybta la doortay.
5. ### Soo koobid Af-Soomaali ah iyo hal su'aal oo faham hubin ah.
$partInstruction
$completionInstruction
''';
      case null:
        return '''
Haddii ardaygu doortay lesson ama section, u adeegso qaab laba-luqadood ah: English-ka muhiimka ah kadib sharaxaad Soomaali ah.
''';
    }
  }

  String _buildScopeNavigation(
    PreparedBook book,
    LearningScopeType? scopeType, {
    String? focusChapter,
    String? focusLesson,
  }) {
    if (scopeType == LearningScopeType.book || scopeType == null) {
      final chapters = book.chapters
          .map((chapter) => '- ${chapter.title}')
          .join('\n');
      return '\nAvailable chapters:\n${chapters.isEmpty ? '- Lama diyaarin' : chapters}';
    }

    if (scopeType == LearningScopeType.chapter) {
      final chapter = book.chapters.where((item) => item.title == focusChapter);
      final lessons = chapter.isEmpty
          ? const <PreparedLesson>[]
          : chapter.first.lessons;
      return '\nLessons in this chapter:\n${lessons.isEmpty ? '- Lama diyaarin' : lessons.map((lesson) => '- ${lesson.title}').join('\n')}';
    }

    if (scopeType == LearningScopeType.lesson) {
      PreparedLesson? lesson;
      for (final chapter in book.chapters) {
        for (final item in chapter.lessons) {
          if (item.title == focusLesson) {
            lesson = item;
            break;
          }
        }
      }
      final sections = lesson?.sections ?? const <PreparedSection>[];
      return '\nSections in this lesson:\n${sections.isEmpty ? '- Lama diyaarin' : sections.map((section) => '- ${section.title}').join('\n')}';
    }

    return '';
  }

  Future<String> _callGeminiApi({
    required String model,
    required String apiKey,
    required String systemPrompt,
    required String userPrompt,
    Uint8List? pdfBytes,
    CancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled == true) {
      throw const GeminiCancelledException();
    }
    final client = _customClient ?? http.Client();
    final shouldClose = _customClient == null;
    cancellationToken?.attachClient(client);

    try {
      final parts = <Map<String, dynamic>>[];

      // If sliced PDF is available, attach it as application/pdf inline data
      if (pdfBytes != null && pdfBytes.isNotEmpty) {
        parts.add({
          'inline_data': {
            'mime_type': 'application/pdf',
            'data': base64Encode(pdfBytes),
          },
        });
      }

      parts.add({'text': userPrompt});

      final response = await client
          .post(
            Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
            ),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': systemPrompt},
                ],
              },
              'contents': [
                {'role': 'user', 'parts': parts},
              ],
            }),
          )
          .timeout(const Duration(minutes: 10));

      if (cancellationToken?.isCancelled == true) {
        throw const GeminiCancelledException();
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GeminiBookChatException(
          'API Status ${response.statusCode}: ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>?;
      final firstCandidate = candidates?.isNotEmpty == true
          ? candidates!.first as Map<String, dynamic>?
          : null;
      final content = firstCandidate?['content'] as Map<String, dynamic>?;
      final resParts = content?['parts'] as List<dynamic>?;

      final buffer = StringBuffer();
      if (resParts != null) {
        for (final part in resParts) {
          if (part is Map<String, dynamic>) {
            if (part['thought'] == true) continue;
            final partText = part['text'] as String?;
            if (partText != null && partText.isNotEmpty) {
              buffer.write(partText);
            }
          }
        }
      }
      final text = buffer.toString().trim();
      if (text.isEmpty) {
        throw const GeminiBookChatException('Jawaab madhan ayaa soo noqotay.');
      }
      return text;
    } finally {
      if (shouldClose) {
        client.close();
      }
    }
  }

  List<int> _findRelevantPages(
    PreparedBook book,
    BookKnowledge knowledge,
    String question, {
    String? focusChapter,
    String? focusLesson,
    String? focusSection,
  }) {
    final allowed = <int>{};
    for (final chapter in book.chapters) {
      final chapterMatch =
          focusChapter == null || chapter.title == focusChapter;
      for (final lesson in chapter.lessons) {
        final lessonMatch = focusLesson == null || lesson.title == focusLesson;
        for (final section in lesson.sections) {
          final sectionMatch =
              focusSection == null || section.title == focusSection;
          if (chapterMatch && lessonMatch && sectionMatch) {
            for (var p = section.startPage; p <= section.endPage; p++) {
              allowed.add(p);
            }
          }
        }
        if (focusSection == null && chapterMatch && lessonMatch) {
          for (var p = lesson.startPage; p <= lesson.endPage; p++) {
            allowed.add(p);
          }
        }
      }
      if (focusLesson == null && focusSection == null && chapterMatch) {
        for (var p = chapter.startPage; p <= chapter.endPage; p++) {
          allowed.add(p);
        }
      }
    }

    // If no specific scope filter was matched, allow all pages
    final targetPages = allowed.isNotEmpty
        ? allowed
        : knowledge.pages.keys.toSet();

    final terms = question
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.length > 2)
        .toSet();

    if (terms.isEmpty) {
      final sorted = targetPages.toList()..sort();
      return sorted.take(6).toList();
    }

    final scored = targetPages.map((pageNumber) {
      final text = knowledge.pages[pageNumber] ?? '';
      final words = text.toLowerCase().split(RegExp(r'[^a-z0-9]+')).toSet();
      final score = terms.where(words.contains).length;
      return (page: pageNumber, score: score);
    }).toList()..sort((a, b) => b.score.compareTo(a.score));

    final matched = scored
        .where((s) => s.score > 0)
        .map((s) => s.page)
        .toList();
    if (matched.isNotEmpty) {
      return matched.take(6).toList();
    }

    final sorted = targetPages.toList()..sort();
    return sorted.take(6).toList();
  }

  /// High-value local tutor generator to ensure offline & demo reliability
  String _generateLocalTutorResponse({
    required PreparedBook book,
    required BookKnowledge knowledge,
    required List<int> pages,
    required String question,
    required TutorMode mode,
    required String? focusChapter,
    required String? focusLesson,
    required String? focusSection,
    LearningScopeType? learningScopeType,
    String? apiErrorMessage,
  }) {
    final scopeTitle =
        focusSection ?? focusLesson ?? focusChapter ?? book.title;
    final combinedText = pages
        .map((p) => knowledge.pages[p] ?? '')
        .where((t) => t.trim().isNotEmpty)
        .join('\n\n');

    final cleanExcerpt = combinedText.trim().isNotEmpty
        ? combinedText
        : _synthesizeFallbackKnowledge(
            book: book,
            scopeTitle: scopeTitle,
            question: question,
          );

    final errorNotice = apiErrorMessage != null
        ? '> ⚠️ *Fiiro gaar ah: ${_friendlyApiError(apiErrorMessage)} Jawaabtan waxaa kuu diyaariyay Leyli AI.*\n\n'
        : '';

    if (learningScopeType == LearningScopeType.book) {
      final chapters = book.chapters.isEmpty
          ? '- Chapters-ka buuggan weli lama diyaarin.'
          : book.chapters.map((chapter) => '- ${chapter.title}').join('\n');
      return '''
$errorNotice### 📚 Guudmar: ${book.title}

Buuggani waa **${book.title}** oo loogu talagalay **${book.category}**.

### Chapters-ka buugga
$chapters

Chapter ama lesson kee rabtaa inaan ku bilowno?
''';
    }

    if (learningScopeType == LearningScopeType.chapter) {
      final chapter = book.chapters.where((item) => item.title == focusChapter);
      final lessons = chapter.isEmpty
          ? const <PreparedLesson>[]
          : chapter.first.lessons;
      final lessonList = lessons.isEmpty
          ? '- Lessons-ka chapter-kan weli lama diyaarin.'
          : lessons.map((lesson) => '- ${lesson.title}').join('\n');
      return '''
$errorNotice### 📖 Guudmar: $scopeTitle

Chapter-kan wuxuu ka tirsan yahay **${book.title}** (${book.category}). Hoos waxaa ku qoran lessons-ka uu ka kooban yahay:

$lessonList

Lesson ama section kee rabtaa inaan kuu sharaxo?
''';
    }

    switch (mode) {
      case TutorMode.teach:
        return '''
$errorNotice### 📖 Casharka: $scopeTitle
Ku soo dhawoow barashada **$scopeTitle** ee buugga *${book.title}* (${book.category})!

#### 📌 Qodobada Muhiimka ah & Sharaxaadda:
$cleanExcerpt

#### 💡 Tusaale & Faham Dheeraad ah:
Fikradahan waxaa loogu talagalay inay ardayda fasalka **${book.category}** ka caawiyaan fahamka buuxa ee manhajka iyo sida casharku ugu xiran yahay nolosheenna dhabta ah.

Haddii aad qabto su'aal gaar ah ama faahfaahin dheeraad ah oo ku saabsan qaybtaan, fadlan qor si aan si qoto dheer kuugu sharaxo!
''';

      case TutorMode.visuals:
        return '''
$errorNotice### 🖼️ Sharaxaadda Sawirrada & Jaantusyada: $scopeTitle

Halkan waxaa ku yaal falanqaynta jaantusyada, shaxannada, iyo xogta sawirran ee qaybta **$scopeTitle**:

#### 🔍 Jaantusyada & Qaybaha Muhiimka ah:
$cleanExcerpt

#### 💡 Sida loo Fahmo Muuqaalka & Jaantuska:
- Jaantusyada casharkan waxay muujinayaan sida qaybaha kala duwan isugu xiran yihiin iyo habka wareegga/dhaqdhaqaaqa.
- Xusuuso calaamadaha, halbeegyada, iyo cinwaannada ku dul qoran si aad imtixaanka ugu faa'iidaysato.

*Haddii aad qabto su'aal gaar ah oo ku saabsan sawir ama jaantus gaar ah, fadlan hoos ku qor!*
''';

      case TutorMode.explain:
        return '''
$errorNotice### 💡 Sharaxaadda Fudud ee: $scopeTitle

Halkan waxaa ku yaal nuxurka ugu muhiimsan ee loo fududeeyay ardayga:

$cleanExcerpt

**Tusaale Sahal ah**: Markaad eegto mowduucan, u arag sidii dhisidda tallaabooyinka aasaasiga ah ee cilmigan. Qodob kasta wuxuu taageerayaa kan ku xiga!
''';

      case TutorMode.quiz:
        return '''
$errorNotice### 📝 Is-tijaabi (Quiz): $scopeTitle

**Su'aasha 1-aad:**
Maxay tahay dulucda ugu weyn ee looga hadlay $scopeTitle?
- A) Qeexidda guud iyo qaybaha muhiimka ah
- B) Taariikhda cilmiga oo keliya
- C) Xisaabinta caalamiga ah
- D) Ma jirto mid sax ah

**Su'aasha 2-aad:**
Qodobkee ayaa ugu muhiimsan nuxurka qoraalka kor ku xusan?
- A) Fahamka iyo adeegsiga saxda ah
- B) Kaliya xafididda ereyada
- C) Iska iloobidda xaqiiqooyinka
- D) Dhammaan waa sax

---
✅ **Jawaabaha Saxda ah:**
1. **A** - Sababtoo ah qoraalku wuxuu si toos ah u sharaxayaa qodobada aasaasiga ah.
2. **A** - Fahamka dhabta ah ayaa saldhig u ah barashada maadadan.
''';

      case TutorMode.summary:
        return '''
$errorNotice### 📌 Dulucda & Qodobada Muhiimka ah ($scopeTitle)

- **Maadada:** ${book.title} (${book.category})
- **Qaybta Diiradda:** $scopeTitle
- **Bogagga la xiriira:** ${pages.isEmpty ? 'Dhammaan' : pages.join(', ')}

**Qodobada Ugu Waaweyn:**
$cleanExcerpt
''';

      case TutorMode.freeChat:
        return '''
$errorNotice### 📚 Sharaxaadda Casharka: $scopeTitle

Waad ku mahadsan tahay su'aashaada ku saabsan **$scopeTitle** ee maaddada *${book.title} (${book.category})*.

Su'aashaada: *"$question"*

---
#### 🇬🇧 English from the lesson:
$cleanExcerpt

#### 🇸🇴 Sharaxaadda Macallinka:
Qoraalka kore wuxuu ka hadlayaa fikradaha muhiimka ah ee **$scopeTitle**. Akhri erayada English-ka ah, kadibna ku xiriiri qeexitaannada, qaacidooyinka, iyo tusaalooyinka casharka.

#### 💡 Hubin Faham:
Maxay tahay fikradda ugu muhiimsan ee aad ka fahamtay qaybtaan?
''';
    }
  }

  String _friendlyApiError(String error) {
    if (error.contains('503')) return 'Gemini hadda wuu mashquulsan yahay.';
    if (error.contains('429')) {
      return 'Codsiyo badan ayaa jira; fadlan mar kale isku day wax yar kadib.';
    }
    if (error.contains('401') || error.contains('403')) {
      return 'Furaha Gemini lama aqbalin.';
    }
    return 'Xiriirka Google Gemini ma suuroobin xilligan.';
  }

  String _synthesizeFallbackKnowledge({
    required PreparedBook book,
    required String scopeTitle,
    required String question,
  }) {
    final lowerScope = scopeTitle.toLowerCase();
    final isPhysics =
        book.title.toLowerCase().contains('phy') ||
        lowerScope.contains('motion') ||
        lowerScope.contains('frequency') ||
        lowerScope.contains('period') ||
        lowerScope.contains('wave');

    if (isPhysics) {
      return '''
1. **Qeexidda Guud:**
   - **Periodic Motion (Dhaqdhaqaaqa Xilliga ah)**: Waa dhaqdhaqaaq kasta oo dib isugu soo laabta muddooyin waqti oo is le'eg ka dib (sida lulashada pendulum-ka, wareegga meerayaasha, ama gariirka xadhigga gitaarka).
   - **Period (\\\$T\\\$ / Xilli)**: Waa waqtiga ay ku qaadato hal wareeg ama hal lulasho oo buuxda (Complete Cycle). Waxaa lagu cabbiraa ilbiriqsi (s).
   - **Frequency (\\\$f\\\$ / Jeer-jeer)**: Waa tirada wareegyada ama lulashada ee dhacda hal ilbiriqsi gudaheed. Waxaa lagu cabbiraa Hertz (Hz ama 1/s).

2. **Xiriirka Xisaabeed & Qaacidooyinka:**
   - f = 1 / T  *(Frequency-gu waa rogganka Period-ka)*
   - T = 1 / f  *(Period-ku waa rogganka Frequency-ga)*
   - Haddii xilligu (T) kordho, jeer-jeerku (f) wuu yaraadaa, waana xiriir rogganta ah (Inverse Relationship).

3. **Tusaale Faham ah:**
   - Haddii lulashadu sameyso 20 wareeg 4 ilbiriqsi gudaheed:
     - Period (T) = 4 / 20 = 0.2 ilbiriqsi.
     - Frequency (f) = 1 / 0.2 = 5 Hz.
''';
    }

    return '''
Mowduuca **$scopeTitle** ee maaddada *${book.title} (${book.category})* wuxuu xambaarsan yahay fikradaha saldhigga u ah cutubkan:
- **Dulucda Koowaad:** Fahamka qeexitaannada, erey-bixinnada, iyo sharciyada la xiriira $scopeTitle.
- **Dulucda Labaad:** Sida casharkani ugu xiran yahay qaybaha kale ee manhajka fasalka ${book.category}.
- **Qodobada Xusuusta:** Dib-u-eegista qaababka, tusaalooyinka, iyo su'aalaha caadiga ah ee imtixaanka lagu weydiin karo.
''';
  }
}

class GeminiBookChatException implements Exception {
  const GeminiBookChatException(this.message);
  final String message;

  @override
  String toString() => message;
}

class GeminiCancelledException implements Exception {
  const GeminiCancelledException([this.message = 'Shaqada waa la joojiyay']);
  final String message;

  @override
  String toString() => message;
}

class CancellationToken {
  bool _isCancelled = false;
  http.Client? _activeClient;

  bool get isCancelled => _isCancelled;

  void attachClient(http.Client client) {
    _activeClient = client;
  }

  void cancel() {
    _isCancelled = true;
    try {
      _activeClient?.close();
    } catch (_) {}
  }
}
