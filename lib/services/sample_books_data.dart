import '../models/book_knowledge.dart';
import '../models/prepared_book.dart';

class SampleBooksData {
  static List<PreparedBook> get sampleBooks => [
    _form1Biology,
    _form2Chemistry,
    _form3Physics,
    _form4History,
  ];

  static Map<String, BookKnowledge> get sampleKnowledge => {
    _form1Biology.id: _form1Knowledge,
    _form2Chemistry.id: _form2Knowledge,
    _form3Physics.id: _form3Knowledge,
    _form4History.id: _form4Knowledge,
  };

  // -------------------------------------------------------------
  // FORM 1: Sayniska & Nolosha (Biology & Life Science)
  // -------------------------------------------------------------
  static final _form1Biology = PreparedBook(
    id: 'sample_form1_bio',
    title: 'Sayniska Guud & Nolosha - Fasalka 1aad',
    originalFileName: 'sayniska_fasalka_1.pdf',
    pageCount: 30,
    category: 'Form 1',
    status: PreparedBookStatus.published,
    createdAt: DateTime(2025, 1, 10),
    updatedAt: DateTime(2025, 2, 1),
    chapters: const [
      PreparedChapter(
        id: 'c1',
        title: 'Cutubka 1: Unugyada & Nolosha',
        startPage: 1,
        endPage: 10,
        lessons: [
          PreparedLesson(
            id: 'c1_l1',
            title: 'Casharka 1: Waa Maxay Unug?',
            startPage: 1,
            endPage: 5,
            sections: [
              PreparedSection(
                id: 'c1_l1_s1',
                title: '1.1 Qeexidda Unugga & Taariikhdiisa',
                startPage: 1,
                endPage: 2,
              ),
              PreparedSection(
                id: 'c1_l1_s2',
                title: '1.2 Qaybaha Muhiimka ah ee Unugga',
                startPage: 3,
                endPage: 5,
              ),
            ],
          ),
          PreparedLesson(
            id: 'c1_l2',
            title: 'Casharka 2: Farqiga u dhexeeya Unugyada Dhirta & Xayawaanka',
            startPage: 6,
            endPage: 10,
            sections: [
              PreparedSection(
                id: 'c1_l2_s1',
                title: '1.3 Qaab-dhismeedka Unugga Dhirta (Derbiga Unugga & Chloroplast)',
                startPage: 6,
                endPage: 8,
              ),
              PreparedSection(
                id: 'c1_l2_s2',
                title: '1.4 Isbarbardhigga Guud & Shaqooyinka',
                startPage: 9,
                endPage: 10,
              ),
            ],
          ),
        ],
      ),
      PreparedChapter(
        id: 'c2',
        title: 'Cutubka 2: Habka Dheefshiidka Dadka',
        startPage: 11,
        endPage: 20,
        lessons: [
          PreparedLesson(
            id: 'c2_l1',
            title: 'Casharka 1: Xubnaha Hab-dhiska Dheefshiidka',
            startPage: 11,
            endPage: 15,
            sections: [
              PreparedSection(
                id: 'c2_l1_s1',
                title: '2.1 Afka, Ilkaha iyo Candhuufta',
                startPage: 11,
                endPage: 13,
              ),
              PreparedSection(
                id: 'c2_l1_s2',
                title: '2.2 Hunguriga iyo Caloosha',
                startPage: 14,
                endPage: 15,
              ),
            ],
          ),
          PreparedLesson(
            id: 'c2_l2',
            title: 'Casharka 2: Nuugista Nafaqada iyo Mindhicirrada',
            startPage: 16,
            endPage: 20,
            sections: [
              PreparedSection(
                id: 'c2_l2_s1',
                title: '2.3 Mindhicirka Yar & Shaqada Beerka',
                startPage: 16,
                endPage: 18,
              ),
              PreparedSection(
                id: 'c2_l2_s2',
                title: '2.4 Mindhicirka Weyn & Qashin-saarka',
                startPage: 19,
                endPage: 20,
              ),
            ],
          ),
        ],
      ),
    ],
  );

