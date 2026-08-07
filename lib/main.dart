import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPersistedData();
  runApp(const EkodavSafetyApp());
}

class EkodavSafetyApp extends StatelessWidget {
  const EkodavSafetyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EKODAV SAFETY',
      theme: ThemeData(
        primaryColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A),
          primary: const Color(0xFF0F172A),
          secondary: const Color(0xFF0284C7),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

Future<void> openEkodavWeb() async {
  final Uri url = Uri.parse('https://www.ekodav.cz');
  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
    debugPrint('Could not launch $url');
  }
}

Future<void> openGoogleMaps(String gpsCoords) async {
  final cleanCoords = gpsCoords.replaceAll('GPS:', '').trim();
  final Uri url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$cleanCoords');
  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
    debugPrint('Could not launch $url');
  }
}

Set<String> subLocationHistory = {'Sklad', 'Parkoviště', 'Rampa', 'Dílna', 'Kanceláře', 'Výrobní hala'};

// -----------------------------------------------------------------------------
// DATOVÝ MODEL PRO LEGISLATIVNÍ PRAVIDLA
// -----------------------------------------------------------------------------
class LegislationRule {
  final String id;
  String category;
  String lawNumber;
  String paragraph;
  String citation;
  String subjectDescription;

  LegislationRule({
    required this.id,
    required this.category,
    this.lawNumber = '',
    required this.paragraph,
    this.citation = '',
    required this.subjectDescription,
  });

  String get fullTitle {
    String res = category;
    if (lawNumber.isNotEmpty) res += ' č. $lawNumber';
    if (paragraph.isNotEmpty) res += ' ($paragraph)';
    return res;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'lawNumber': lawNumber,
        'paragraph': paragraph,
        'citation': citation,
        'subjectDescription': subjectDescription,
      };

  factory LegislationRule.fromJson(Map<String, dynamic> json) => LegislationRule(
        id: json['id'] as String,
        category: json['category'] as String,
        lawNumber: json['lawNumber'] as String? ?? '',
        paragraph: json['paragraph'] as String,
        citation: json['citation'] as String? ?? '',
        subjectDescription: json['subjectDescription'] as String? ?? '',
      );
}

// -----------------------------------------------------------------------------
// AUTOMATICKÉ VYHODNOCENÍ NÁLEZU DLE LEGISLATIVY A PŘÍKLADŮ
// -----------------------------------------------------------------------------

String _normalizeForMatch(String input) {
  const withDiacritics = 'áčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ';
  const withoutDiacritics = 'acdeeinorstuuyzACDEEINORSTUUYZ';
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final idx = withDiacritics.indexOf(ch);
    buffer.write(idx >= 0 ? withoutDiacritics[idx] : ch);
  }
  return buffer.toString();
}

class LegislationMatch {
  final LegislationRule rule;
  final bool isConfident;
  LegislationMatch(this.rule, this.isConfident);
}

/// Vyhodnotí text nálezu proti příkladům ("subjectDescription") v databázi
/// legislativy a vrátí nejlépe odpovídající normu. Pokud žádný příklad
/// nesedí, spadne na první normu vybrané kategorie (dřívější chování) a
/// označí výsledek jako nejistý, ať to inspektor na revizi zkontroluje.
LegislationMatch? matchLegislation(String noteText, String category) {
  if (globalLegislationDatabase.isEmpty) return null;

  final normalizedNote = _normalizeForMatch(noteText);
  LegislationRule? bestRule;
  int bestScore = 0;

  for (final rule in globalLegislationDatabase) {
    final examples = rule.subjectDescription
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);

    int score = 0;
    for (final example in examples) {
      final normalizedExample = _normalizeForMatch(example);
      if (normalizedExample.isEmpty) continue;
      if (normalizedNote.contains(normalizedExample) ||
          normalizedExample.contains(normalizedNote)) {
        score += 3;
        continue;
      }
      final words = normalizedExample.split(RegExp(r'\s+')).where((w) => w.length > 3);
      for (final word in words) {
        if (normalizedNote.contains(word)) score += 1;
      }
    }
    if (rule.category == category) score += 1;

    if (score > bestScore) {
      bestScore = score;
      bestRule = rule;
    }
  }

  if (bestRule != null && bestScore >= 2) {
    return LegislationMatch(bestRule, true);
  }

  final fallback = globalLegislationDatabase.firstWhere(
    (r) => r.category == category,
    orElse: () => LegislationRule(
      id: '0',
      category: category,
      paragraph: '§ 101',
      subjectDescription: '',
    ),
  );
  return LegislationMatch(fallback, false);
}

List<LegislationRule> globalLegislationDatabase = [
  LegislationRule(
    id: '1',
    category: 'BOZP',
    lawNumber: '262/2006 Sb.',
    paragraph: '§ 102 odst. 1',
    citation: 'Zaměstnavatel je povinen vytvářet bezpečné a zdraví neohrožující pracovní prostředí.',
    subjectDescription: 'rozpadlé schody, prostředí pracoviště, nerovný povrch',
  ),
  LegislationRule(
    id: '2',
    category: 'PO',
    lawNumber: '133/1985 Sb.',
    paragraph: '§ 5 odst. 1',
    citation: 'Právnické osoby jsou povinny obstarávat a udržovat v práceschopném stavu věcné prostředky požární ochrany.',
    subjectDescription: 'zapadlý hasičák, chybějící revize PHP, zahrazený hydrant',
  ),
  LegislationRule(
    id: '3',
    category: 'BOZP',
    lawNumber: '101/2005 Sb.',
    paragraph: 'Příloha č. 3',
    citation: 'Únikové cesty a východy musejí zůstat trvale volné.',
    subjectDescription: 'blokovaný únikový východ, palety na chodbě',
  ),
];

