import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isAndroid) {
    AndroidInAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE53935),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE53935),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

// --- DATA MODELS ---

class PdfFile {
  final int id;
  String name;
  String size;
  String date;
  bool isFavorite;
  final String? path;
  final String? base64;
  final int timestamp;
  final FileType fileType;

  PdfFile({
    required this.id,
    required this.name,
    required this.size,
    required this.date,
    this.isFavorite = false,
    this.path,
    this.base64,
    required this.timestamp,
    this.fileType = FileType.device,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'size': size,
    'date': date,
    'isFavorite': isFavorite,
    'path': path,
    'base64': base64,
    'timestamp': timestamp,
    'fileType': fileType.index,
  };

  static PdfFile fromJson(Map<String, dynamic> json) {
    return PdfFile(
      id: json['id'],
      name: json['name'],
      size: json['size'],
      date: json['date'],
      isFavorite: json['isFavorite'] ?? false,
      path: json['path'],
      base64: json['base64'] ?? '',
      timestamp: json['timestamp'],
      fileType: FileType.values[json['fileType'] ?? 0],
    );
  }
}

enum FileType { device, imported, recent, favorite, custom }

// --- MAIN HOME SCREEN ---

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> 
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  int _currentScreenIndex = 0;
  int _currentHomeTabIndex = 0;
  
  List<PdfFile> _recentFiles = [];
  List<PdfFile> _deviceFiles = [];
  List<PdfFile> _favoriteFiles = [];
  List<PdfFile> _importedFiles = [];
  
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<PdfFile> _filteredFiles = [];
  
  bool _isSelectionMode = false;
  Set<int> _selectedFiles = {};
  
  bool _hasFullAccess = false;
  bool _permissionChecked = false;
  bool _showPermissionBlock = false;
  
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _showFabMenu = false;
  
  final ScrollController _scrollController = ScrollController();
  bool _isAppBarVisible = true;
  double _lastScrollOffset = 0;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    
    _scrollController.addListener(_handleScroll);
    