  static final _form1Knowledge = BookKnowledge(
    bookId: 'sample_form1_bio',
    pages: const {
      1: 'CUTUBKA 1: UNUGYADA & NOLOSHA\nQeexidda Unugga:\nUnuggu waa unugga aasaasiga ah ee dhismaha iyo shaqada dhammaan noolaha (The cell is the basic structural and functional unit of all living organisms). Dhammaan nooluhu waxay ka kooban yihiin hal unug (unicellular) sida bakteeriyada ama balaayiin unug (multicellular) sida dhirta iyo xayawaanka.',
      2: 'Taariikhda Baaritaanka Unugga:\nSaynisyahan Robert Hooke ayaa sanadkii 1665 markii ugu horeysay arkay unugyo meyd ah isagoo isticmaalaya mikroskoob fudud. Kadib Anton van Leeuwenhoek ayaa arkay unugyo nool. Aragtida Unugga (Cell Theory) waxay sheegaysaa: 1. Noolaha oo dhan waxay ka samaysan yihiin unugyo. 2. Unuggu waa qaybta ugu yar ee nolosha. 3. Dhammaan unugyadu waxay ka yimaadaan unugyo hore u jiray.',
      3: 'QAYBAHA MUHIIMKA AH EE UNUGGA:\n1. Xuubka Unugga (Cell Membrane): Wuxuu ilaaliyaa unugga wuxuuna xakameeyaa waxyaabaha soo galaya ama ka baxaya (semi-permeable barrier).\n2. Nukliyeeska (Nucleus): Waa xarunta taliska unugga. Waxay ka kooban tahay hiddo-sidaha (DNA) kaas oo maamula dhammaan ficillada unugga.',
      4: '3. Cytoplasm: Waa dareere jel ah oo buuxiya gudaha unugga, halkaas oo ay ku dhex jiraan xubnaha yaryar (organelles).\n4. Mitochondria: Waxaa loogu yeeraa "warshadda tamarta unugga" (powerhouse of the cell). Waxay soo saartaa tamarta noocuu ATP iyadoo loo marayo habka neefsashada unugga.',
      5: '5. Ribosomes: Waxay soo saaraan borotiinnada muhiimka u ah koritaanka iyo dayactirka unugga.\n6. Endoplasmic Reticulum (ER) & Golgi Apparatus: Waxay qaabilsan yihiin qaadista, habaynta iyo dhoofinta maaddooyinka unugga gudihiisa ama dibaddiisa.',
      6: 'FARQIGA U DHEXEEYA UNUGYADA DHIRTA & XAYAWAANKA:\nUnugyada dhirta iyo xayawaanku waxay wadaagaan xubno badan, laakiin unugga dhirtu wuxuu leeyahay saddex shay oo gaar ah:\n1. Derbiga Unugga (Cell Wall): Wuxuu ka samaysan yahay cellulose, wuxuuna siiyaa dhirta adkeysi iyo qaab go’an.\n2. Chloroplasts: Waxay ka kooban yihiin chlorophyll oo ah maaddada cagaaran ee dhirtu u isticmaasho habka photosynthesis (cunto samaynta).',
      7: '3. Vacuole Weyn oo Bartamaha ku yaal (Large Central Vacuole): Wuxuu kaydiyaa biyaha iyo maaddooyinka nafaqada, wuxuuna ilaaliyaa cadaadiska unugga (turgor pressure). Unugyada xayawaanku waxay leeyihiin vacuoles yaryar oo ku meel-gaar ah.',
      8: 'Unugga Xayawaanka:\nUnugga xayawaanku ma laha derbi unug mana laha chloroplast. Wuxuu leeyahay qaab dabacsan oo wareegsan. Waxaa kale oo uu leeyahay Centrioles oo ka qayb qaata kala-qeybsanaanta unugga.',
      9: 'ISBARBARDHIGGA SHAQOOYINKA:\n- Dhirtu waa noole iskeed isu quudiya (Autotrophs) maxaa yeelay chloroplast ayaa u sahlaysa inay iftiinka qorraxda u beddesho tamar kiimikaad (glucose).\n- Xayawaanku waa heterotrophs oo waxay ku tiirsan yihiin noolaha kale si ay tamar u helaan.',
      10: 'Su\'aalaha Cutubka 1aad:\n1. Waa maxay shaqada mitochondria?\n2. Sheeg laba farqi oo u dhexeeya unugga dhirta iyo unugga xayawaanka?\n3. Waa maxay doorka xuubka unugga (cell membrane)?',
      11: 'CUTUBKA 2: HABKA DHEEFSHIIDKA DADKA\nDheefshiidku waa habka cuntada adag loogu jajabiyo unugyo yaryar oo milmi kara si jirku u nuugo uguna faa’iidaysto tamar ahaan.',
      12: 'AFKA IYO ILKAHA:\n1. Dheefshiidka farsamo (Mechanical digestion): Ilkaha ayaa cuntada ku calaliya oo ku jajabiya qeybo yaryar.\n2. Dheefshiidka kiimiko (Chemical digestion): Candhuufta waxaa ku jira ensaymka Amylase oo bilaaba burburinta carbohydrates-ka (caroorka).',
      13: 'Carrabka: Wuxuu cuntada ku qasaa candhuufta wuxuuna u qaabeeyaa kubad yar (bolus) si sahlan loogu liqo hunguriga.',
      14: 'HUNGURIGA IYO CALOOSHA:\nHunguriga (Esophagus) wuxuu cuntada u gudbiyaa caloosha isagoo isticmaalaya murqaha oo isku urura (Peristalsis).',
      15: 'Caloosha (Stomach):\nCaloosha waxaa ku jira aashitada Hydrochloric acid (HCl) iyo ensaymka Pepsin. HCl waxay dishaa jeermiska cuntada soo raaca waxayna kicisaa pepsin si uu u dheefshiido borotiinka.',
      16: 'MINDHICIRKA YAR (Small Intestine):\nWaa xubinta ugu dheer hab-dhiska dheefshiidka (qiyaastii 6 mitir). Halkan ayaa lagu dhammeystiraa dheefshiidka intiisa badan waxaana ka dhacda nuugista nafaqada (absorption).',
      17: 'Beerka & Xameetida (Liver & Gallbladder):\nBeerku wuxuu soo saaraa maaddada Bile (xameeti) oo lagu kaydiyo kiishka xameetida. Bile waxay miltaa dufanka (emulsification of fats) si ensaymyada lipase ay si fudud ugu shaqeeyaan.',
      18: 'Villi (Faraha Nuugista):\nGudaha mindhicirka yar waxaa ku yaal fariro yaryar oo loogu yeero Villi. Waxay ballaariyaan bedka nuugista si nafaqada loogu gudbiyo dhiigga.',
      19: 'MINDHICIRKA WEYN (Large Intestine):\nMindhicirka weyn ma dheefshiido cuntada, laakiin wuxuu nuugaa biyaha iyo cusbada dheeraadka ah ee ku jirta qashinka cuntada.',
      20: 'Qashin-saarka (Excretion):\nQashinka adag (saxarada) waxaa lagu kaydiyaa malawadka (rectum) waxaana laga saaraa futada (anus).',
    },
  );

