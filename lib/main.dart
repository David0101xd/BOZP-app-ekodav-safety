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

// -----------------------------------------------------------------------------
// POMOCNÁ FUNKCE PRO AUTOMATICKÉ URČENÍ LEGISLATIVY
// -----------------------------------------------------------------------------
String getDefaultLegislation(String category) {
  switch (category) {
    case 'BOZP':
      return 'Zákoník práce č. 262/2006 Sb., NV č. 101/2005 Sb.';
    case 'PO':
      return 'Zákon č. 133/1985 Sb. o PO, Vyhláška č. 246/2001 Sb.';
    case 'Životní prostředí':
      return 'Zákon č. 541/2020 Sb. (odpady), Zákon č. 201/2012 Sb.';
    case 'Technické normy':
      return 'NV č. 378/2001 Sb. (strojní zařízení), ČSN normy';
    case 'Revize a kontroly':
      return 'NV č. 190/2022 Sb., NV č. 194/2022 Sb. (VTZ)';
    case 'Regulatorní školení':
      return 'Zákoník práce č. 262/2006 Sb. (§ 103 odst. 2)';
    case 'ISO':
      return 'ČSN EN ISO 45001 / ISO 14001';
    default:
      return 'Zákoník práce č. 262/2006 Sb.';
  }
}

// -----------------------------------------------------------------------------
// DATOVÉ MODELY (NÁLEZ A REPORT)
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
        title: const Text('EKODAV SAFETY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.shield_outlined, size: 80, color: Color(0xFF0284C7)),
            const SizedBox(height: 10),
            const Text(
              'Inspekce BOZP a PO v terénu',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.grey),
            ),
            const SizedBox(height: 30),

            ElevatedButton.icon(
              icon: const Icon(Icons.add_a_photo, size: 26),
              label: const Text('NOVÝ REPORT (V TERÉNU)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
              label: Text('REVIZE U STOLU (${globalFindings.length} NÁLEZŮ)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
              label: Text('HISTORIE REPORTŮ (${savedReports.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
    'Čerpací stanice Benzina - Praha 4',
    'Skladová hala B - Brno',
    'Továrna Unipetrol - Litvínov'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zadání lokace')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Zadejte název lokace / pracoviště:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _locationController,
              decoration: InputDecoration(
                hintText: 'např. Čerpací stanice, hala, budova...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.location_on),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Nebo vyberte z nedávných navštívených:', style: TextStyle(color: Colors.grey)),
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
              label: const Text('ZAHÁJIT INSPEKCI', style: TextStyle(fontSize: 18)),
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
  String _selectedSeverity = 'Střední';
  final TextEditingController _noteController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  int _editingIndex = -1;
  String _statusMessage = '';

  final List<String> _categories = [
    'BOZP', 'PO', 'Životní prostředí',
    'Technické normy', 'Revize a kontroly',
    'Regulatorní školení', 'ISO'
  ];

  final List<String> _severities = ['Vysoká', 'Střední', 'Nízká', 'Doporučení'];

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
          _statusMessage = '📷 Fotografie úspěšně načtena!';
        });
      }
    } catch (e) {
      try {
        final XFile? galleryFile = await _picker.pickImage(source: ImageSource.gallery);
        if (galleryFile != null) {
          final bytes = await galleryFile.readAsBytes();
          setState(() {
            _currentPhotoBytes = bytes;
            _statusMessage = '📷 Fotografie načtena z galerie!';
          });
        }
      } catch (err) {
        setState(() {
          _statusMessage = '⚠️ Povolte v prohlížeči přístup k fotoaparátu.';
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
              title: const Text('Galerie obrázků'),
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
        existing.description = _noteController.text.isEmpty ? 'Nález bez poznámky' : _noteController.text;
        existing.photoBytes = _currentPhotoBytes;
        existing.isPhotoTaken = _currentPhotoBytes != null;
        if (existing.legislation.isEmpty) {
          existing.legislation = autoLegislation;
        }
        _statusMessage = '⚡ Nález #${existing.orderNumber} aktualizován!';
      } else {
        final newFinding = Finding(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          orderNumber: globalFindings.length + 1,
          category: _selectedCategory,
          severity: _selectedSeverity,
          description: _noteController.text.isEmpty ? 'Nález bez poznámky' : _noteController.text,
          legislation: autoLegislation,
          photoBytes: _currentPhotoBytes,
          isPhotoTaken: _currentPhotoBytes != null,
          timestamp: DateTime.now(),
        );

        globalFindings.add(newFinding);
        _statusMessage = '⚡ Nález #${newFinding.orderNumber} uložen!';
      }

      _resetFormToNew();
    });
  }

  void _resetFormToNew() {
    _editingIndex = -1;
    _currentPhotoBytes = null;
    _noteController.clear();
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
        _statusMessage = 'Načten nález #${finding.orderNumber} k úpravě';
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
            Text('Uloženo nálezů: ${globalFindings.length}', style: const TextStyle(fontSize: 12, color: Colors.greenAccent)),
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
                            Text('1. ŤUKNI PRO VYFOCENÍ / VYBRÁNÍ FOTKY', style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 13)),
                            Text('(Aplikace otevře mobilní fotoaparát)', style: TextStyle(color: Colors.grey, fontSize: 11)),
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
                    title: Text(report.locationName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Počet nálezů: ${report.findings.length}\nDatum: ${report.date.day}.${report.date.month}.${report.date.year} ${report.date.hour}:${report.date.minute.toString().padLeft(2, '0')}'),
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
// 5. REVIZE U STOLU + REÁLNÝ GENERÁTOR A KE STAŽENÍ PDF PROTOKOLU
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

  // REÁLNÉ VYGENEROVÁNÍ A KONTROLA PDF PROTOKOLU
  Future<void> _generateAndDownloadPdf() async {
    final pdf = pw.Document();

    // Načtení české diakritiky z Google Fonts
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(
          base: fontRegular,
          bold: fontBold,
        ),
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
            pw.Text('Celkový počet nálezů: ${globalFindings.length}', style: const pw.TextStyle(fontSize: 12)),
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
                        pw.Text('Nález #${f.orderNumber} • ${f.category}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                        pw.Text('Závažnost: ${f.severity}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: f.severity == 'Vysoká' ? PdfColors.red : PdfColors.orange800)),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('Popis: ${f.description}'),
                    pw.SizedBox(height: 4),
                    pw.Text('Zákon / Norma: $leg', style: pw.TextStyle(color: PdfColors.blue900, fontWeight: pw.FontWeight.bold)),
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

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Protokol_BOZP_${DateTime.now().day}_${DateTime.now().month}_${DateTime.now().year}.pdf',
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
      appBar: AppBar(title: Text('Revize u stolu (${globalFindings.length} nálezů)')),
      body: globalFindings.isEmpty
          ? const Center(child: Text('Zatím nebyly zadané žádné nálezy.'))
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
                                  backgroundColor: finding.severity == 'Vysoká'
                                      ? Colors.red
                                      : finding.severity == 'Střední'
                                          ? Colors.orange
                                          : Colors.blue,
                                  child: Text('#${finding.orderNumber}', style: const TextStyle(color: Colors.white)),
                                ),
                          title: Text('${finding.category} • ${finding.severity} závažnost', style: const TextStyle(fontWeight: FontWeight.bold)),
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