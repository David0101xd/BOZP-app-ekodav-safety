import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  runApp(const EkodavSafetyApp());
}

class EkodavSafetyApp extends StatelessWidget {
  const EkodavSafetyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EKODAV SAFETY',
      theme: ThemeData(
        primaryColor: const Color(0xFF1E293B),
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

// Funkce pro otevření webu www.ekodav.cz po kliknutí na logo
void openEkodavWeb() {
  html.window.open('https://www.ekodav.cz', '_blank');
}

// -----------------------------------------------------------------------------
// POMOCNÁ FUNKCE PRO LEGISLATIVU
// -----------------------------------------------------------------------------
String getDefaultLegislation(String category) {
  switch (category) {
    case 'BOZP':
      return 'Zakonik prace c. 262/2006 Sb., NV c. 101/2005 Sb.';
    case 'PO':
      return 'Zakon c. 133/1985 Sb. o PO, Vyhlaska c. 246/2001 Sb.';
    case 'Životní prostředí':
      return 'Zakon c. 541/2020 Sb. (odpady), Zakon c. 201/2012 Sb.';
    case 'Technické normy':
      return 'NV c. 378/2001 Sb. (strojni zarizeni), CSN normy';
    case 'Revize a kontroly':
      return 'NV c. 190/2022 Sb., NV c. 194/2022 Sb. (VTZ)';
    case 'Regulatorní školení':
      return 'Zakonik prace c. 262/2006 Sb. (103 odst. 2)';
    case 'ISO':
      return 'CSN EN ISO 45001 / ISO 14001';
    default:
      return 'Zakonik prace c. 262/2006 Sb.';
  }
}

// -----------------------------------------------------------------------------
// DATOVÉ MODELY
// -----------------------------------------------------------------------------
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
}

class InspectionReport {
  final String id;
  final String locationName;
  final DateTime date;
  final List<Finding> findings;