  // -------------------------------------------------------------
  // FORM 2: Kimistariga Guud (Chemistry)
  // -------------------------------------------------------------
  static final _form2Chemistry = PreparedBook(
    id: 'sample_form2_chem',
    title: 'Kimistariga Guud - Fasalka 2aad',
    originalFileName: 'kimistariga_fasalka_2.pdf',
    pageCount: 25,
    category: 'Form 2',
    status: PreparedBookStatus.published,
    createdAt: DateTime(2025, 1, 15),
    updatedAt: DateTime(2025, 2, 5),
    chapters: const [
      PreparedChapter(
        id: 'chem_c1',
        title: 'Cutubka 1: Qaab-dhismeedka Atom-ka & Jadwalka Curiyayaasha',
        startPage: 1,
        endPage: 12,
        lessons: [
          PreparedLesson(
            id: 'chem_c1_l1',
            title: 'Casharka 1: Qaybaha Atom-ka (Protons, Neutrons, Electrons)',
            startPage: 1,
            endPage: 6,
            sections: [
              PreparedSection(
                id: 'chem_c1_l1_s1',
                title: '1.1 Nucleus-ka iyo Xisaabinta Tirada Atom-ka',
                startPage: 1,
                endPage: 3,
              ),
              PreparedSection(
                id: 'chem_c1_l1_s2',
                title: '1.2 Qaybinta Elektaroonnada (Electronic Configuration)',
                startPage: 4,
                endPage: 6,
              ),
            ],
          ),
          PreparedLesson(
            id: 'chem_c1_l2',
            title: 'Casharka 2: Jadwalka Curiyayaasha (Periodic Table)',
            startPage: 7,
            endPage: 12,
            sections: [
              PreparedSection(
                id: 'chem_c1_l2_s1',
                title: '1.3 Kooxaha (Groups) iyo Kulamada (Periods)',
                startPage: 7,
                endPage: 9,
              ),
              PreparedSection(
                id: 'chem_c1_l2_s2',
                title: '1.4 Biraha iyo Ma-biraha (Metals and Non-metals)',
                startPage: 10,
                endPage: 12,
              ),
            ],
          ),
        ],
      ),
    ],
  );