    _checkPermissionAndInitialize();
    _loadData();
  }
  
  void _handleScroll() {
    if (_currentScreenIndex != 0) return;
    
    final currentOffset = _scrollController.offset;
    final isScrollingDown = currentOffset > _lastScrollOffset;
    final isScrollingUp = currentOffset < _lastScrollOffset;
    
    const threshold = 50.0;
    
    if (isScrollingDown && currentOffset > threshold) {
      if (_isAppBarVisible) {
        setState(() {
          _isAppBarVisible = false;
        });
      }
    } else if (isScrollingUp) {
      if (!_isAppBarVisible) {
        setState(() {
          _isAppBarVisible = true;
        });
      }
    }
    
    _lastScrollOffset = currentOffset;
  }
  
  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissionAndInitialize();
      if (_currentScreenIndex == 0 && _currentHomeTabIndex == 1) {
        _scanDeviceFiles();
      }
    }
  }
  
  // ACROBAT STRATEJİSİ: İlk açılışta izin kontrolü
  Future<void> _checkPermissionAndInitialize() async {
    if (Platform.isAndroid) {
      try {
        var status = await Permission.manageExternalStorage.status;
        
        setState(() {
          _hasFullAccess = status.isGranted;
          _permissionChecked = true;
          _showPermissionBlock = !status.isGranted;
        });
        
        if (_hasFullAccess) {
          _scanDeviceFiles();
        }
      } catch (e) {
        print('Permission error: $e');
      }
    } else {
      setState(() {
        _hasFullAccess = true;
        _permissionChecked = true;
      });
    }
  }
  
  Future<void> _requestFullAccess() async {
    if (Platform.isAndroid) {
      var status = await Permission.manageExternalStorage.request();
      
      setState(() {
        _hasFullAccess = status.isGranted;
        _showPermissionBlock = !status.isGranted;
      });
      
      if (_hasFullAccess) {
        _scanDeviceFiles();
      }
    }
  }
  
  Future<void> _openAppSettings() async {
    await openAppSettings();
  }
  
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final recentJson = prefs.getStringList('recent_files') ?? [];
    _recentFiles = recentJson.map((json) => PdfFile.fromJson(jsonDecode(json))).toList();
    
    final favoriteJson = prefs.getStringList('favorite_files') ?? [];
    _favoriteFiles = favoriteJson.map((json) => PdfFile.fromJson(jsonDecode(json))).toList();
    
    final importedJson = prefs.getStringList('imported_files') ?? [];
    _importedFiles = importedJson.map((json) => PdfFile.fromJson(jsonDecode(json))).toList();
    
    _updateFilteredFiles();
  }
  
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setStringList(
      'recent_files',
      _recentFiles.map((file) => jsonEncode(file.toJson())).toList(),
    );
    
    await prefs.setStringList(
      'favorite_files',
      _favoriteFiles.map((file) => jsonEncode(file.toJson())).toList(),
    );
    
    await prefs.setStringList(
      'imported_files',
      _importedFiles.map((file) => jsonEncode(file.toJson())).toList(),
    );
  }
  
  // GELİŞMİŞ TARAMA: Tüm cihazı tarar
  Future<void> _scanDeviceFiles() async {
    if (!_hasFullAccess) return;
    
    try {
      final List<File> pdfFiles = await _getAllDevicePDFs();
      
      setState(() {
        _deviceFiles = pdfFiles.map((file) {
          try {
            final stat = file.statSync();
            return PdfFile(
              id: file.path.hashCode,
              name: _getFileNameFromPath(file.path),
              size: _formatFileSize(stat.size),
              date: _formatFileDate(stat.modified),
              path: file.path,
              timestamp: stat.modified.millisecondsSinceEpoch,
              fileType: FileType.device,
            );
          } catch (e) {
            return PdfFile(
              id: file.path.hashCode,
              name: _getFileNameFromPath(file.path),
              size: '~1 MB',
              date: _getCurrentDate(),
              path: file.path,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              fileType: FileType.device,
            );
          }
        }).toList();
        
        // Dosyaları tarihe göre sırala
        _deviceFiles.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        _updateFilteredFiles();
      });
    } catch (e) {
      print('Scan error: $e');
    }
  }
  
  // Tüm cihazdaki PDF'leri bul (recursive)
  Future<List<File>> _getAllDevicePDFs() async {
    final List<File> pdfFiles = [];
    
    try {
      // Root directory'den başla
      final rootDirs = [
        '/storage/emulated/0',
        if (await Directory('/storage/emulated/1').exists()) '/storage/emulated/1',
        if (await Directory('/sdcard').exists()) '/sdcard',
      ];
      
      for (var rootPath in rootDirs) {
        final rootDir = Directory(rootPath);
        if (await rootDir.exists()) {
          await _scanRecursive(rootDir, pdfFiles);
        }
      }
    } catch (e) {
      print('Get device PDFs error: $e');
    }
    
    return pdfFiles;
  }
  
  // Recursive tarama
  Future<void> _scanRecursive(Directory dir, List<File> pdfFiles) async {
    try {
      final entities = await dir.list().toList();
      
      for (var entity in entities) {
        if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
          pdfFiles.add(entity);
          // Sınır: 500 dosya
          if (pdfFiles.length >= 500) break;
        } else if (entity is Directory) {
          // Bazı sistem klasörlerini atla
          final dirName = path.basename(entity.path);
          if (!_shouldSkipDirectory(dirName)) {
            await _scanRecursive(entity, pdfFiles);
          }
        }
      }
    } catch (e) {
      // Permission hatası olabilir, devam et
      print('Scan directory error: ${dir.path} - $e');
    }
  }
  
  bool _shouldSkipDirectory(String dirName) {
    final skipDirs = [
      'Android', 'LOST.DIR', 'cache', 'Cache', 
      'thumbnails', 'Thumbnails', 'tmp', 'temp'
    ];
    return skipDirs.contains(dirName);
  }
  
  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (math.log(bytes) / math.log(1024)).floor();
    
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }
  
  String _formatFileDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'Bugün ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Dün ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} gün önce';
    } else {
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    }
  }
  
  String _getCurrentDate() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
  }
  
  String _getFileNameFromPath(String filePath) {
    return path.basename(filePath);
  }
  
  void _handleTabChange() {
    if (_tabController.indexIsChanging) {
      setState(() {
        _currentHomeTabIndex = _tabController.index;
        _updateFilteredFiles();
        _scrollToTop();
      });
    }
  }
  
  void _updateFilteredFiles() {
    List<PdfFile> sourceList;
    
    switch (_currentHomeTabIndex) {
      case 0:
        sourceList = _recentFiles;
        break;
      case 1:
        sourceList = [..._deviceFiles, ..._importedFiles];
        break;
      case 2:
        sourceList = _favoriteFiles;
        break;
      default:
        sourceList = [];
    }
    
    if (_searchController.text.isEmpty) {
      _filteredFiles = List.from(sourceList);
    } else {
      final query = _searchController.text.toLowerCase();
      _filteredFiles = sourceList.where((file) {
        return file.name.toLowerCase().contains(query);
      }).toList();
    }
    
    setState(() {});
  }
  
  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _updateFilteredFiles();
      }
    });
  }
  
  void _addToRecent(PdfFile file) {
    setState(() {
      _recentFiles.removeWhere((f) => f.id == file.id);
      _recentFiles.insert(0, PdfFile(
        id: file.id,
        name: file.name,
        size: file.size,
        date: file.date,
        isFavorite: file.isFavorite,
        path: file.path,
        base64: file.base64 ?? '',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        fileType: FileType.recent,
      ));
      
      if (_recentFiles.length > 20) {
        _recentFiles = _recentFiles.sublist(0, 20);
      }
      
      _saveData();
      if (_currentScreenIndex == 0 && _currentHomeTabIndex == 0) {
        _updateFilteredFiles();
      }
    });
  }
  
  void _toggleFavorite(PdfFile file) {
    setState(() {
      file.isFavorite = !file.isFavorite;
      
      if (file.isFavorite) {
        if (!_favoriteFiles.any((f) => f.id == file.id)) {
          _favoriteFiles.insert(0, PdfFile(
            id: file.id,
            name: file.name,
            size: file.size,
            date: file.date,
            isFavorite: true,
            path: file.path,
            base64: file.base64 ?? '',
            timestamp: DateTime.now().millisecondsSinceEpoch,
            fileType: FileType.favorite,
          ));
        }
      } else {
        _favoriteFiles.removeWhere((f) => f.id == file.id);
      }
      
      _updateFileInList(_recentFiles, file);
      _updateFileInList(_deviceFiles, file);
      _updateFileInList(_importedFiles, file);
      
      _saveData();
      if (_currentScreenIndex == 0) {
        _updateFilteredFiles();
      }
    });
  }
  
  void _updateFileInList(List<PdfFile> list, PdfFile updatedFile) {
    final index = list.indexWhere((f) => f.id == updatedFile.id);
    if (index != -1) {
      list[index] = updatedFile;
    }
  }
  
  // FAB'dan PDF Yükle (izin olmadan da çalışır)
  Future<void> _importPDF() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowedExtensions: ['pdf'],
        allowMultiple: true,
        type: FileType.custom,
      );
      
      if (result != null && result.files.isNotEmpty) {
        for (var platformFile in result.files) {
          String? base64Data;
          
          if (platformFile.path != null) {
            final sourceFile = File(platformFile.path!);
            final bytes = await sourceFile.readAsBytes();
            base64Data = base64Encode(bytes);
          } else if (platformFile.bytes != null) {
            base64Data = base64Encode(platformFile.bytes!);
          }
          
          if (base64Data != null) {
            final newFile = PdfFile(
              id: DateTime.now().millisecondsSinceEpoch + platformFile.hashCode,
              name: platformFile.name,
              size: _formatFileSize(platformFile.size),
              date: _getCurrentDate(),
              base64: base64Data,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              fileType: FileType.imported,
            );
            
            setState(() {
              _importedFiles.insert(0, newFile);
              _addToRecent(newFile);
              
              // Cihazda sekmesine geç
              if (_currentScreenIndex != 0 || _currentHomeTabIndex != 1) {
                _currentScreenIndex = 0;
                _currentHomeTabIndex = 1;
                _tabController.animateTo(1);
              } else {
                _updateFilteredFiles();
              }
            });
          }
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result.files.length} dosya başarıyla yüklendi')),
        );
      }
    } catch (e) {
      print('Import error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dosya yüklenirken hata oluştu')),
      );
    }
  }
  
  // ACROBAT'ın dosya seçme ekranı gibi
  Future<void> _openFilePicker() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowedExtensions: ['pdf'],
        allowMultiple: true,
        type: FileType.custom,
      );
      
      if (result != null && result.files.isNotEmpty) {
        for (var platformFile in result.files) {
          if (platformFile.path != null) {
            final file = File(platformFile.path!);
            final stat = await file.stat();
            
            final newFile = PdfFile(
              id: file.path.hashCode,
              name: platformFile.name,
              size: _formatFileSize(stat.size),
              date: _formatFileDate(stat.modified),
              path: file.path,
              timestamp: stat.modified.millisecondsSinceEpoch,
              fileType: FileType.device,
            );
            
            // Cihaz dosyalarına ekle (izinsiz görünmeyecek)
            if (!_deviceFiles.any((f) => f.id == newFile.id)) {
              setState(() {
                _deviceFiles.add(newFile);
                _addToRecent(newFile);
              });
            }
            
            // PDF'i hemen aç
            _openPDFViewer(newFile);
          }
        }
      }
    } catch (e) {
      print('File picker error: $e');
    }
  }
  
  Future<void> _openPDFViewer(PdfFile file) async {
    _addToRecent(file);
    
    try {
      // PDF verisini hazırla
      String base64Data;
      
      if (file.base64 != null) {
        base64Data = file.base64!;
      } else if (file.path != null) {
        final fileBytes = await File(file.path!).readAsBytes();
        base64Data = base64Encode(fileBytes);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF verisi bulunamadı')),
        );
        return;
      }
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PDFViewerScreen(
            pdfFile: file,
            base64Data: base64Data,
            fileName: file.name,
          ),
        ),
      );
    } catch (e) {
      print('PDF açma hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF açılamadı: ${e.toString()}')),
      );
    }
  }
  
  Widget _buildPDFCard(PdfFile file, int index) {
    final theme = Theme.of(context);
    final isSelected = _selectedFiles.contains(file.id);
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isSelected ? theme.primaryColor.withOpacity(0.1) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? theme.primaryColor : theme.dividerColor,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (_isSelectionMode) {
            setState(() {
              if (_selectedFiles.contains(file.id)) {
                _selectedFiles.remove(file.id);
              } else {
                _selectedFiles.add(file.id);
              }
              if (_selectedFiles.isEmpty) {
                _isSelectionMode = false;
              }
            });
          } else {
            _openPDFViewer(file);
          }
        },
        onLongPress: () {
          setState(() {
            _isSelectionMode = true;
            _selectedFiles.add(file.id);
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (_isSelectionMode)
                Checkbox(
                  value: _selectedFiles.contains(file.id),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedFiles.add(file.id);
                      } else {
                        _selectedFiles.remove(file.id);
                      }
                    });
                  },
                ),
              
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.picture_as_pdf,
                  color: theme.primaryColor,
                  size: 32,
                ),
              ),
              
              const SizedBox(width: 12),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          file.size,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.textTheme.bodySmall?.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          file.date,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              IconButton(
                onPressed: () => _toggleFavorite(file),
                icon: Icon(
                  file.isFavorite ? Icons.star : Icons.star_border,
                  color: file.isFavorite ? Colors.amber : theme.iconTheme.color,
                ),
              ),
              
              if (!_isSelectionMode)
                PopupMenuButton(
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      child: Text('Paylaş'),
                    ),
                    const PopupMenuItem(
                      child: Text('Yeniden Adlandır'),
                    ),
                    PopupMenuItem(
                      child: const Text('Sil', style: TextStyle(color: Colors.red)),
                      onTap: () {
                        _deleteFile(file);
                      },
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _deleteFile(PdfFile file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sil'),
        content: Text('"${file.name}" dosyasını silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _recentFiles.removeWhere((f) => f.id == file.id);
                _deviceFiles.removeWhere((f) => f.id == file.id);
                _importedFiles.removeWhere((f) => f.id == file.id);
                _favoriteFiles.removeWhere((f) => f.id == file.id);
                _selectedFiles.remove(file.id);
                _updateFilteredFiles();
                _saveData();
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('"${file.name}" silindi')),
              );
            },
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
  
  // ACROBAT GİBİ İZİN BLOKLAYICI EKRANI
  Widget _buildPermissionBlockScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 60),
              Icon(
                Icons.folder_open,
                size: 120,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 40),
              Text(
                'Dosyalarınıza erişim izni verin',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Lütfen dosyalarınıza erişim izni verin\nAyarlar\'dan erişin.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 60),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _requestFullAccess,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'AYARLARDAN İZİN VER',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    // ACROBAT gibi: Şimdi değil (sadece FAB'dan PDF yükle)
                    setState(() {
                      _showPermissionBlock = false;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[600],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Colors.grey[300]!),
                  ),
                  child: const Text(
                    'Şimdi değil',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const Spacer(),
              // Alt navigasyon (Acrobat'taki gibi)
              Container(
                height: 56,
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildBottomNavItem(Icons.home, 'Ana Sayfa', true),
                    _buildBottomNavItem(Icons.create, 'Oluştur', false),
                    _buildBottomNavItem(Icons.folder, 'Dosyalar', false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildBottomNavItem(IconData icon, String label, bool isActive) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          color: isActive ? const Color(0xFFE53935) : Colors.grey[500],
          size: 24,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? const Color(0xFFE53935) : Colors.grey[500],
          ),
        ),
      ],
    );
  }
  
  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 64,
            color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    // ACROBAT STRATEJİSİ: İzin yoksa bloklayıcı ekran göster
    if (_showPermissionBlock) {
      return _buildPermissionBlockScreen();
    }
    
    return Scaffold(
      key: _scaffoldKey,
      appBar: _currentScreenIndex == 0 ? 
        (_isSearching ? _buildSearchAppBar() : _buildMainAppBar()) : 
        _buildSimpleAppBar(),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNavBar(),
      floatingActionButton: _currentScreenIndex == 0 ? _buildFAB() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
  
  AppBar _buildMainAppBar() {
    return AppBar(
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('PDF Reader'),
        ],
      ),
      actions: [
        if (_isSelectionMode) ...[
          IconButton(
            onPressed: () {
              setState(() {
                _selectedFiles.clear();
                _isSelectionMode = false;
              });
            },
            icon: const Icon(Icons.close),
          ),
          Text('${_selectedFiles.length} seçildi'),
          const SizedBox(width: 8),
        ] else ...[
          IconButton(
            onPressed: _toggleSearch,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: const Icon(Icons.menu),
          ),
        ],
      ],
      bottom: _isAppBarVisible
          ? TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.history), text: 'Son'),
                Tab(icon: Icon(Icons.phone_iphone), text: 'Cihazda'),
                Tab(icon: Icon(Icons.star), text: 'Favoriler'),
              ],
            )
          : null,
    );
  }
  
  AppBar _buildSimpleAppBar() {
    String title;
    switch (_currentScreenIndex) {
      case 1:
        title = 'Araçlar';
        break;
      case 2:
        title = 'Dosyalar';
        break;
      default:
        title = 'PDF Reader';
    }
    
    return AppBar(
      title: Text(title),
      actions: [
        IconButton(
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          icon: const Icon(Icons.menu),
        ),
      ],
    );
  }
  
  AppBar _buildSearchAppBar() {
    return AppBar(
      leading: IconButton(
        onPressed: _toggleSearch,
        icon: const Icon(Icons.arrow_back),
      ),
      title: TextField(
        controller: _searchController,
        decoration: const InputDecoration(
          hintText: 'PDF Ara...',
          border: InputBorder.none,
        ),
        autofocus: true,
        onChanged: (value) => _updateFilteredFiles(),
      ),
      actions: [
        if (_searchController.text.isNotEmpty)
          IconButton(
            onPressed: () {
              _searchController.clear();
              _updateFilteredFiles();
            },
            icon: const Icon(Icons.clear),
          ),
      ],
    );
  }
  
  Widget _buildBody() {
    switch (_currentScreenIndex) {
      case 0:
        return _buildHomeScreen();
      case 1:
        return _buildToolsGrid();
      case 2:
        return _buildCloudServicesList();
      default:
        return Container();
    }
  }
  
  Widget _buildHomeScreen() {
    return Column(
      children: [
        if (!_isAppBarVisible && _currentScreenIndex == 0)
          Container(
            color: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.history), text: 'Son'),
                Tab(icon: Icon(Icons.phone_iphone), text: 'Cihazda'),
                Tab(icon: Icon(Icons.star), text: 'Favoriler'),
              ],
            ),
          ),
        
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildRecentTab(),
              _buildDeviceTab(),
              _buildFavoritesTab(),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildRecentTab() {
    if (_filteredFiles.isEmpty) {
      return _buildEmptyState('Henüz dosya yok');
    }
    
    return ListView.builder(
      controller: _scrollController,
      itemCount: _filteredFiles.length,
      itemBuilder: (context, index) {
        return _buildPDFCard(_filteredFiles[index], index);
      },
    );
  }
  
  Widget _buildDeviceTab() {
    if (!_permissionChecked) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (!_hasFullAccess) {
      return _buildEmptyState('Cihazdaki PDF\'leri görmek için izin verin');
    }
    
    if (_filteredFiles.isEmpty) {
      return RefreshIndicator(
        onRefresh: _scanDeviceFiles,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            _buildEmptyState('Cihazınızda PDF bulunamadı'),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _scanDeviceFiles,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _filteredFiles.length,
        itemBuilder: (context, index) {
          return _buildPDFCard(_filteredFiles[index], index);
        },
      ),
    );
  }
  
  Widget _buildFavoritesTab() {
    if (_filteredFiles.isEmpty) {
      return _buildEmptyState('Henüz favori dosyanız yok');
    }
    
    return ListView.builder(
      controller: _scrollController,
      itemCount: _filteredFiles.length,
      itemBuilder: (context, index) {
        return _buildPDFCard(_filteredFiles[index], index);
      },
    );
  }
  
  Widget _buildBottomNavBar() {
    return BottomNavigationBar(
      currentIndex: _currentScreenIndex,
      onTap: (index) {
        setState(() {
          _currentScreenIndex = index;
          _isSearching = false;
          _isSelectionMode = false;
          _selectedFiles.clear();
          _isAppBarVisible = true;
        });
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Ana Sayfa',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.tune),
          label: 'Araçlar',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.folder),
          label: 'Dosyalar',
        ),
      ],
    );
  }
  
  Widget _buildFAB() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showFabMenu) ...[
          // ACROBAT gibi: "Dosya aç" seçeneği
          _buildFABMenuItem(
            icon: Icons.folder_open,
            label: 'Dosya aç',
            onTap: () {
              setState(() => _showFabMenu = false);
              _openFilePicker();
            },
          ),
          const SizedBox(height: 8),
          _buildFABMenuItem(
            icon: Icons.upload_file,
            label: 'PDF Yükle',
            onTap: () {
              setState(() => _showFabMenu = false);
              _importPDF();
            },
          ),
          const SizedBox(height: 8),
          if (!_hasFullAccess)
            _buildFABMenuItem(
              icon: Icons.settings,
              label: 'İzin ver',
              onTap: () {
                setState(() => _showFabMenu = false);
                _requestFullAccess();
              },
            ),
        ],
        FloatingActionButton(
          onPressed: () {
            setState(() => _showFabMenu = !_showFabMenu);
          },
          backgroundColor: Theme.of(context).primaryColor,
          child: Icon(_showFabMenu ? Icons.close : Icons.add),
        ),
      ],
    );
  }
  
  Widget _buildFABMenuItem({required IconData icon, required String label, required VoidCallback onTap}) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 12),
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // Tools Grid (Basitleştirilmiş)
  Widget _buildToolsGrid() {
    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 2,
      childAspectRatio: 1.2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      children: const [
        _ToolCard(title: 'PDF Birleştir', icon: Icons.merge, color: Color(0xFFE53935)),
        _ToolCard(title: 'Sesli Okuma', icon: Icons.volume_up, color: Color(0xFF4CAF50)),
        _ToolCard(title: 'OCR Metin Çıkar', icon: Icons.text_fields, color: Color(0xFF2196F3)),
        _ToolCard(title: 'PDF İmzala', icon: Icons.draw, color: Color(0xFF9C27B0)),
      ],
    );
  }
  
  Widget _buildCloudServicesList() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ListTile(
          leading: Icon(Icons.cloud, color: Color(0xFF4285F4)),
          title: Text('Google Drive'),
          trailing: Icon(Icons.chevron_right),
        ),
        ListTile(
          leading: Icon(Icons.cloud, color: Color(0xFF0078D4)),
          title: Text('OneDrive'),
          trailing: Icon(Icons.chevron_right),
        ),
        ListTile(
          leading: Icon(Icons.cloud, color: Color(0xFF0061FF)),
          title: Text('Dropbox'),
          trailing: Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _ToolCard({
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// PDF Viewer Screen (Basitleştirilmiş)
class PDFViewerScreen extends StatefulWidget {
  final PdfFile pdfFile;
  final String base64Data;
  final String fileName;

  const PDFViewerScreen({
    super.key,
    required this.pdfFile,
    required this.base64Data,
    required this.fileName,
  });

  @override
  State<PDFViewerScreen> createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends State<PDFViewerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {},
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.picture_as_pdf,
              size: 100,
              color: Colors.red,
            ),
            const SizedBox(height: 20),
            Text(
              'PDF Viewer: ${widget.fileName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Boyut: ${widget.pdfFile.size}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                // PDF görüntüleme işlevi buraya eklenecek
              },
              child: const Text('PDF\'i Aç'),
            ),
          ],
        ),
      ),
    );
  }
}