  InspectionReport({
    required this.id,
    required this.locationName,
    required this.date,
    required this.findings,
  });
}

List<Finding> globalFindings = [];
List<InspectionReport> savedReports = [];

// -----------------------------------------------------------------------------
// 1. DOMOVSKÁ OBRAZOVKA (S KLIKACÍM LOGEM V HLAVIČCE)
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
        title: GestureDetector(
          onTap: openEkodavWeb,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.network(
                  'logo.png',
                  height: 34,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(Icons.eco, color: Colors.greenAccent, size: 28);
                  },
                ),
                const SizedBox(width: 10),
                const Text(
                  'EKODAV SAFETY',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: openEkodavWeb,
              child: const Icon(Icons.shield_outlined, size: 80, color: Color(0xFF0284C7)),
            ),
            const SizedBox(height: 10),
            const Text(
              'Inspekce BOZP a PO v terenu',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.grey),
            ),
            const SizedBox(height: 30),

            ElevatedButton.icon(
              icon: const Icon(Icons.add_a_photo, size: 26),
              label: const Text('NOVY REPORT (V TERENU)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
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
            const SizedBox(height: 12),

            OutlinedButton.icon(
              icon: const Icon(Icons.table_chart, size: 26),
              label: Text('REVIZE U STOLU (${globalFindings.length} NALEZU)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
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
            const SizedBox(height: 12),

            OutlinedButton.icon(
              icon: const Icon(Icons.folder_open, size: 26),
              label: Text('HISTORIE REPORTU (${savedReports.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
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
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 2. ZADÁNÍ LOKACE
// -----------------------------------------------------------------------------
class NewReportScreen extends StatefulWidget {
  const NewReportScreen({Key? key}) : super(key: key);

  @override
  State<NewReportScreen> createState() => _NewReportScreenState();
}

class _NewReportScreenState extends State<NewReportScreen> {
  final TextEditingController _locationController = TextEditingController();
  final List<String> _historyLocations = [
    'Cerpaci stanice Benzina - Praha 4',
    'Skladova hala B - Brno',
    'Tovarna Unipetrol - Litvinov'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zadani lokace')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Zadejte nazev lokace / pracoviste:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _locationController,
              decoration: InputDecoration(
                hintText: 'napr. Cerpaci stanice, hala, budova...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.location_on),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Nebo vyberte z nedavnych navstivenych:', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _historyLocations.map((loc) {
                return ActionChip(
                  label: Text(loc),
                  onPressed: () => setState(() => _locationController.text = loc),
                );
              }).toList(),
            ),
            const Spacer(),
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow, size: 28),
              label: const Text('ZAHAJIT INSPEKCI', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                if (_locationController.text.trim().isEmpty) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => InspectionModeScreen(locationName: _locationController.text)),
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
// 3. INSPEKČNÍ REŽIM
// -----------------------------------------------------------------------------
class InspectionModeScreen extends StatefulWidget {
  final String locationName;
  const InspectionModeScreen({Key? key, required this.locationName}) : super(key: key);

  @override
  State<InspectionModeScreen> createState() => _InspectionModeScreenState();
}

class _InspectionModeScreenState extends State<InspectionModeScreen> {
  Uint8List? _currentPhotoBytes;
  String _selectedCategory = 'BOZP';
  String _selectedSeverity = 'Stredni';
  final TextEditingController _noteController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  int _editingIndex = -1;
  String _statusMessage = '';

  final List<String> _categories = [
    'BOZP', 'PO', 'Zivotni prostredi',
    'Technicke normy', 'Revize a kontroly',
    'Regulatorni skoleni', 'ISO'
  ];

  final List<String> _severities = ['Vysoka', 'Stredni', 'Nizka', 'Doporuceni'];

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
          _statusMessage = '📷 Fotografie uspesne nactena!';
        });
      }
    } catch (e) {
      try {
        final XFile? galleryFile = await _picker.pickImage(source: ImageSource.gallery);
        if (galleryFile != null) {
          final bytes = await galleryFile.readAsBytes();
          setState(() {
            _currentPhotoBytes = bytes;
            _statusMessage = '📷 Fotografie nactena z galerie!';
          });
        }
      } catch (err) {
        setState(() {
          _statusMessage = '⚠️ Povolte v prohlizeci pristup k fotoaparatu.';
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
              title: const Text('Vyfotit / Vybrat soubor'),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green, size: 30),
              title: const Text('Galerie obrazku'),
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
      final autoLegislation = getDefaultLegislation(_selectedCategory);

      if (_editingIndex >= 0 && _editingIndex < globalFindings.length) {
        final existing = globalFindings[_editingIndex];
        existing.category = _selectedCategory;
        existing.severity = _selectedSeverity;
        existing.description = _noteController.text.isEmpty ? 'Nalez bez poznamky' : _noteController.text;
        existing.photoBytes = _currentPhotoBytes;
        existing.isPhotoTaken = _currentPhotoBytes != null;
        if (existing.legislation.isEmpty) {
          existing.legislation = autoLegislation;
        }
        _statusMessage = '⚡ Nalez #${existing.orderNumber} aktualizovan!';
      } else {
        final newFinding = Finding(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          orderNumber: globalFindings.length + 1,
          category: _selectedCategory,
          severity: _selectedSeverity,
          description: _noteController.text.isEmpty ? 'Nalez bez poznamky' : _noteController.text,
          legislation: autoLegislation,
          photoBytes: _currentPhotoBytes,
          isPhotoTaken: _currentPhotoBytes != null,
          timestamp: DateTime.now(),
        );

        globalFindings.add(newFinding);
        _statusMessage = '⚡ Nalez #${newFinding.orderNumber} ulozen!';
      }

      _resetFormToNew();
    });
  }

  void _resetFormToNew() {
    _editingIndex = -1;
    _currentPhotoBytes = null;
    _noteController.clear();
    _selectedCategory = 'BOZP';
    _selectedSeverity = 'Stredni';
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
        _statusMessage = 'Nacten nalez #${finding.orderNumber} k uprave';
      });
    }
  }

  void _finishInspection() {
    if (globalFindings.isNotEmpty) {
      final report = InspectionReport(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        locationName: widget.locationName,
        date: DateTime.now(),
        findings: List.from(globalFindings),
      );
      savedReports.insert(0, report);
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
            Text('Inspekce: ${widget.locationName}', style: const TextStyle(fontSize: 16)),
            Text('Ulozeno nalezu: ${globalFindings.length}', style: const TextStyle(fontSize: 12, color: Colors.greenAccent)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 30),
            onPressed: _finishInspection,
            tooltip: 'Dokoncit inspekci',
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
                      child: Text('Upravujete Nalez #${globalFindings[_editingIndex].orderNumber}'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _resetFormToNew()),
                      child: const Text('Zrusit'),
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
                                  color: Colors.black.withOpacity(0.6),
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
                            Text('1. TUKNI PRO VYFOCENI / VYBRANI FOTKY', style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 13)),
                            Text('(Aplikace otevre mobilni fotoaparat)', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),

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

            const Text('3. Zavaznost:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: _severities.map((sev) {
                final isSelected = _selectedSeverity == sev;
                Color color = Colors.grey;
                if (sev == 'Vysoka') color = Colors.red;
                if (sev == 'Stredni') color = Colors.orange;
                if (sev == 'Nizka') color = Colors.amber;
                if (sev == 'Doporuceni') color = Colors.blue;

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
                labelText: '4. Popis / Hlasova poznamka',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.mic, color: Colors.red),
              ),
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              icon: const Icon(Icons.flash_on, size: 28),
              label: Text(
                _editingIndex >= 0 ? 'ULOZIT ZMENY NALEZU' : 'ULOZIT A DALSÍ NALEZ',
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
              'SEZNAM NALEZU (${globalFindings.length}):',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey),
            ),
            const SizedBox(height: 8),

            if (globalFindings.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text('Zatim nebyly zadane zadne nalezy.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
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
                              backgroundColor: item.severity == 'Vysoka'
                                  ? Colors.red
                                  : item.severity == 'Stredni'
                                      ? Colors.orange
                                      : Colors.blue,
                              child: Text('#${item.orderNumber}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                            ),
                      title: Text('${item.category} • ${item.severity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(item.description),
                      onTap: () => _loadFindingIntoForm(index),
                    ),
                  );
                },
              ),

            const SizedBox(height: 20),

            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline, size: 26),
              label: Text(
                'DOKONCIT INSPEKCI (${globalFindings.length} NALEZU)',
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
      appBar: AppBar(title: const Text('Historie inspekcnich reportu')),
      body: savedReports.isEmpty
          ? const Center(
              child: Text('Zatim nebyly dokonceny zadne reporty.', style: TextStyle(color: Colors.grey)),
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
                    title: Text(report.locationName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Pocet nalezu: ${report.findings.length}\nDatum: ${report.date.day}.${report.date.month}.${report.date.year} ${report.date.hour}:${report.date.minute.toString().padLeft(2, '0')}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      globalFindings = List.from(report.findings);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => InspectionModeScreen(locationName: report.locationName),
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

// -----------------------------------------------------------------------------
// 5. REVIZE U STOLU A SPOLEHLIVÉ GENEROVÁNÍ PDF
// -----------------------------------------------------------------------------
class RevisionTableScreen extends StatefulWidget {
  const RevisionTableScreen({Key? key}) : super(key: key);

  @override
  State<RevisionTableScreen> createState() => _RevisionTableScreenState();
}

class _RevisionTableScreenState extends State<RevisionTableScreen> {
  void _editLegislation(Finding finding) {
    TextEditingController legController = TextEditingController(
      text: finding.legislation.isEmpty
          ? getDefaultLegislation(finding.category)
          : finding.legislation,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Upravit legislativu (#${finding.orderNumber})'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nalez: ${finding.description}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: legController,
              decoration: const InputDecoration(
                labelText: 'Cesky zakon / norma',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zrusit')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                finding.legislation = legController.text;
              });
              Navigator.pop(context);
            },
            child: const Text('Ulozit'),
          )
        ],
      ),
    );
  }

  Future<void> _generateAndDownloadPdf() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'EKODAV SAFETY - PROTOKOL BOZP A PO',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
                  ),
                  pw.Text('${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}'),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text('Celkovy pocet nalezu: ${globalFindings.length}', style: const pw.TextStyle(fontSize: 12)),
            pw.Divider(),
            pw.SizedBox(height: 10),
            ...globalFindings.map((f) {
              final leg = f.legislation.isEmpty ? getDefaultLegislation(f.category) : f.legislation;
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 12),
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Nalez #${f.orderNumber} - ${f.category}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                        pw.Text('Zavaznost: ${f.severity}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: f.severity == 'Vysoka' ? PdfColors.red : PdfColors.orange800)),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('Popis: ${f.description}'),
                    pw.SizedBox(height: 4),
                    pw.Text('Zakon / Norma: $leg', style: pw.TextStyle(color: PdfColors.blue900, fontWeight: pw.FontWeight.bold)),
                    if (f.photoBytes != null) ...[
                      pw.SizedBox(height: 8),
                      pw.Container(
                        height: 120,
                        child: pw.Image(pw.MemoryImage(f.photoBytes!), fit: pw.BoxFit.contain),
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
      filename: 'Protokol_BOZP_${DateTime.now().day}_${DateTime.now().month}_${DateTime.now().year}.pdf',
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
            Text('GENERATOR REPORTU', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
              Text('Celkem nalezu: ${globalFindings.length}'),
              Text('Datum vygenerovani: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}'),
              const SizedBox(height: 12),
              const Text('Obsah reportu ke stazeni:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                    final leg = f.legislation.isEmpty ? getDefaultLegislation(f.category) : f.legislation;
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
                              '• #${f.orderNumber} [${f.category}] ${f.description}\n   Norma: $leg',
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
            child: const Text('Zavrit'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('STAHNOUT REPORT (PDF)'),
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
      appBar: AppBar(title: Text('Revize u stolu (${globalFindings.length} nalezu)')),
      body: globalFindings.isEmpty
          ? const Center(child: Text('Zatim nebyly zadane zadne nalezy.'))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: globalFindings.length,
                    itemBuilder: (context, index) {
                      final finding = globalFindings[index];
                      final activeLegislation = finding.legislation.isEmpty
                          ? getDefaultLegislation(finding.category)
                          : finding.legislation;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: finding.photoBytes != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.memory(finding.photoBytes!, width: 40, height: 40, fit: BoxFit.cover),
                                )
                              : CircleAvatar(
                                  backgroundColor: finding.severity == 'Vysoka'
                                      ? Colors.red
                                      : finding.severity == 'Stredni'
                                          ? Colors.orange
                                          : Colors.blue,
                                  child: Text('#${finding.orderNumber}', style: const TextStyle(color: Colors.white)),
                                ),
                          title: Text('${finding.category} • ${finding.severity} zavaznost', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${finding.description}\n📜 Norma: $activeLegislation'),
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