  static final _form2Knowledge = BookKnowledge(
    bookId: 'sample_form2_chem',
    pages: const {
      1: 'CUTUBKA 1: QAAB-DHISMEEDKA ATOM-KA\nAtom-ku waa qaybta ugu yar ee curiye kiimikaad oo haysata astaamihiisa. Atom kasta wuxuu ka kooban yahay laba qaybood: Nucleus oo dhexda ku yaal iyo Daruur Elektaroonno ah oo ku wareegta.',
      2: 'QAYBAHA HOOSE EE ATOM-KA (Subatomic Particles):\n1. Protons: Waxay ku jiraan nucleus-ka, waxayna leeyihiin koronto togan (+1). Mass-koodu waa 1 amu.\n2. Neutrons: Waxay ku jiraan nucleus-ka, mana laha wax koronto ah (dhexdhexaad, 0). Mass-koodu waa 1 amu.',
      3: '3. Electrons: Waxay ku wareegaan nucleus-ka godadka (shells), waxayna leeyihiin koronto taban (-1). Mass-koodu aad buu u yar yahay (qiyaastii 1/1840 amu).\nTirada Atom-ka (Atomic Number, Z) = Tirada Protons-ka.\nTirada Mass-ka (Mass Number, A) = Protons + Neutrons.',
      4: 'QAYBINTA ELEKTAROONNADA (Electronic Configuration):\nElektaroonnadu waxay buuxiyaan lakabyada tamarta (energy shells) iyadoo la raacayo sharciga 2n^2:\n- Lakabka 1aad (K): ugu badnaan 2 electrons.\n- Lakabka 2aad (L): ugu badnaan 8 electrons.\n- Lakabka 3aad (M): ugu badnaan 8 electrons (curiyeyaasha ugu horreeya 20).',
      7: 'JADWALKA CURIYAYAASHA (Periodic Table):\nCuriyeyaasha waxaa loo habeeyay iyadoo la raacayo kororka tirada atom-kooda (atomic number).\n- Kooxaha (Groups): Waa tiirarka toosan (vertical columns) 1 ilaa 8. Curiyeyaasha isku kooxda ah waxay leeyihiin isla tirada electrons-ka lakabka sare (valence electrons) iyo astaamo kiimikaad oo isku mid ah.',
      8: '- Kulamada (Periods): Waa safafka jiifa (horizontal rows). Tirada kulanka waxay muujisaa tirada lakabyada tamarta ee curiyuhu leeyahay.',
      10: 'BIRAHA IYO MA-BIRAHA:\n- Biraha (Metals): Waxay ku yaallaan bidixda jadwalka. Waxay dhalaalaan, qaadaan kuleylka iyo korontada, waxayna bixiyaan electrons si ay u sameeyaan ions togan (cations).\n- Ma-biraha (Non-metals): Waxay ku yaallaan midigta. Ma gudbiyaan korontada waxayna qaataan electrons.',
    },
  );