Widget buildEkodavLogoHeader() {
  return GestureDetector(
    onTap: openEkodavWeb,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.eco, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
            RichText(
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: 'EKO',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  TextSpan(
                    text: 'DAV',
                    style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  TextSpan(
                    text: ' SAFETY',
                    style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w300),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget buildEkodavMainLogo() {
  return GestureDetector(
    onTap: openEkodavWeb,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'EK',
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: 0.5),
              ),
              Stack(
                alignment: Alignment.center,
                children: [
                  const Text(
                    'O',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  Positioned(
                    top: 6,
                    child: Transform.rotate(
                      angle: -0.2,
                      child: const Icon(Icons.eco, size: 20, color: Color(0xFF10B981)),
                    ),
                  ),
                ],
              ),
              const Text(
                'DAV',
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: 0.5),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'SAFETY',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF59E0B),
                    letterSpacing: 2.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'BOZP, PO, EKO',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF334155), letterSpacing: 3.0),
          ),
          const SizedBox(height: 2),
          const Text(
            'OBNOVITELNÉ ENERGIE',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B), letterSpacing: 2.5),
          ),
        ],
      ),
    ),
  );
}

class Finding {
  final String id;
  int orderNumber;
  String category;
  String severity;
  String description;
  String legislation;
  String locationDetail;
  bool isPhotoTaken;
  Uint8List? photoBytes;
  DateTime timestamp;

