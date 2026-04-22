import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/error_code.dart';
import '../services/database_service.dart';
import '../services/ocr_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<String> _robotModels = <String>[
    'YRC1000',
    'YRC1000micro',
    'DX200',
  ];

  final OcrService _ocrService = OcrService();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _solutionController = TextEditingController();
  final TextEditingController _expertNoteController = TextEditingController();
  final TextEditingController _weldingSearchController =
      TextEditingController();
  final TextEditingController _ioSearchController = TextEditingController();
  final TextEditingController _dbSearchController = TextEditingController();
  CameraController? _cameraController;
  Timer? _scanTimer;

  bool _isInitializing = true;
  bool _isScanning = false;
  bool _isBottomSheetOpen = false;
  bool _isSaving = false;
  String _statusText = 'Sistem baslatiliyor...';
  String? _lastDetectedCode;
  String _lastScanTime = '-';
  List<ErrorCode> _records = <ErrorCode>[];
  String _selectedModel = _robotModels.first;
  String _weldingQuery = '';
  String _ioQuery = '';
  String _dbQuery = '';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      setState(() {
        _statusText = 'Veritabani kontrol ediliyor...';
      });
      await DatabaseService.instance.initialize();
      await _loadRecords();

      setState(() {
        _statusText = 'Kamera izinleri ve onizleme hazirlaniyor...';
      });
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      _startScanning();

      if (!mounted) {
        return;
      }
      setState(() {
        _isInitializing = false;
        _statusText = 'Tarama aktif. ALARM/ERROR kodu bekleniyor.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isInitializing = false;
        _statusText = 'Baslatma hatasi: $e';
      });
    }
  }

  Future<void> _loadRecords() async {
    final records = await DatabaseService.instance.getAllErrorCodes();
    if (!mounted) {
      return;
    }
    setState(() {
      _records = records;
    });
  }

  void _startScanning() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _scanCurrentFrame(),
    );
  }

  Future<void> _scanCurrentFrame() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (_isScanning || _isBottomSheetOpen || controller.value.isTakingPicture) {
      return;
    }

    _isScanning = true;
    try {
      final image = await controller.takePicture();
      final text = await _ocrService.scanTextFromImagePath(image.path);
      final detectedCode = _ocrService.detectErrorCode(text);
      _lastScanTime = DateFormat('HH:mm:ss').format(DateTime.now());

      if (!mounted) {
        return;
      }

      if (detectedCode == null) {
        setState(() {
          _statusText = 'Kod bulunamadi. Tarama suruyor...';
        });
        return;
      }

      final errorData = await DatabaseService.instance.findByCode(detectedCode);
      if (errorData == null) {
        setState(() {
          _statusText = '$detectedCode bulundu fakat veritabani eslesmesi yok.';
        });
        return;
      }

      if (_lastDetectedCode == errorData.code) {
        setState(() {
          _statusText = 'Ayni kod tekrar algilandi: ${errorData.code}';
        });
        return;
      }

      _lastDetectedCode = errorData.code;
      setState(() {
        _statusText = 'Kod algilandi: ${errorData.code}';
      });

      await HapticFeedback.mediumImpact();
      await _showResultSheet(errorData);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Tarama hatasi: $e';
      });
    } finally {
      _isScanning = false;
    }
  }

  Future<void> _showResultSheet(ErrorCode errorData) async {
    if (!mounted) {
      return;
    }
    _isBottomSheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 60,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Text(
                  errorData.code,
                  style: const TextStyle(
                    color: Color(0xFF005691),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  errorData.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                _InfoBlock(title: 'Aciklama', body: errorData.description),
                _InfoBlock(title: 'Resmi Cozum', body: errorData.solution),
                _InfoBlock(title: 'Uzman Notu', body: errorData.expertNote),
              ],
            ),
          ),
        );
      },
    );
    _isBottomSheetOpen = false;
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _cameraController?.dispose();
    _ocrService.dispose();
    _codeController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _solutionController.dispose();
    _expertNoteController.dispose();
    _weldingSearchController.dispose();
    _ioSearchController.dispose();
    _dbSearchController.dispose();
    super.dispose();
  }

  Future<void> _saveRecord() async {
    final code = _codeController.text.trim().toUpperCase();
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final solution = _solutionController.text.trim();
    final expertNote = _expertNoteController.text.trim();

    if (code.isEmpty ||
        title.isEmpty ||
        description.isEmpty ||
        solution.isEmpty ||
        expertNote.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tum alanlari doldurman gerekiyor.'),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });
    await DatabaseService.instance.upsertErrorCode(
      ErrorCode(
        code: code,
        title: title,
        description: description,
        solution: solution,
        expertNote: expertNote,
      ),
    );
    await _loadRecords();

    if (!mounted) {
      return;
    }
    setState(() {
      _isSaving = false;
    });
    _codeController.clear();
    _titleController.clear();
    _descriptionController.clear();
    _solutionController.clear();
    _expertNoteController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Kayit basariyla veritabanina eklendi.'),
      ),
    );
  }

  Future<void> _deleteRecord(ErrorCode record) async {
    await DatabaseService.instance.deleteByCode(record.code);
    await _loadRecords();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${record.code} kaydi silindi.')),
    );
  }

  Future<void> _openEditDialog(ErrorCode record) async {
    final codeController = TextEditingController(text: record.code);
    final titleController = TextEditingController(text: record.title);
    final descriptionController = TextEditingController(text: record.description);
    final solutionController = TextEditingController(text: record.solution);
    final expertController = TextEditingController(text: record.expertNote);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Kaydi Duzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _Field(controller: codeController, label: 'Code'),
                const SizedBox(height: 8),
                _Field(controller: titleController, label: 'Title'),
                const SizedBox(height: 8),
                _Field(
                  controller: descriptionController,
                  label: 'Description',
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                _Field(
                  controller: solutionController,
                  label: 'Solution',
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                _Field(
                  controller: expertController,
                  label: 'Expert Note',
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Iptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );

    if (saved != true) {
      codeController.dispose();
      titleController.dispose();
      descriptionController.dispose();
      solutionController.dispose();
      expertController.dispose();
      return;
    }

    await DatabaseService.instance.upsertErrorCode(
      ErrorCode(
        code: codeController.text.trim().toUpperCase(),
        title: titleController.text.trim(),
        description: descriptionController.text.trim(),
        solution: solutionController.text.trim(),
        expertNote: expertController.text.trim(),
      ),
    );
    await _loadRecords();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kayit guncellendi.')),
      );
    }

    codeController.dispose();
    titleController.dispose();
    descriptionController.dispose();
    solutionController.dispose();
    expertController.dispose();
  }

  List<String> _weldingItemsForModel() {
    const map = <String, List<String>>{
      'YRC1000': <String>[
        'Topraklama kablosu ve kaynak sasesi kontrol edilir.',
        'Weld source handshake bitleri test edilir.',
        'Job cagrisi ile kaynak parametreleri dogrulanir.',
      ],
      'YRC1000micro': <String>[
        'Kompakt panelde guc modulu fan ve sicaklik izlenir.',
        'Torc kablo bukkum yaricapi mikro hucreye uygun ayarlanir.',
        'Daha dusuk akim senaryolari icin test pencesi yapilir.',
      ],
      'DX200': <String>[
        'DX200 I/F karti ve relay cikislari tek tek dogrulanir.',
        'Legacy weld package parametre eslesmeleri kontrol edilir.',
        'Pendantte alarm reset ve welding ready akisi test edilir.',
      ],
    };
    return map[_selectedModel] ?? const <String>[];
  }

  List<String> _ioItemsForModel() {
    const map = <String, List<String>>{
      'YRC1000': <String>[
        'DI Arc Start izin biti PLC ile senkron olmalidir.',
        'DO Gas On cikisi ile solenoid cevabi olculmelidir.',
        'Fault reset pulse suresi 200ms ustu denenmelidir.',
      ],
      'YRC1000micro': <String>[
        'Mikro hucre emniyet switchleri zincir testi yapilir.',
        'Wire feed enable cikisi robot cycle ile karsilastirilir.',
        'I/O monitor ekraninda edge gecisleri izlenir.',
      ],
      'DX200': <String>[
        'Universal input mapping tablosu sahadaki kabloya gore esitlenir.',
        'DO/DI adresleri eski yedek ile karsilastirilir.',
        'PLC handshake timeout suresi alarm logu ile dogrulanir.',
      ],
    };
    return map[_selectedModel] ?? const <String>[];
  }

  List<String> _filterTextItems(List<String> input, String query) {
    if (query.trim().isEmpty) {
      return input;
    }
    final q = query.toLowerCase();
    return input.where((item) => item.toLowerCase().contains(q)).toList();
  }

  List<ErrorCode> _filteredRecords() {
    if (_dbQuery.trim().isEmpty) {
      return _records;
    }
    final q = _dbQuery.toLowerCase();
    return _records.where((record) {
      return record.code.toLowerCase().contains(q) ||
          record.title.toLowerCase().contains(q) ||
          record.description.toLowerCase().contains(q);
    }).toList();
  }

  Widget _buildModelSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF005691), width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedModel,
          isExpanded: true,
          iconEnabledColor: const Color(0xFF005691),
          items: _robotModels
              .map(
                (model) => DropdownMenuItem<String>(
                  value: model,
                  child: Text('Robot Modeli: $model'),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _selectedModel = value;
            });
          },
        ),
      ),
    );
  }

  Widget _buildScannerTab() {
    return _isInitializing
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(color: Color(0xFF005691)),
                  const SizedBox(height: 12),
                  Text(
                    _statusText,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        : Column(
            children: <Widget>[
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.black,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _cameraController != null &&
                          _cameraController!.value.isInitialized
                      ? CameraPreview(_cameraController!)
                      : const Center(
                          child: Text(
                            'Kamera kullanilamiyor.',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                ),
              ),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF005691), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Tarama Durumu',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF005691),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_statusText),
                    const SizedBox(height: 4),
                    Text(
                      'Son tarama saati: $_lastScanTime',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ],
          );
  }

  Widget _buildWeldingSetupTab() {
    final dynamicItems = _filterTextItems(_weldingItemsForModel(), _weldingQuery);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        _SectionHeader(
          title: 'Kaynak Kurulum Rehberi',
          subtitle: 'Secili modele gore devreye alma adimlari',
        ),
        const SizedBox(height: 8),
        _Field(
          controller: _weldingSearchController,
          label: 'Kurulum adimlarinda ara',
          onChanged: (value) => setState(() => _weldingQuery = value),
        ),
        const SizedBox(height: 12),
        const _CheckCard(
          title: 'Guc ve emniyet hazirligi',
          items: <String>[
            'Topraklama kablosu dogru bagli mi kontrol et.',
            'Kaynak makinesi giris gerilimi nominal degerde olmalı.',
            'Acil stop zinciri ve emniyet roleleri test edilmeli.',
          ],
        ),
        const _CheckCard(
          title: 'Mekanik kurulum adimlari',
          items: <String>[
            'Torcu sabitle ve kablo bukum yaricapini koru.',
            'Tel surme unitesini kablo boyuna gore kalibre et.',
            'Gaz regulatoru ve debi degerini proses tipine gore ayarla.',
          ],
        ),
        const _CheckCard(
          title: 'Parametre dogrulama',
          items: <String>[
            'Weld job no, akim ve voltaj referanslarini dogrula.',
            'Robot hizlari ve weave parametrelerini test et.',
            'Deneme puntosu alip cizgi stabilitesini gozlemle.',
          ],
        ),
        _CheckCard(
          title: 'Model Bazli Kurulum ($_selectedModel)',
          items: dynamicItems,
        ),
      ],
    );
  }

  Widget _buildIoTab() {
    final dynamicItems = _filterTextItems(_ioItemsForModel(), _ioQuery);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        _SectionHeader(
          title: 'I/O Baglanti Paneli',
          subtitle: 'Sinyal dogrulama ve saha test listesi',
        ),
        const SizedBox(height: 8),
        _Field(
          controller: _ioSearchController,
          label: 'I/O adimlarinda ara',
          onChanged: (value) => setState(() => _ioQuery = value),
        ),
        const SizedBox(height: 12),
        const _CheckCard(
          title: 'Dijital girisler (DI)',
          items: <String>[
            'Arc start onayi (DI) sinyali aktif mi kontrol et.',
            'Torch collision sinyali normal durumda LOW olmali.',
            'Kapak/kapak switchleri guvenlik PLC tarafinda dogrulanmali.',
          ],
        ),
        const _CheckCard(
          title: 'Dijital cikislar (DO)',
          items: <String>[
            'Wire feed enable (DO) tetikleniyor mu izle.',
            'Gas on (DO) cikisinda role tepkisi kontrol edilmeli.',
            'Fault reset (DO) pulse suresi parametreye uygun olmali.',
          ],
        ),
        const _CheckCard(
          title: 'I/O test proseduru',
          items: <String>[
            'Pendant I/O monitor ekranindan sinyalleri canli izle.',
            'PLC ile handshake bitleri tek tek test edilmeli.',
            'Hata halinde fiziksel soket, pinout ve kablo surekliligi olc.',
          ],
        ),
        _CheckCard(
          title: 'Model Bazli I/O Kontrol ($_selectedModel)',
          items: dynamicItems,
        ),
      ],
    );
  }

  Widget _buildDatabaseTab() {
    final filtered = _filteredRecords();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        const _SectionHeader(
          title: 'RAM Database Yonetimi',
          subtitle: 'Kayit ekle, guncelle, ara ve sil',
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF005691), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Database Kayit Paneli',
                style: TextStyle(
                  color: Color(0xFF005691),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              _Field(controller: _codeController, label: 'Code (orn. ALARM 4107)'),
              const SizedBox(height: 8),
              _Field(controller: _titleController, label: 'Title'),
              const SizedBox(height: 8),
              _Field(controller: _descriptionController, label: 'Description', maxLines: 3),
              const SizedBox(height: 8),
              _Field(controller: _solutionController, label: 'Solution', maxLines: 3),
              const SizedBox(height: 8),
              _Field(controller: _expertNoteController, label: 'Expert Note', maxLines: 3),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSaving ? null : _saveRecord,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF005691),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_isSaving ? 'Kaydediliyor...' : 'Veriyi Kaydet'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Toplam kayit: ${_records.length} | Filtrelenen: ${filtered.length}',
                style: const TextStyle(
                  color: Color(0xFF005691),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              _Field(
                controller: _dbSearchController,
                label: 'Kayitlarda ara (code/title/description)',
                onChanged: (value) => setState(() => _dbQuery = value),
              ),
              const SizedBox(height: 10),
              if (filtered.isEmpty)
                const Text('Henuz kayit yok.')
              else
                ...filtered.take(20).map(
                      (record) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          tileColor: const Color(0xFFF5F8FB),
                          title: Text(record.code),
                          subtitle: Text(record.title),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              IconButton(
                                tooltip: 'Duzenle',
                                onPressed: () => _openEditDialog(record),
                                icon: const Icon(Icons.edit, size: 20),
                              ),
                              IconButton(
                                tooltip: 'Sil',
                                onPressed: () => _deleteRecord(record),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                  color: Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F8FB),
        appBar: AppBar(
          title: const Text('RAM Service Panel'),
          backgroundColor: const Color(0xFF005691),
          foregroundColor: Colors.white,
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            tabs: <Widget>[
              Tab(text: 'Kaynak Kurulum'),
              Tab(text: 'I/O Baglantilari'),
              Tab(text: 'Kamera Tarama'),
              Tab(text: 'Database'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            Column(
              children: <Widget>[
                _buildModelSelector(),
                Expanded(child: _buildWeldingSetupTab()),
              ],
            ),
            Column(
              children: <Widget>[
                _buildModelSelector(),
                Expanded(child: _buildIoTab()),
              ],
            ),
            _buildScannerTab(),
            _buildDatabaseTab(),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF005691), Color(0xFF0A77BC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({
    required this.title,
    required this.items,
  });

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF005691), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF005691),
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('• '),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF005691),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(body),
        ],
      ),
    );
  }
}