  // -------------------------------------------------------------
  // FORM 3: Fiisigiska & Tamarta (Physics)
  // -------------------------------------------------------------
  static final _form3Physics = PreparedBook(
    id: 'sample_form3_phys',
    title: 'Fiisigiska & Tamarta - Fasalka 3aad',
    originalFileName: 'fiisigiska_fasalka_3.pdf',
    pageCount: 28,
    category: 'Form 3',
    status: PreparedBookStatus.published,
    createdAt: DateTime(2025, 1, 20),
    updatedAt: DateTime(2025, 2, 8),
    chapters: const [
      PreparedChapter(
        id: 'phys_c1',
        title: 'Cutubka 1: Xeerarka Dhaqdhaqaaqa ee Newton (Newton’s Laws of Motion)',
        startPage: 1,
        endPage: 14,
        lessons: [
          PreparedLesson(
            id: 'phys_c1_l1',
            title: 'Casharka 1: Xeerka 1aad & 2aad ee Newton',
            startPage: 1,
            endPage: 7,
            sections: [
              PreparedSection(
                id: 'phys_c1_l1_s1',
                title: '1.1 Xeerka 1aad ee Newton (Inertia)',
                startPage: 1,
                endPage: 3,
              ),
              PreparedSection(
                id: 'phys_c1_l1_s2',
                title: '1.2 Xeerka 2aad ee Newton (Force & Acceleration: F = ma)',
                startPage: 4,
                endPage: 7,
              ),
            ],
          ),
          PreparedLesson(
            id: 'phys_c1_l2',
            title: 'Casharka 2: Xeerka 3aad ee Newton & Momentum',
            startPage: 8,
            endPage: 14,
            sections: [
              PreparedSection(
                id: 'phys_c1_l2_s1',
                title: '1.3 Ficil & Falcelin (Action & Reaction)',
                startPage: 8,
                endPage: 10,
              ),
              PreparedSection(
                id: 'phys_c1_l2_s2',
                title: '1.4 Ilaalinta Momentum-ka',
                startPage: 11,
                endPage: 14,
              ),
            ],
          ),
        ],
      ),
    ],
  );

  static final _form3Knowledge = BookKnowledge(
    bookId: 'sample_form3_phys',
    pages: const {
      1: 'CUTUBKA 1: XEERARKA DHAQDHAQAAQA EE NEWTON\nSir Isaac Newton wuxuu dejiyay saddex xeer oo aasaas u ah barashada fiisigiska casriga ah iyo dhaqdhaqaaqa walxaha.',
      2: 'XEERKA 1AAD EE NEWTON (Sharciga Inertia):\n"Shay kastaa wuxuu ku sii jirayaa xaaladdiisa nasashada ama dhaqdhaqaaqa toosan ee xawaaraha joogtada ah, ilaa uu ku yimaado xoog dibadeed oo qasba."\nInertia waa rabitaanka shaygu ku diido isbeddelka ku yimaada dhaqdhaqaaqiisa.',
      4: 'XEERKA 2AAD EE NEWTON (F = ma):\n"Xawaare-kordhinta (Acceleration) shay ku dhacda waxay si toos ah ugu xiran tahay xoogga saaran (Force), waxayna si leexsan ugu xiran tahay culayskiisa (Mass)."\nQaaciddada: Force (F) = mass (m) × acceleration (a).\nHalbeegga Xoogga waa Newton (N). 1 N = 1 kg·m/s².',
      8: 'XEERKA 3AAD EE NEWTON (Action and Reaction):\n"Ficil kasta wuxuu leeyahay falcelin le\'eg oo ka soo horjeedda jihadiisa." (For every action, there is an equal and opposite reaction).\nTusaale: Markaad dhulka ku tallaabsato, lugtaadu waxay dib u riixdaa dhulka, dhulkuna wuxuu kugu riixaa horay.',
      11: 'MOMENTUM (Xawaare-Culeys):\nMomentum waa cabbirka culeyska iyo xawaaraha shayga socda: p = m × v.\nSharciga Ilaalinta Momentum-ka: Isku-darka momentum-ka walxaha isku dhacaya ka hor isku dhaca wuxuu la mid yahay kan ka dambeeya haddii uusan jirin xoog dibadeed.',
    },
  );