  Finding({
    required this.id,
    required this.orderNumber,
    required this.category,
    required this.severity,
    required this.description,
    this.legislation = '',
    this.locationDetail = '',
    this.isPhotoTaken = false,
    this.photoBytes,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'orderNumber': orderNumber,
        'category': category,
        'severity': severity,
        'description': description,
        'legislation': legislation,
        'locationDetail': locationDetail,
        'isPhotoTaken': isPhotoTaken,
        'photoBytes': photoBytes != null ? base64Encode(photoBytes!) : null,
        'timestamp': timestamp.toIso8601String(),
      };

  factory Finding.fromJson(Map<String, dynamic> json) => Finding(
        id: json['id'] as String,
        orderNumber: json['orderNumber'] as int,
        category: json['category'] as String,
        severity: json['severity'] as String,
        description: json['description'] as String,
        legislation: json['legislation'] as String? ?? '',
        locationDetail: json['locationDetail'] as String? ?? '',
        isPhotoTaken: json['isPhotoTaken'] as bool? ?? false,
        photoBytes: json['photoBytes'] != null ? base64Decode(json['photoBytes'] as String) : null,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

class InspectionReport {
  final String id;
  final String companyName;
  final String companyIco;
  final String companyAddress;
  final String locationName;
  final DateTime date;
  final List<Finding> findings;
  final String? gpsCoords;

  InspectionReport({
    required this.id,
    this.companyName = '',
    this.companyIco = '',
    this.companyAddress = '',
    required this.locationName,
    required this.date,
    required this.findings,
    this.gpsCoords,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyName': companyName,
        'companyIco': companyIco,
        'companyAddress': companyAddress,
        'locationName': locationName,
        'date': date.toIso8601String(),
        'findings': findings.map((f) => f.toJson()).toList(),
        'gpsCoords': gpsCoords,
      };

  factory InspectionReport.fromJson(Map<String, dynamic> json) => InspectionReport(
        id: json['id'] as String,
        companyName: json['companyName'] as String? ?? '',
        companyIco: json['companyIco'] as String? ?? '',
        companyAddress: json['companyAddress'] as String? ?? '',
        locationName: json['locationName'] as String,
        date: DateTime.parse(json['date'] as String),
        findings: (json['findings'] as List)
            .map((f) => Finding.fromJson(f as Map<String, dynamic>))
            .toList(),
        gpsCoords: json['gpsCoords'] as String?,
      );
}

/// Firma/lokace aktuálně rozpracované inspekce – slouží jako podklad pro
/// titulní stranu generovaného reportu (RevisionTableScreen na ni nemá
/// jinak přímý přístup, pracuje jen se seznamem `globalFindings`).
class ActiveReportContext {
  String companyName = '';
  String companyIco = '';
  String companyAddress = '';
  String locationName = '';
}

ActiveReportContext currentReportContext = ActiveReportContext();

List<Finding> globalFindings = [];
List<InspectionReport> savedReports = [
  InspectionReport(
    id: '1',
    companyName: 'BENZINA s.r.o.',
    companyIco: '12345678',
    companyAddress: 'Milevská 2095/5, Praha 4',
    locationName: 'Skladová hala A - Brno',
    date: DateTime.now().subtract(const Duration(days: 2)),
    findings: [
      Finding(
        id: '101',
        orderNumber: 1,
        category: 'BOZP',
        severity: 'Vysoká',
        description: 'Blokovaný únikový východ paletami',
        locationDetail: 'Sklad',
        legislation: 'Zákoník práce č. 262/2006 Sb.',
        timestamp: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ],
    gpsCoords: '49.1951, 16.6078',
  ),
];

// -----------------------------------------------------------------------------
// PERZISTENCE (localStorage prohlížeče přes shared_preferences)
// -----------------------------------------------------------------------------
const String _kLegislationKey = 'ekodav_legislation_v1';
const String _kReportsKey = 'ekodav_reports_v1';

Future<void> loadPersistedData() async {
  try {
    final prefs = await SharedPreferences.getInstance();

    final legislationJson = prefs.getString(_kLegislationKey);
    if (legislationJson != null) {
      final decoded = jsonDecode(legislationJson) as List;
      globalLegislationDatabase = decoded
          .map((e) => LegislationRule.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    final reportsJson = prefs.getString(_kReportsKey);
    if (reportsJson != null) {
      final decoded = jsonDecode(reportsJson) as List;
      savedReports = decoded
          .map((e) => InspectionReport.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  } catch (e) {
    debugPrint('Nepodařilo se načíst uložená data: $e');
  }
}

Future<void> persistLegislation() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(globalLegislationDatabase.map((r) => r.toJson()).toList());
    await prefs.setString(_kLegislationKey, encoded);
  } catch (e) {
    debugPrint('Nepodařilo se uložit legislativu: $e');
  }
}

Future<void> persistReports() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(savedReports.map((r) => r.toJson()).toList());
    await prefs.setString(_kReportsKey, encoded);
  } catch (e) {
    debugPrint('Nepodařilo se uložit reporty: $e');
  }
}

// -----------------------------------------------------------------------------
// 1. DOMOVSKÁ OBRAZOVKA
// -----------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        centerTitle: true,
        title: buildEkodavLogoHeader(),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 15),
                      buildEkodavMainLogo(),
                      const SizedBox(height: 12),
                      const Text(
                        'Inspekce BOZP a PO v terénu',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey),
                      ),
                      const SizedBox(height: 25),

                      ElevatedButton.icon(
                        icon: const Icon(Icons.add_a_photo, size: 24),
                        label: const Text('NOVÝ REPORT (V TERÉNU)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const NewReportScreen()),
                          );
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 10),

                      OutlinedButton.icon(
                        icon: const Icon(Icons.table_chart, size: 24),
                        label: Text('REVIZE REPORTU (U STOLU) (${globalFindings.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          foregroundColor: const Color(0xFF0F172A),
                          side: const BorderSide(color: Color(0xFF0F172A), width: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RevisionTableScreen()),
                          );
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 10),

                      OutlinedButton.icon(
                        icon: const Icon(Icons.folder_open, size: 24),
                        label: Text('HISTORIE REPORTŮ (${savedReports.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          foregroundColor: Colors.grey[800],
                          side: BorderSide(color: Colors.grey[600]!, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ReportsHistoryScreen()),
                          );
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 20),
                      const Divider(thickness: 1.5),
                      const SizedBox(height: 10),

                      ElevatedButton.icon(
                        icon: const Icon(Icons.gavel, size: 22),
                        label: Text('SPRÁVA LEGISLATIVY (${globalLegislationDatabase.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: const Color(0xFF34D399),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const LegislationManagerScreen()),
                          );
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: const Text(
                  'Aplikace je vlastnictvím společnosti EKODAV SAFETY s.r.o., se sídlem Černokostelecká 1806/123, Strašnice, 100 00 Praha 10, IČO: 19161930, zapsané v obchodním rejstříku vedeném Městským soudem v Praze, spis. zn. C 382362.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: Colors.grey, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SPRÁVA LEGISLATIVY
// -----------------------------------------------------------------------------
class LegislationManagerScreen extends StatefulWidget {
  const LegislationManagerScreen({Key? key}) : super(key: key);

  @override
  State<LegislationManagerScreen> createState() => _LegislationManagerScreenState();
}

class _LegislationManagerScreenState extends State<LegislationManagerScreen> {
  final List<String> _categories = [
    'BOZP', 'PO', 'Životní prostředí',
    'Technické normy', 'Revize a kontroly',
    'Regulatorní školení', 'ISO'
  ];

  void _showAddRuleDialog([LegislationRule? existingRule]) {
    String selectedCat = existingRule?.category ?? 'BOZP';
    final lawController = TextEditingController(text: existingRule?.lawNumber ?? '');
    final paraController = TextEditingController(text: existingRule?.paragraph ?? '');
    final citationController = TextEditingController(text: existingRule?.citation ?? '');
    final subjectController = TextEditingController(text: existingRule?.subjectDescription ?? '');
    String errorMessage = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              existingRule == null ? '➕ Přidat normu / předpis' : '✏️ Upravit normu / předpis',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (errorMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(errorMessage, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),

                  const Text('Oblast (BOZP / PO...): *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCat,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedCat = val);
                    },
                  ),
                  const SizedBox(height: 12),

                  const Text('Číslo legislativy / normy (nepovinné):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: lawController,
                    decoration: InputDecoration(
                      hintText: 'např. 262/2006 Sb. nebo ČSN 73 0802',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  const Text('Paragraf / Ustanovení: *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: paraController,
                    decoration: InputDecoration(
                      hintText: 'např. § 102 odst. 1',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  const Text('Přesná citace (nepovinné):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: citationController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'např. Zaměstnavatel je povinen vytvářet bezpečné prostředí...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  const Text('Čeho se týká (pro vyhodnocení fotek): *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: subjectController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'např. rozpadlé schody, zahrazený hydrant, chybějící kryt...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Zrušit'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('ULOŽIT NORMU'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  if (paraController.text.trim().isEmpty) {
                    setDialogState(() => errorMessage = '⚠️ Vyplňte povinný Paragraf.');
                    return;
                  }
                  if (subjectController.text.trim().isEmpty) {
                    setDialogState(() => errorMessage = '⚠️ Vyplňte popis čeho se týká.');
                    return;
                  }

                  setState(() {
                    if (existingRule != null) {
                      existingRule.category = selectedCat;
                      existingRule.lawNumber = lawController.text.trim();
                      existingRule.paragraph = paraController.text.trim();
                      existingRule.citation = citationController.text.trim();
                      existingRule.subjectDescription = subjectController.text.trim();
                    } else {
                      globalLegislationDatabase.add(
                        LegislationRule(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          category: selectedCat,
                          lawNumber: lawController.text.trim(),
                          paragraph: paraController.text.trim(),
                          citation: citationController.text.trim(),
                          subjectDescription: subjectController.text.trim(),
                        ),
                      );
                    }
                  });
                  persistLegislation();
                  Navigator.pop(context);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seznam čerpané legislativy & norem'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('PŘIDAT LEGISLATIVU / NORMU'),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        onPressed: () => _showAddRuleDialog(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Color(0xFF0284C7)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tato databáze norem slouží jako podklad pro automatické vyhodnocování pořízených fotografií a vytváření inspekčních nálezů.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'SEZNAM ČERPANÉ LEGISLATIVY (${globalLegislationDatabase.length}):',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: globalLegislationDatabase.length,
              itemBuilder: (context, index) {
                final rule = globalLegislationDatabase[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF0F172A),
                      child: Text(rule.category.substring(0, 1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    title: Text('${rule.category}${rule.lawNumber.isNotEmpty ? " č. ${rule.lawNumber}" : ""} (${rule.paragraph})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('🔎 Vyhodnocování fotek: ${rule.subjectDescription}', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0284C7))),
                        if (rule.citation.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('💬 "${rule.citation}"', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 11)),
                        ]
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showAddRuleDialog(rule),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              globalLegislationDatabase.removeAt(index);
                            });
                            persistLegislation();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 2. ZADÁNÍ LOKACE, FIRMY & HISTORIE
// -----------------------------------------------------------------------------
class NewReportScreen extends StatefulWidget {
  const NewReportScreen({Key? key}) : super(key: key);

  @override
  State<NewReportScreen> createState() => _NewReportScreenState();
}

class _NewReportScreenState extends State<NewReportScreen> {
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _icoController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  String? _gpsCoords;
  bool _isLoadingAres = false;
  bool _isLoadingGps = false;

  Set<String> get _recentLocationChips {
    final Set<String> chips = {};
    for (var report in savedReports) {
      if (report.companyName.isNotEmpty) chips.add(report.companyName);
      if (report.locationName.isNotEmpty) chips.add(report.locationName.split('(GPS:')[0].trim());
    }
    if (chips.isEmpty) {
      chips.addAll(['BENZINA s.r.o.', 'Čerpací stanice MOL', 'Skladová hala A', 'Unipetrol']);
    }
    return chips;
  }

  Future<void> _getGpsLocation() async {
    setState(() {
      _isLoadingGps = true;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Zapněte prosím službu polohy (GPS) v prohlížeči/zařízení.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Přístup k poloze byl zamítnut.';
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw 'Přístup k poloze je trvale zakázán – povolte ho v nastavení prohlížeče.';
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (!mounted) return;
      setState(() {
        _gpsCoords = '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📍 GPS pozice byla úspěšně načtena!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ Nepodařilo se získat GPS: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingGps = false;
        });
      }
    }
  }

  Future<void> _fetchAresData(String ico) async {
    final cleanIco = ico.replaceAll(RegExp(r'\s+'), '');
    if (cleanIco.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Vyplňte prosím IČO.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      _isLoadingAres = true;
    });

    try {
      final url = Uri.parse('https://ares.gov.cz/ares/nesstar/v1/ekonomicke-subjekty/$cleanIco');
      final response = await http.get(url, headers: {
        'Accept': 'application/json',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        
        final String companyName = (data['obchodniJmeno'] ?? '') as String;
        final String actualIco = (data['ico'] ?? cleanIco) as String;
        
        final Map<String, dynamic>? sidlo = data['sidlo'] as Map<String, dynamic>?;
        String street = '';
        String houseNumber = '';
        String city = '';
        String zip = '';

        if (sidlo != null) {
          street = sidlo['nazevUlice']?.toString() ?? '';
          if (street.isEmpty) {
            street = sidlo['nazevCastiObce']?.toString() ?? sidlo['nazevObce']?.toString() ?? '';
          }

          final cisloDomovni = sidlo['cisloDomovni'];
          final cisloOrientacni = sidlo['cisloOrientacni'];
          final cisloOrientacniPismeno = sidlo['cisloOrientacniPismeno'];

          if (cisloDomovni != null && cisloOrientacni != null) {
            houseNumber = '$cisloDomovni/$cisloOrientacni';
          } else if (cisloDomovni != null) {
            houseNumber = '$cisloDomovni';
          } else if (cisloOrientacni != null) {
            houseNumber = '$cisloOrientacni';
          }

          if (cisloOrientacniPismeno != null && cisloOrientacniPismeno.toString().isNotEmpty) {
            houseNumber += cisloOrientacniPismeno.toString();
          }

          final String nazevObce = sidlo['nazevObce']?.toString() ?? '';
          final String nazevCastiObce = sidlo['nazevCastiObce']?.toString() ?? '';
          if (nazevObce.isNotEmpty && nazevCastiObce.isNotEmpty && nazevObce != nazevCastiObce) {
            city = '$nazevObce - $nazevCastiObce';
          } else {
            city = nazevObce.isNotEmpty ? nazevObce : nazevCastiObce;
          }

          final pscVal = sidlo['psc'];
          if (pscVal != null) {
            final String rawZip = pscVal.toString().replaceAll(RegExp(r'\s+'), '');
            if (rawZip.length == 5) {
              zip = '${rawZip.substring(0, 3)} ${rawZip.substring(3)}';
            } else {
              zip = rawZip;
            }
          }
        }

        setState(() {
          if (companyName.isNotEmpty) {
            _companyController.text = companyName;
          }
          if (actualIco.isNotEmpty) {
            _icoController.text = actualIco;
          }
          
          final List<String> addressParts = [];
          if (street.isNotEmpty) {
            if (houseNumber.isNotEmpty) {
              addressParts.add('$street $houseNumber');
            } else {
              addressParts.add(street);
            }
          } else if (houseNumber.isNotEmpty) {
            addressParts.add(houseNumber);
          }
          
          final String cityAndZip = [zip, city].where((s) => s.isNotEmpty).join(' ');
          if (cityAndZip.isNotEmpty) {
            addressParts.add(cityAndZip);
          }
          
          _addressController.text = addressParts.join(', ');
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Načteno z ARES:\n'
                'Firma: $companyName\n'
                'IČO: $actualIco\n'
                'Ulice: $street\n'
                'Č. p.: $houseNumber\n'
                'Město: $city\n'
                'PSČ: $zip',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else if (response.statusCode == 404) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Subjekt s tímto IČO nebyl v ARES nalezen.'), backgroundColor: Colors.red),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Chyba při načítání z ARES (kód ${response.statusCode}).'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Chyba připojení: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAres = false;
        });
      }
    }
  }

  void _startInspection() {
    String loc = _locationController.text.trim();
    String comp = _companyController.text.trim();
    if (loc.isEmpty) {
      loc = 'Inspekce BOZP (${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year})';
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => InspectionModeScreen(
          locationName: _gpsCoords != null ? '$loc (GPS: $_gpsCoords)' : loc,
          companyName: comp,
          companyIco: _icoController.text.trim(),
          companyAddress: _addressController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zadání lokace & historie')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('KONTROLOVANÝ SUBJEKT (FIRMA):', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
            const SizedBox(height: 8),

            TextField(
              controller: _companyController,
              decoration: InputDecoration(
                labelText: 'Název firmy',
                hintText: 'např. BENZINA s.r.o.',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.business, color: Color(0xFF0284C7)),
              ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _icoController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'IČO',
                      hintText: '12345678',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.numbers, color: Color(0xFF0284C7)),
                      suffixIcon: _isLoadingAres
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(12.0),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.search, color: Color(0xFF0284C7)),
                              tooltip: 'Načíst z ARES',
                              onPressed: () => _fetchAresData(_icoController.text),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      labelText: 'Sídlo / Adresa',
                      hintText: 'Praha 4',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.home, color: Color(0xFF0284C7)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text('Zadejte název lokace / pracoviště / provozovny:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                TextButton.icon(
                  onPressed: _isLoadingGps ? null : _getGpsLocation,
                  icon: _isLoadingGps
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.my_location, size: 18, color: _gpsCoords != null ? Colors.green : Colors.red),
                  label: Text(
                    _isLoadingGps ? 'Zjišťuji polohu...' : (_gpsCoords != null ? 'GPS Načtena' : 'Získat GPS'),
                    style: TextStyle(color: _gpsCoords != null ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                )
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _locationController,
              decoration: InputDecoration(
                hintText: 'např. Čerpací stanice, hala, budova...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.location_on, color: Color(0xFF0284C7)),
              ),
            ),
            const SizedBox(height: 18),

            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow, size: 28),
              label: const Text('ZÁHAJIT NOVOU KONTROLU', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _startInspection,
            ),

            const SizedBox(height: 20),
            const Divider(thickness: 1.5),

            const Text('Rychlý výběr z nedávných firem a provozoven:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _recentLocationChips.map((item) {
                return ActionChip(
                  avatar: const Icon(Icons.history, size: 16, color: Color(0xFF0284C7)),
                  label: Text(item, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  backgroundColor: Colors.blue[50],
                  side: BorderSide(color: Colors.blue[200]!),
                  onPressed: () {
                    setState(() {
                      if (_companyController.text.isEmpty) {
                        _companyController.text = item;
                      } else {
                        _locationController.text = item;
                      }
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 20),
            const Divider(thickness: 1.5),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PROBĚHLÉ REPORTY V HISTORII:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                Chip(
                  label: Text('${savedReports.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  backgroundColor: const Color(0xFF0284C7),
                )
              ],
            ),
            const SizedBox(height: 8),

            if (savedReports.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Text('Zatím nebyly dokončeny žádné reporty.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: savedReports.length,
                itemBuilder: (context, index) {
                  final report = savedReports[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    elevation: 2,
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFF0284C7),
                        child: Icon(Icons.description, color: Colors.white),
                      ),
                      title: Text(
                        '${report.companyName.isNotEmpty ? "${report.companyName} - " : ""}${report.locationName}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (report.companyIco.isNotEmpty) Text('IČO: ${report.companyIco} • Sídlo: ${report.companyAddress}'),
                          Text('Počet nálezů: ${report.findings.length} • ${report.date.day}.${report.date.month}.${report.date.year}'),
                          if (report.locationName.contains('GPS:'))
                            GestureDetector(
                              onTap: () {
                                openGoogleMaps(report.locationName);
                              },
                              child: const Padding(
                                padding: EdgeInsets.only(top: 4.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.map, size: 16, color: Colors.red),
                                    SizedBox(width: 4),
                                    Text('Otevřít v Google Maps', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.underline)),
                                  ],
                                ),
                              ),
                            )
                        ],
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        globalFindings = List.from(report.findings);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => InspectionModeScreen(
                              locationName: report.locationName,
                              companyName: report.companyName,
                              companyIco: report.companyIco,
                              companyAddress: report.companyAddress,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 3. INSPEKČNÍ REŽIM SE ZADÁVÁNÍM MÍSTA
// -----------------------------------------------------------------------------
class InspectionModeScreen extends StatefulWidget {
  final String locationName;
  final String companyName;
  final String companyIco;
  final String companyAddress;

  const InspectionModeScreen({
    Key? key,
    required this.locationName,
    this.companyName = '',
    this.companyIco = '',
    this.companyAddress = '',
  }) : super(key: key);

  @override
  State<InspectionModeScreen> createState() => _InspectionModeScreenState();
}

class _InspectionModeScreenState extends State<InspectionModeScreen> {
  Uint8List? _currentPhotoBytes;
  String _selectedCategory = 'BOZP';
  String _selectedSeverity = 'Střední';
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _placeController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  int _editingIndex = -1;
  String _statusMessage = '';

  final List<String> _categories = [
    'BOZP', 'PO', 'Životní prostředí',
    'Technické normy', 'Revize a kontroly',
    'Regulatorní školení', 'ISO'
  ];

  final List<String> _severities = ['Vysoká', 'Střední', 'Nízká', 'Doporučení'];

  @override
  void initState() {
    super.initState();
    currentReportContext = ActiveReportContext()
      ..companyName = widget.companyName
      ..companyIco = widget.companyIco
      ..companyAddress = widget.companyAddress
      ..locationName = widget.locationName;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _currentPhotoBytes = bytes;
          _statusMessage = source == ImageSource.camera
              ? '📷 Fotografie úspěšně načtena!'
              : '📷 Fotografie načtena z galerie!';
        });
      }
      // pickedFile == null znamená, že uživatel focení/výběr zrušil – to není chyba.
    } catch (e) {
      if (source == ImageSource.camera) {
        // Fotoaparát selhal (chybí oprávnění / zařízení bez kamery) – nabídneme galerii jako záchranu.
        try {
          final XFile? galleryFile = await _picker.pickImage(source: ImageSource.gallery);
          if (galleryFile != null) {
            final bytes = await galleryFile.readAsBytes();
            setState(() {
              _currentPhotoBytes = bytes;
              _statusMessage = '📷 Fotoaparát nedostupný, fotografie načtena z galerie.';
            });
          }
        } catch (err) {
          setState(() {
            _statusMessage = '⚠️ Povolte v prohlížeči přístup k fotoaparátu nebo galerii.';
          });
        }
      } else {
        setState(() {
          _statusMessage = '⚠️ Nepodařilo se načíst fotografii z galerie.';
        });
      }
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Vyberte zdroj fotografie:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF0284C7), size: 30),
              title: const Text('Vyfotit fotoaparátem'),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green, size: 30),
              title: const Text('Vybrat z galerie'),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (_currentPhotoBytes != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red, size: 30),
                title: const Text('Odstranit fotografii'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _currentPhotoBytes = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  void _saveAndNext() {
    setState(() {
      final placeText = _placeController.text.trim();

      if (placeText.isNotEmpty) {
        subLocationHistory.add(placeText);
      }

      final noteText = _noteController.text.isEmpty ? 'Nález bez poznámky' : _noteController.text;
      final match = matchLegislation(noteText, _selectedCategory);
      final matchedLegislation = match?.rule.fullTitle ?? '';
      final matchLabel = match == null
          ? ''
          : (match.isConfident ? ' (🤖 auto-přiřazeno)' : ' (⚠️ zkontrolujte)');

      if (_editingIndex >= 0 && _editingIndex < globalFindings.length) {
        final existing = globalFindings[_editingIndex];
        existing.category = _selectedCategory;
        existing.severity = _selectedSeverity;
        existing.description = noteText;
        existing.locationDetail = placeText;
        existing.photoBytes = _currentPhotoBytes;
        existing.isPhotoTaken = _currentPhotoBytes != null;
        existing.legislation = matchedLegislation;
        _statusMessage = '⚡ Nález #${existing.orderNumber} aktualizován!$matchLabel';
      } else {
        final newFinding = Finding(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          orderNumber: globalFindings.length + 1,
          category: _selectedCategory,
          severity: _selectedSeverity,
          description: noteText,
          locationDetail: placeText,
          legislation: matchedLegislation,
          photoBytes: _currentPhotoBytes,
          isPhotoTaken: _currentPhotoBytes != null,
          timestamp: DateTime.now(),
        );

        globalFindings.add(newFinding);
        _statusMessage = '⚡ Nález #${newFinding.orderNumber} uložen!$matchLabel';
      }

      _resetFormToNew();
    });
  }

  void _resetFormToNew() {
    _editingIndex = -1;
    _currentPhotoBytes = null;
    _noteController.clear();
    _placeController.clear();
    _selectedCategory = 'BOZP';
    _selectedSeverity = 'Střední';
  }

  void _loadFindingIntoForm(int index) {
    if (index >= 0 && index < globalFindings.length) {
      final finding = globalFindings[index];
      setState(() {
        _editingIndex = index;
        _currentPhotoBytes = finding.photoBytes;
        _selectedCategory = finding.category;
        _selectedSeverity = finding.severity;
        _noteController.text = finding.description;
        _placeController.text = finding.locationDetail;
        _statusMessage = 'Načten nález #${finding.orderNumber} k úpravě';
      });
    }
  }

  void _finishInspection() {
    if (globalFindings.isNotEmpty) {
      final report = InspectionReport(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        companyName: widget.companyName,
        companyIco: widget.companyIco,
        companyAddress: widget.companyAddress,
        locationName: widget.locationName,
        date: DateTime.now(),
        findings: List.from(globalFindings),
      );
      savedReports.insert(0, report);
      persistReports();
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inspekce: ${widget.companyName.isNotEmpty ? "${widget.companyName} - " : ""}${widget.locationName}', style: const TextStyle(fontSize: 14)),
            Text('Uloženo nálezů: ${globalFindings.length}', style: const TextStyle(fontSize: 11, color: Colors.greenAccent)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 30),
            onPressed: _finishInspection,
            tooltip: 'Dokončit inspekci',
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_statusMessage.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[700]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_statusMessage, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _statusMessage = ''),
                    )
                  ],
                ),
              ),

            if (_editingIndex >= 0 && _editingIndex < globalFindings.length)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(8),
                color: Colors.amber[100],
                child: Row(
                  children: [
                    const Icon(Icons.edit, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Upravujete Nález #${globalFindings[_editingIndex].orderNumber}'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _resetFormToNew()),
                      child: const Text('Zrušit'),
                    )
                  ],
                ),
              ),

            GestureDetector(
              onTap: _showImageSourceDialog,
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  color: _currentPhotoBytes != null ? Colors.black : Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _currentPhotoBytes != null ? Colors.green : Colors.grey[400]!,
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _currentPhotoBytes != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(_currentPhotoBytes!, fit: BoxFit.cover),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.edit, color: Colors.white, size: 20),
                              ),
                            )
                          ],
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt_outlined, size: 48, color: Color(0xFF0284C7)),
                            SizedBox(height: 8),
                            Text('1. ŤUKNI PRO VYFOCENÍ / VYBRÁNÍ FOTKY', style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 13)),
                            Text('(Aplikace otevře mobilní fotoaparát)', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            const Text('Místo / Upřesnění lokace nálezu:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            TextField(
              controller: _placeController,
              decoration: InputDecoration(
                hintText: 'např. Sklad, Parkoviště, Dílna, Rampa...',
                prefixIcon: const Icon(Icons.place, color: Color(0xFF0284C7)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: subLocationHistory.map((place) {
                return ActionChip(
                  avatar: const Icon(Icons.history, size: 14, color: Color(0xFF0284C7)),
                  label: Text(place, style: const TextStyle(fontSize: 12)),
                  backgroundColor: Colors.blue[50],
                  onPressed: () {
                    setState(() {
                      _placeController.text = place;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            const Text('2. Kategorie:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: const Color(0xFF0284C7),
                  labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
                  onSelected: (val) => setState(() => _selectedCategory = cat),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            const Text('3. Závažnost:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: _severities.map((sev) {
                final isSelected = _selectedSeverity == sev;
                Color color = Colors.grey;
                if (sev == 'Vysoká') color = Colors.red;
                if (sev == 'Střední') color = Colors.orange;
                if (sev == 'Nízká') color = Colors.amber;
                if (sev == 'Doporučení') color = Colors.blue;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected ? color : Colors.grey[200],
                        foregroundColor: isSelected ? Colors.white : Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () => setState(() => _selectedSeverity = sev),
                      child: Text(sev, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: '4. Popis / Hlasová poznámka',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.mic, color: Colors.red),
              ),
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              icon: const Icon(Icons.flash_on, size: 28),
              label: Text(
                _editingIndex >= 0 ? 'ULOŽIT ZMĚNY NÁLEZU' : 'ULOŽIT A DALŠÍ NÁLEZ',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saveAndNext,
            ),

            const SizedBox(height: 20),
            const Divider(thickness: 2),

            Text(
              'SEZNAM NÁLEZŮ (${globalFindings.length}):',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey),
            ),
            const SizedBox(height: 8),

            if (globalFindings.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text('Zatím nebyly zadané žádné nálezy.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: globalFindings.length,
                itemBuilder: (context, index) {
                  final item = globalFindings[index];
                  final isCurrentlyEditing = _editingIndex == index;

                  return Card(
                    color: isCurrentlyEditing ? Colors.amber[50] : null,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      dense: true,
                      leading: item.photoBytes != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.memory(item.photoBytes!, width: 40, height: 40, fit: BoxFit.cover),
                            )
                          : CircleAvatar(
                              radius: 14,
                              backgroundColor: item.severity == 'Vysoká'
                                  ? Colors.red
                                  : item.severity == 'Střední'
                                      ? Colors.orange
                                      : Colors.blue,
                              child: Text('#${item.orderNumber}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                            ),
                      title: Text('${item.category} • ${item.severity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${item.locationDetail.isNotEmpty ? "📍 Místo: ${item.locationDetail}\n" : ""}${item.description}'),
                      onTap: () => _loadFindingIntoForm(index),
                    ),
                  );
                },
              ),

            const SizedBox(height: 20),

            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline, size: 26),
              label: Text(
                'DOKONČIT INSPEKCI (${globalFindings.length} NÁLEZŮ)',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _finishInspection,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class ReportsHistoryScreen extends StatelessWidget {
  const ReportsHistoryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historie inspekčních reportů')),
      body: savedReports.isEmpty
          ? const Center(
              child: Text('Zatím nebyly dokončeny žádné reporty.', style: TextStyle(color: Colors.grey)),
            )
          : ListView.builder(
              itemCount: savedReports.length,
              itemBuilder: (context, index) {
                final report = savedReports[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF0284C7),
                      child: Icon(Icons.description, color: Colors.white),
                    ),
                    title: Text(
                      '${report.companyName.isNotEmpty ? "${report.companyName} - " : ""}${report.locationName}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (report.companyIco.isNotEmpty) Text('IČO: ${report.companyIco} • Sídlo: ${report.companyAddress}'),
                        Text('Počet nálezů: ${report.findings.length}\nDatum: ${report.date.day}.${report.date.month}.${report.date.year} ${report.date.hour}:${report.date.minute.toString().padLeft(2, '0')}'),
                        if (report.locationName.contains('GPS:'))
                          GestureDetector(
                            onTap: () {
                              openGoogleMaps(report.locationName);
                            },
                            child: const Padding(
                              padding: EdgeInsets.only(top: 4.0),
                              child: Row(
                                children: [
                                  Icon(Icons.map, size: 16, color: Colors.red),
                                  SizedBox(width: 4),
                                  Text('Otevřít v Google Maps', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.underline)),
                                ],
                              ),
                            ),
                          )
                      ],
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      globalFindings = List.from(report.findings);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => InspectionModeScreen(
                            locationName: report.locationName,
                            companyName: report.companyName,
                            companyIco: report.companyIco,
                            companyAddress: report.companyAddress,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

class RevisionTableScreen extends StatefulWidget {
  const RevisionTableScreen({Key? key}) : super(key: key);

  @override
  State<RevisionTableScreen> createState() => _RevisionTableScreenState();
}

class _RevisionTableScreenState extends State<RevisionTableScreen> {
  void _editLegislation(Finding finding) {
    TextEditingController legController = TextEditingController(text: finding.legislation);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Upravit legislativu (#${finding.orderNumber})'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nález: ${finding.description}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: legController,
              decoration: const InputDecoration(
                labelText: 'Český zákon / norma',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zrušit')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                finding.legislation = legController.text;
              });
              Navigator.pop(context);
            },
            child: const Text('Uložit'),
          )
        ],
      ),
    );
  }

  static const PdfColor _pdfNavy = PdfColor.fromInt(0xFF0F172A);
  static const PdfColor _pdfGreen = PdfColor.fromInt(0xFF10B981);
  static const PdfColor _pdfBlue = PdfColor.fromInt(0xFF0284C7);
  static const PdfColor _pdfAmber = PdfColor.fromInt(0xFFF59E0B);
  static const PdfColor _pdfSlate = PdfColor.fromInt(0xFF334155);

  PdfColor _severityColor(String severity) {
    switch (severity) {
      case 'Vysoká':
      case 'Vysoka':
        return PdfColors.red700;
      case 'Střední':
      case 'Stredni':
        return _pdfAmber;
      case 'Nízká':
      case 'Nizka':
        return _pdfBlue;
      default:
        return _pdfGreen;
    }
  }

  pw.Widget _severityBadge(String severity) {
    final color = _severityColor(severity);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(color: color, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10))),
      child: pw.Text(severity.toUpperCase(), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
    );
  }

  pw.Widget _statChip(String label, int count, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const pw.EdgeInsets.only(right: 6, bottom: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text('$count', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: color)),
          pw.SizedBox(width: 4),
          pw.Text(label, style: pw.TextStyle(fontSize: 10, color: _pdfSlate)),
        ],
      ),
    );
  }

  Future<void> _generateAndDownloadPdf() async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

    final bySeverity = <String, int>{};
    final byCategory = <String, int>{};
    for (final f in globalFindings) {
      bySeverity[f.severity] = (bySeverity[f.severity] ?? 0) + 1;
      byCategory[f.category] = (byCategory[f.category] ?? 0) + 1;
    }

    final ctx = currentReportContext;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 26, 30, 26),
        header: (context) {
          if (context.pageNumber == 1) return pw.SizedBox();
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 6),
            margin: const pw.EdgeInsets.only(bottom: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 1)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('EKODAV SAFETY – Protokol BOZP a PO', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                pw.Text(dateStr, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
          );
        },
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Strana ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (pw.Context context) {
          return [
            // --- TITULNÍ STRANA ---
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: _pdfNavy,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Text('EKO', style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                      pw.Text('DAV', style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: _pdfGreen)),
                      pw.SizedBox(width: 8),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: pw.BoxDecoration(color: _pdfAmber, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
                        child: pw.Text('SAFETY', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _pdfNavy)),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('BOZP  •  PO  •  ŽIVOTNÍ PROSTŘEDÍ', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey400, letterSpacing: 1.2)),
                ],
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Text('PROTOKOL O PROVEDENÉ INSPEKCI', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _pdfNavy)),
            pw.SizedBox(height: 4),
            pw.Text('Vystaveno: $dateStr', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
            pw.SizedBox(height: 16),

            // --- INFO O SUBJEKTU ---
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (ctx.companyName.isNotEmpty) _infoRow('Kontrolovaný subjekt', ctx.companyName),
                  if (ctx.companyIco.isNotEmpty) _infoRow('IČO', ctx.companyIco),
                  if (ctx.companyAddress.isNotEmpty) _infoRow('Sídlo', ctx.companyAddress),
                  if (ctx.locationName.isNotEmpty) _infoRow('Místo inspekce', ctx.locationName),
                  _infoRow('Celkový počet nálezů', '${globalFindings.length}'),
                ],
              ),
            ),
            pw.SizedBox(height: 18),

            // --- SOUHRN ---
            pw.Text('SOUHRN NÁLEZŮ', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _pdfNavy)),
            pw.SizedBox(height: 8),
            pw.Wrap(
              children: [
                for (final entry in bySeverity.entries) _statChip(entry.key, entry.value, _severityColor(entry.key)),
              ],
            ),
            pw.Wrap(
              children: [
                for (final entry in byCategory.entries) _statChip(entry.key, entry.value, _pdfBlue),
              ],
            ),

            pw.NewPage(),

            // --- JEDNOTLIVÉ NÁLEZY ---
            pw.Text('DETAIL NÁLEZŮ', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _pdfNavy)),
            pw.SizedBox(height: 10),
            ...globalFindings.map((f) {
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 14),
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Nález #${f.orderNumber} – ${f.category}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: _pdfNavy)),
                        _severityBadge(f.severity),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    if (f.locationDetail.isNotEmpty) ...[
                      pw.Text('Místo nálezu: ${f.locationDetail}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey800)),
                      pw.SizedBox(height: 3),
                    ],
                    pw.Text('Popis: ${f.description}', style: const pw.TextStyle(fontSize: 11)),
                    pw.SizedBox(height: 5),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: pw.BoxDecoration(color: PdfColors.blue50, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
                      child: pw.Text('Zákon / Norma: ${f.legislation}', style: pw.TextStyle(color: _pdfBlue, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    if (f.photoBytes != null) ...[
                      pw.SizedBox(height: 8),
                      pw.ClipRRect(
                        horizontalRadius: 6,
                        verticalRadius: 6,
                        child: pw.Container(
                          height: 160,
                          width: double.infinity,
                          child: pw.Image(pw.MemoryImage(f.photoBytes!), fit: pw.BoxFit.cover),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ];
        },
      ),
    );

    final pdfBytes = await pdf.save();
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'Protokol_BOZP_${now.day}_${now.month}_${now.year}.pdf',
    );
  }

  pw.Widget _infoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 150,
            child: pw.Text(label, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }

  void _generateReportPreview() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.picture_as_pdf, color: Colors.red),
            SizedBox(width: 8),
            Text('GENERÁTOR REPORTU', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PROTOKOL O INSPEKCI BOZP A PO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0284C7))),
              const Divider(),
              Text('Celkem nálezů: ${globalFindings.length}'),
              Text('Datum vygenerování: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}'),
              const SizedBox(height: 12),
              const Text('Obsah reportu ke stažení:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              Container(
                height: 180,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: globalFindings.length,
                  itemBuilder: (context, idx) {
                    final f = globalFindings[idx];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          if (f.photoBytes != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.memory(f.photoBytes!, width: 30, height: 30, fit: BoxFit.cover),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              '• #${f.orderNumber} [${f.category}] ${f.locationDetail.isNotEmpty ? "(${f.locationDetail}) " : ""}${f.description}\n   Norma: ${f.legislation}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zavřít'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('STÁHNOUT REPORT (PDF)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              _generateAndDownloadPdf();
            },
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Revize reportu u stolu (${globalFindings.length} nálezů)')),
      body: globalFindings.isEmpty
          ? const Center(child: Text('Zatím nebyly zadané žádné nálezy.'))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: globalFindings.length,
                    itemBuilder: (context, index) {
                      final finding = globalFindings[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: finding.photoBytes != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.memory(finding.photoBytes!, width: 40, height: 40, fit: BoxFit.cover),
                                )
                              : CircleAvatar(
                                  backgroundColor: finding.severity == 'Vysoká'
                                      ? Colors.red
                                      : finding.severity == 'Střední'
                                          ? Colors.orange
                                          : Colors.blue,
                                  child: Text('#${finding.orderNumber}', style: const TextStyle(color: Colors.white)),
                                ),
                          title: Text('${finding.category} • ${finding.severity} závažnost', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${finding.locationDetail.isNotEmpty ? "📍 Místo: ${finding.locationDetail}\n" : ""}${finding.description}\n📜 Norma: ${finding.legislation}'),
                          trailing: const Icon(Icons.edit, color: Color(0xFF0284C7)),
                          isThreeLine: true,
                          onTap: () => _editLegislation(finding),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.print, size: 28),
                    label: const Text('GENERATOVAT REPORT (PDF / EXPORT)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _generateReportPreview,
                  ),
                ),
              ],
            ),
    );
  }
}