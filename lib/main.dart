import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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
        primaryColor: const Color(0xFFE53935),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE53935),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        primaryColor: const Color(0xFFE53935),
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
      base64: json['base64'],
      timestamp: json['timestamp'],
      fileType: FileType.values[json['fileType'] ?? 0],
    );
  }
}

enum FileType { device, imported, recent, favorite }

class ToolItem {
  final int id;
  final String title;
  final IconData icon;
  final Color color;
  final String page;

  ToolItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.page,
  });
}

class CloudService {
  final int id;
  final String name;
  final IconData icon;
  final Color color;
  final String serviceType;

  CloudService({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.serviceType,
  });
}

// --- MAIN HOME SCREEN ---

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> 
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  int _currentScreenIndex = 0; // 0: Ana Sayfa, 1: Araçlar, 2: Dosyalar
  int _currentHomeTabIndex = 0; // 0: Son, 1: Cihazda, 2: Favoriler
  
  // Data Lists
  List<PdfFile> _recentFiles = [];
  List<PdfFile> _deviceFiles = [];
  List<PdfFile> _favoriteFiles = [];
  List<PdfFile> _importedFiles = [];
  
  // UI State
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<PdfFile> _filteredFiles = [];
  
  bool _isSelectionMode = false;
  Set<int> _selectedFiles = {};
  
  // Permission
  bool _hasPermission = false;
  bool _permissionChecked = false;
  
  // Drawer State
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  // FAB Menu
  bool _showFabMenu = false;
  
  // Connectivity
  bool _isConnected = true;
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  
  // Scroll Controller for Hide/Show AppBar
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
    
    _initConnectivity();
    _checkPermission();
    _loadData();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _connectivitySubscription.cancel();
    super.dispose();
  }
  
  void _handleScroll() {
    if (_currentScreenIndex != 0) return; // Sadece Ana Sayfa'da
    
    final currentOffset = _scrollController.offset;
    final isScrollingDown = currentOffset > _lastScrollOffset;
    final isScrollingUp = currentOffset < _lastScrollOffset;
    
    // Minimum scroll mesafesi
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
      if (_currentScreenIndex == 0 && _currentHomeTabIndex == 1) {
        _scanDeviceFiles();
      }
    }
  }
  
  void _initConnectivity() {
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((ConnectivityResult result) {
      setState(() {
        _isConnected = result != ConnectivityResult.none;
      });
    });
  }
  
  Future<void> _checkPermission() async {
    if (Platform.isAndroid) {
      try {
        var status = await Permission.manageExternalStorage.status;
        setState(() {
          _hasPermission = status.isGranted;
          _permissionChecked = true;
        });
        
        if (_hasPermission && _deviceFiles.isEmpty) {
          _scanDeviceFiles();
        }
      } catch (e) {
        print('Permission error: $e');
      }
    } else {
      setState(() {
        _hasPermission = true;
        _permissionChecked = true;
      });
    }
  }
  
  Future<void> _requestPermission() async {
    if (Platform.isAndroid) {
      var status = await Permission.manageExternalStorage.request();
      setState(() {
        _hasPermission = status.isGranted;
      });
      
      if (_hasPermission) {
        _scanDeviceFiles();
      } else {
        _openAppSettings();
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
  
  Future<void> _scanDeviceFiles() async {
    if (!_hasPermission) return;
    
    try {
      final List<Map<String, String>> pdfs = await _getDevicePDFs();
      
      setState(() {
        _deviceFiles = pdfs.map((pdf) {
          return PdfFile(
            id: DateTime.now().millisecondsSinceEpoch + (pdf.hashCode & 0x7FFFFFFF),
            name: _getFileNameFromPath(pdf['path'] ?? ''),
            size: pdf['size'] ?? '0 B',
            date: pdf['date'] ?? '',
            path: pdf['path'],
            timestamp: DateTime.now().millisecondsSinceEpoch,
            fileType: FileType.device,
          );
        }).toList();
        
        _updateFilteredFiles();
      });
    } catch (e) {
      print('Scan error: $e');
    }
  }
  
  Future<List<Map<String, String>>> _getDevicePDFs() async {
    final List<Map<String, String>> pdfFiles = [];
    
    try {
      final List<String> directories = [
        '/storage/emulated/0/',
        '/sdcard/',
        '/storage/emulated/0/Download/',
        '/storage/emulated/0/Documents/',
      ];
      
      for (var dirPath in directories) {
        try {
          final dir = Directory(dirPath);
          if (await dir.exists()) {
            final files = await _scanDirectory(dir);
            pdfFiles.addAll(files);
          }
        } catch (e) {
          print('Error scanning $dirPath: $e');
        }
      }
    } catch (e) {
      print('Get device PDFs error: $e');
    }
    
    return pdfFiles;
  }
  
  Future<List<Map<String, String>>> _scanDirectory(Directory dir) async {
    final List<Map<String, String>> pdfFiles = [];
    
    try {
      final List<FileSystemEntity> entities = await dir.list().toList();
      
      for (var entity in entities) {
        if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
          try {
            final stat = await entity.stat();
            pdfFiles.add({
              'path': entity.path,
              'size': _formatFileSize(stat.size),
              'date': _formatFileDate(stat.modified),
            });
          } catch (e) {
            pdfFiles.add({
              'path': entity.path,
              'size': '~1 MB',
              'date': _getCurrentDate(),
            });
          }
        }
        
        if (pdfFiles.length > 100) break;
      }
    } catch (e) {
      print('Scan directory error: ${dir.path} - $e');
    }
    
    return pdfFiles;
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
  
  String _getFileNameFromPath(String path) {
    return path.split('/').last;
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
        base64: file.base64,
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
            base64: file.base64,
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
  
  Future<void> _importPDF() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );
      
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/${file.name}');
        
        String? base64Data;
        
        if (file.path != null) {
          final sourceFile = File(file.path!);
          await sourceFile.copy(tempFile.path);
          final bytes = await tempFile.readAsBytes();
          base64Data = base64Encode(bytes);
        } else if (file.bytes != null) {
          await tempFile.writeAsBytes(file.bytes!);
          final bytes = await tempFile.readAsBytes();
          base64Data = base64Encode(bytes);
        }
        
        if (base64Data != null) {
          final newFile = PdfFile(
            id: DateTime.now().millisecondsSinceEpoch,
            name: file.name,
            size: _formatFileSize(file.size),
            date: _getCurrentDate(),
            base64: base64Data,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            fileType: FileType.imported,
          );
          
          setState(() {
            _importedFiles.insert(0, newFile);
            _addToRecent(newFile);
            if (_currentScreenIndex != 0 || _currentHomeTabIndex != 1) {
              _currentScreenIndex = 0;
              _currentHomeTabIndex = 1;
              _tabController.animateTo(1);
            } else {
              _updateFilteredFiles();
            }
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${file.name} başarıyla yüklendi')),
          );
        }
      }
    } catch (e) {
      print('Import error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dosya yüklenirken hata oluştu')),
      );
    }
  }
  
  void _openPDFViewer(PdfFile file) {
    _addToRecent(file);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PDFViewerScreen(pdfFile: file),
      ),
    );
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
  
  Widget _buildPermissionBanner() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.folder_open,
            size: 64,
            color: Theme.of(context).primaryColor.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Cihazınızdaki PDF\'lere erişebilmem için izin gerekli',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Devam etmek için Tüm Dosya Erişimi izni verin.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _requestPermission,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Ayarlardan Erişim Ver'),
          ),
        ],
      ),
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
  
  Widget _buildToolsGrid() {
    final tools = [
      ToolItem(id: 1, title: 'PDF Birleştir', icon: Icons.merge, color: const Color(0xFFE53935), page: 'merge'),
      ToolItem(id: 2, title: 'Sesli Okuma', icon: Icons.volume_up, color: const Color(0xFF4CAF50), page: 'tts'),
      ToolItem(id: 3, title: 'OCR Metin Çıkar', icon: Icons.text_fields, color: const Color(0xFF2196F3), page: 'ocr'),
      ToolItem(id: 4, title: 'PDF İmzala', icon: Icons.draw, color: const Color(0xFF9C27B0), page: 'sign'),
      ToolItem(id: 5, title: 'PDF Sıkıştır', icon: Icons.compress, color: const Color(0xFFFF9800), page: 'compress'),
      ToolItem(id: 6, title: 'Sayfa Düzenle', icon: Icons.reorder, color: const Color(0xFF795548), page: 'organize'),
      ToolItem(id: 7, title: 'Resimden PDF', icon: Icons.image, color: const Color(0xFF00BCD4), page: 'image2pdf'),
      ToolItem(id: 8, title: 'PDF\'den Resim', icon: Icons.picture_as_pdf, color: const Color(0xFF607D8B), page: 'pdf2image'),
    ];
    
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.2,
      ),
      itemCount: tools.length,
      itemBuilder: (context, index) {
        final tool = tools[index];
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            onTap: () {
              _navigateToToolPage(tool.page);
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: tool.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(tool.icon, color: tool.color, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tool.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  
  void _navigateToToolPage(String page) {
    switch (page) {
      case 'merge':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MergeScreen()),
        );
        break;
      case 'tts':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const TTSScreen()),
        );
        break;
      case 'ocr':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const OCRScreen()),
        );
        break;
      case 'sign':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SignScreen()),
        );
        break;
      case 'compress':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CompressScreen()),
        );
        break;
      case 'organize':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const OrganizeScreen()),
        );
        break;
      case 'image2pdf':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ImageToPdfScreen()),
        );
        break;
      case 'pdf2image':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const PdfToImageScreen()),
        );
        break;
    }
  }
  
  Widget _buildCloudServicesList() {
    final cloudServices = [
      CloudService(id: 1, name: 'Google Drive', icon: Icons.cloud, color: const Color(0xFF4285F4), serviceType: 'google_drive'),
      CloudService(id: 2, name: 'OneDrive', icon: Icons.cloud, color: const Color(0xFF0078D4), serviceType: 'onedrive'),
      CloudService(id: 3, name: 'Dropbox', icon: Icons.cloud, color: const Color(0xFF0061FF), serviceType: 'dropbox'),
    ];
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Bu aygıtta',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Bağlı bulut hesapları',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
        const SizedBox(height: 24),
        
        // Cloud Services
        Column(
          children: cloudServices.map((service) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: service.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(service.icon, color: service.color),
                ),
                title: Text(service.name),
                trailing: Icon(Icons.add, color: Theme.of(context).primaryColor),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${service.name} bağlanıyor...')),
                  );
                },
              ),
            );
          }).toList(),
        ),
        
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        
        // E-posta section
        Text(
          'E-postalardaki PDF\'ler',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEA4335).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.mail, color: Color(0xFFEA4335)),
            ),
            title: const Text('Gmail'),
            trailing: Icon(Icons.add, color: Theme.of(context).primaryColor),
            onTap: () {
              ScaffoldMessenger.of(context).showSnakBar(
                const SnackBar(content: Text('Gmail bağlanıyor...')),
              );
            },
          ),
        ),
        
        const SizedBox(height: 32),
        Center(
          child: OutlinedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Daha fazla dosya göz atılıyor...')),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).primaryColor,
              side: BorderSide(color: Theme.of(context).primaryColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text('Daha fazla dosyaya göz atın'),
          ),
        ),
      ],
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      key: _scaffoldKey,
      appBar: _currentScreenIndex == 0 ? 
        (_isSearching ? _buildSearchAppBar(theme) : _buildMainAppBar(theme)) : 
        _buildSimpleAppBar(theme),
      body: _buildBody(theme),
      bottomNavigationBar: _buildBottomNavBar(theme),
      floatingActionButton: _currentScreenIndex == 0 ? _buildFAB(theme) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
  
  AppBar _buildMainAppBar(ThemeData theme) {
    return AppBar(
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.primaryColor,
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
  
  AppBar _buildSimpleAppBar(ThemeData theme) {
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
  
  AppBar _buildSearchAppBar(ThemeData theme) {
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
  
  Widget _buildBody(ThemeData theme) {
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
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Swipe gesture için: yatay kaydırma ile tab değişimi
        if (notification is ScrollUpdateNotification && 
            notification.dragDetails != null) {
          final delta = notification.dragDetails!.delta.dx;
          if (delta.abs() > 10) { // Minimum swipe mesafesi
            if (delta < 0 && _currentHomeTabIndex < 2) {
              // Sağdan sola swipe - sonraki tab
              _tabController.animateTo(_currentHomeTabIndex + 1);
            } else if (delta > 0 && _currentHomeTabIndex > 0) {
              // Soldan sağa swipe - önceki tab
              _tabController.animateTo(_currentHomeTabIndex - 1);
            }
          }
        }
        return false;
      },
      child: Column(
        children: [
          // Sticky Tab Bar (AppBar gizlenince gösterilecek)
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
          
          // Content with scroll controller
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
      ),
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
    
    if (!_hasPermission) {
      return _buildPermissionBanner();
    }
    
    if (_filteredFiles.isEmpty) {
      return _buildEmptyState('Cihazınızda PDF bulunamadı');
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
  
  Widget _buildBottomNavBar(ThemeData theme) {
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
  
  Widget _buildFAB(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showFabMenu) ...[
          _buildFABMenuItem(
            icon: Icons.document_scanner,
            label: 'Belge Tara',
            onTap: () {
              setState(() => _showFabMenu = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Kamera açılıyor...')),
              );
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
        ],
        FloatingActionButton(
          onPressed: () {
            setState(() => _showFabMenu = !_showFabMenu);
          },
          backgroundColor: theme.primaryColor,
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
}

// --- PDF VIEWER SCREEN ---

class PDFViewerScreen extends StatefulWidget {
  final PdfFile pdfFile;

  const PDFViewerScreen({super.key, required this.pdfFile});

  @override
  State<PDFViewerScreen> createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends State<PDFViewerScreen> {
  late InAppWebViewController _webViewController;
  double _progress = 0;
  bool _isLoading = true;

  @override
  Widget build(BuildContext context) {
    // Base64 veriyi viewer.html'e query parameter olarak gönderiyoruz
    String viewerUrl;
    
    if (widget.pdfFile.base64 != null) {
      // Base64 veriyi direkt gönderiyoruz
      viewerUrl = 'asset://flutter_assets/assets/web/viewer.html?base64=${widget.pdfFile.base64}';
    } else if (widget.pdfFile.path != null) {
      // Dosya yolundan açma
      viewerUrl = 'asset://flutter_assets/assets/web/viewer.html?file=file://${widget.pdfFile.path}';
    } else {
      viewerUrl = 'asset://flutter_assets/assets/web/viewer.html';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pdfFile.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // Paylaşma işlevi
            },
          ),
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () {
              // Yazdırma işlevi
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              // Menü seçenekleri
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'info',
                child: Text('Dosya Bilgisi'),
              ),
              const PopupMenuItem<String>(
                value: 'rename',
                child: Text('Yeniden Adlandır'),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: Text('Sil', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(viewerUrl)),
            initialOptions: InAppWebViewGroupOptions(
              crossPlatform: InAppWebViewOptions(
                javaScriptEnabled: true,
                useShouldOverrideUrlLoading: true,
                allowFileAccessFromFileURLs: true,
                allowUniversalAccessFromFileURLs: true,
                transparentBackground: true,
              ),
              android: AndroidInAppWebViewOptions(
                useHybridComposition: true,
                allowContentAccess: true,
                allowFileAccess: true,
              ),
              ios: IOSInAppWebViewOptions(
                allowsInlineMediaPlayback: true,
              ),
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
            },
            onLoadStart: (controller, url) {
              setState(() {
                _isLoading = true;
              });
            },
            onLoadStop: (controller, url) async {
              setState(() {
                _isLoading = false;
              });
              
              // JavaScript injection for handling base64 PDF
              if (widget.pdfFile.base64 != null) {
                await controller.evaluateJavascript(source: '''
                  document.addEventListener("webviewerloaded", () => {
                    const params = new URLSearchParams(window.location.search);
                    const base64 = params.get("base64");
                    if (!base64) return;

                    // Base64 → Uint8Array
                    const b64 = base64.split(',')[1];
                    const raw = atob(b64);
                    const len = raw.length;
                    const bytes = new Uint8Array(len);
                    for (let i = 0; i < len; i++) bytes[i] = raw.charCodeAt(i);

                    // Uint8Array → Blob → Blob URL
                    const blob = new Blob([bytes], { type: "application/pdf" });
                    const blobUrl = URL.createObjectURL(blob);

                    // Viewer initialize olana kadar bekle
                    const waiter = setInterval(() => {
                      if (!window.PDFViewerApplication || !PDFViewerApplication.initialized) return;

                      clearInterval(waiter);

                      // 🔥 PDF.js v5.x için doğru kullanım: { url: blobUrl }
                      PDFViewerApplication.open({ url: blobUrl });

                    }, 50);
                  });
                  
                  // Eğer webviewerloaded event'i zaten tetiklenmişse, kodu çalıştır
                  if (document.querySelector('.PDFViewer')) {
                    const params = new URLSearchParams(window.location.search);
                    const base64 = params.get("base64");
                    if (base64) {
                      // Yukarıdaki kodu burada da çalıştır
                      const b64 = base64.split(',')[1];
                      const raw = atob(b64);
                      const len = raw.length;
                      const bytes = new Uint8Array(len);
                      for (let i = 0; i < len; i++) bytes[i] = raw.charCodeAt(i);
                      const blob = new Blob([bytes], { type: "application/pdf" });
                      const blobUrl = URL.createObjectURL(blob);
                      if (window.PDFViewerApplication && PDFViewerApplication.initialized) {
                        PDFViewerApplication.open({ url: blobUrl });
                      }
                    }
                  }
                ''');
              }
            },
            onProgressChanged: (controller, progress) {
              setState(() {
                _progress = progress / 100;
              });
            },
          ),
          
          if (_isLoading)
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).primaryColor,
              ),
            ),
        ],
      ),
    );
  }
}

// --- TOOL SCREENS (PLACEHOLDER) ---

class MergeScreen extends StatelessWidget {
  const MergeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Birleştir')),
      body: const Center(child: Text('PDF Birleştirme Ekranı')),
    );
  }
}

class TTSScreen extends StatelessWidget {
  const TTSScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sesli Okuma')),
      body: const Center(child: Text('Sesli Okuma Ekranı')),
    );
  }
}

class OCRScreen extends StatelessWidget {
  const OCRScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR Metin Çıkar')),
      body: const Center(child: Text('OCR Ekranı')),
    );
  }
}

class SignScreen extends StatelessWidget {
  const SignScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF İmzala')),
      body: const Center(child: Text('PDF İmzalama Ekranı')),
    );
  }
}

class CompressScreen extends StatelessWidget {
  const CompressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Sıkıştır')),
      body: const Center(child: Text('PDF Sıkıştırma Ekranı')),
    );
  }
}

class OrganizeScreen extends StatelessWidget {
  const OrganizeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sayfa Düzenle')),
      body: const Center(child: Text('Sayfa Düzenleme Ekranı')),
    );
  }
}

class ImageToPdfScreen extends StatelessWidget {
  const ImageToPdfScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resimden PDF')),
      body: const Center(child: Text('Resimden PDF Ekranı')),
    );
  }
}

class PdfToImageScreen extends StatelessWidget {
  const PdfToImageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF\'den Resim')),
      body: const Center(child: Text('PDF\'den Resim Ekranı')),
    );
  }
}