  // -------------------------------------------------------------
  // FORM 4: Taariikhda & Xadaaradaha (History & Social Studies)
  // -------------------------------------------------------------
  static final _form4History = PreparedBook(
    id: 'sample_form4_hist',
    title: 'Taariikhda & Xadaaradaha - Fasalka 4aad',
    originalFileName: 'taariikhda_fasalka_4.pdf',
    pageCount: 32,
    category: 'Form 4',
    status: PreparedBookStatus.published,
    createdAt: DateTime(2025, 1, 25),
    updatedAt: DateTime(2025, 2, 10),
    chapters: const [
      PreparedChapter(
        id: 'hist_c1',
        title: 'Cutubka 1: Xadaaradihii Qadiimiga ahaa ee Geeska Afrika',
        startPage: 1,
        endPage: 15,
        lessons: [
          PreparedLesson(
            id: 'hist_c1_l1',
            title: 'Casharka 1: Dhulkii Udugga (Land of Punt)',
            startPage: 1,
            endPage: 7,
            sections: [
              PreparedSection(
                id: 'hist_c1_l1_s1',
                title: '1.1 Xiriirkii Ganacsi ee Masaaridii Hore & Punt',
                startPage: 1,
                endPage: 4,
              ),
              PreparedSection(
                id: 'hist_c1_l1_s2',
                title: '1.2 Alaabooyinka Ganacsiga: Luubaanta, Malmalka iyo Dahabka',
                startPage: 5,
                endPage: 7,
              ),
            ],
          ),
          PreparedLesson(
            id: 'hist_c1_l2',
            title: 'Casharka 2: Magaalo-Goboleedyadii Xeebaha Soomaaliya',
            startPage: 8,
            endPage: 15,
            sections: [
              PreparedSection(
                id: 'hist_c1_l2_s1',
                title: '1.3 Saylac, Muqdisho, Marka iyo Baraawe',
                startPage: 8,
                endPage: 11,
              ),
              PreparedSection(
                id: 'hist_c1_l2_s2',
                title: '1.4 Saldanadihii Ajuuraan iyo Cadal',
                startPage: 12,
                endPage: 15,
              ),
            ],
          ),
        ],
      ),
    ],
  );

  static final _form4Knowledge = BookKnowledge(
    bookId: 'sample_form4_hist',
    pages: const {
      1: 'CUTUBKA 1: XADAARADIHII QADIIMIGA AHAA EE GEESKA AFRIKA\nGeeska Afrika, gaar ahaan xeebaha Soomaaliya, wuxuu ahaa xarun muhiim u ah ganacsiga iyo xiriirka caalamiga ah kumanaan sano ka hor.',
      2: 'DHULKII UDUGGA (LAND OF PUNT):\nBoqortooyadii Masar ee qadiimiga ahayd waxay dalka Soomaaliya u aqoonsanaayeen "Dhulkii Ilaahyada" ama Dhulkii Udugga (Ta Netjer). Boqoraddii Hatshepsut ayaa qiyaastii sanadkii 1493 C.H. u soo dirtay koox ganacsi oo ballaaran.',
      5: 'ALAABOOYINKA GANACSIGA EE PUNT:\nPunt waxay caan ku ahayd: Luubaanta (Frankincense), Malmalka (Myrrh), Dahabka, Fool-maroodiga, iyo haragga xayawaanka duurjoogta ah. Masaaridu waxay u isticmaali jireen udugga aaska boqorrada (mummification) iyo cibaadada.',
      8: 'MAGAALO-GOBOLEEDYADII XEEBAHA SOOMAALIYA:\nMagaalooyinka qadiimiga ah sida Saylac (Zeila), Muqdisho, Marka, iyo Baraawe waxay ahaayeen marsooyin caalami ah oo ay ku kulmi jireen ganacsatada Carbeed, Faarisiyiinta, Hindiya iyo Shiinaha.',
      12: 'SALDANADDII AJUURAAN & SALDANADDII CADAL:\n- Saldanaddii Ajuuraan (Qarnigii 13aad - 17aad): Waxay ku caan baxday maamul xooggan oo biyo-gelin iyo beeraha ah wabiyada Shabeelle iyo Jubba, dhismaha qalcado waaweyn, iyo difaaca xeebaha ee gumeysigii Boortaqiiska.\n- Saldanaddii Cadal (Adal Sultanate): Waxay xarun u ahayd Saylac, waxayna hoggaamisay halgankii taariikhiga ahaa ee Imam Axmed Gurey (Axmed Ibraahim al-Qazi).',
    },
  );
}
