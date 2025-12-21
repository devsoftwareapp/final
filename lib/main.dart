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
    AndroidInAppWebView.setWebContentsDebuggingEnabled(true);
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

// --- MAIN HOME SCREEN ---

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> 
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  int _currentTabIndex = 0;
  
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
  Set<int> _selectedFiles = Set();
  
  // Permission
  bool _hasPermission = false;
  bool _permissionChecked = false;
  
  // Drawer State
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Map<String, bool> _accordionStates = {
    'about': false,
    'settings': false,
    'privacy': false,
    'help': false,
  };
  
  // FAB Menu
  bool _showFabMenu = false;
  
  // Connectivity
  bool _isConnected = true;
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    
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
    _connectivitySubscription.cancel();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
      if (_currentTabIndex == 1) { // Device tab
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
    
    // Load recent files
    final recentJson = prefs.getStringList('recent_files') ?? [];
    _recentFiles = recentJson.map((json) => PdfFile.fromJson(jsonDecode(json))).toList();
    
    // Load favorite files
    final favoriteJson = prefs.getStringList('favorite_files') ?? [];
    _favoriteFiles = favoriteJson.map((json) => PdfFile.fromJson(jsonDecode(json))).toList();
    
    // Load imported files
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
            id: DateTime.now().millisecondsSinceEpoch + pdf.hashCode,
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
        
        // Recursive için limit
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
        _currentTabIndex = _tabController.index;
        _updateFilteredFiles();
      });
    }
  }
  
  void _updateFilteredFiles() {
    List<PdfFile> sourceList;
    
    switch (_currentTabIndex) {
      case 0: // Recent
        sourceList = _recentFiles;
        break;
      case 1: // Device
        sourceList = [..._deviceFiles, ..._importedFiles];
        break;
      case 2: // Favorites
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
      if (_currentTabIndex == 0) {
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
      
      // Update in other lists
      _updateFileInList(_recentFiles, file);
      _updateFileInList(_deviceFiles, file);
      _updateFileInList(_importedFiles, file);
      
      _saveData();
      _updateFilteredFiles();
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
        type: FileType.custom,
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
          base64Data = base64Encode(file.bytes!);
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
            if (_currentTabIndex != 1) {
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
    final isDark = theme.brightness == Brightness.dark;
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
                    PopupMenuItem(
                      child: const Text('Paylaş'),
                      onTap: () {
                        // Share functionality
                      },
                    ),
                    PopupMenuItem(
                      child: const Text('Yeniden Adlandır'),
                      onTap: () {
                        // Rename functionality
                      },
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${tool.title} açılıyor...')),
              );
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
  
  Widget _buildFilesPanel() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildFileSourceItem(
          icon: Icons.phone_android,
          title: 'Bu aygıtta',
          subtitle: '',
          onTap: () {
            setState(() {
              _tabController.animateTo(1);
            });
            Navigator.pop(context);
          },
        ),
        _buildFileSourceItem(
          icon: Icons.drive_file_move,
          title: 'Google Drive',
          subtitle: '',
          onTap: () {},
        ),
        _buildFileSourceItem(
          icon: Icons.cloud,
          title: 'OneDrive',
          subtitle: '',
          onTap: () {},
        ),
        _buildFileSourceItem(
          icon: Icons.interests,
          title: 'Dropbox',
          subtitle: '',
          onTap: () {},
        ),
        _buildFileSourceItem(
          icon: Icons.mail,
          title: 'E-postalardaki PDF\'ler',
          subtitle: 'Gmail',
          onTap: () {},
        ),
        _buildFileSourceItem(
          icon: Icons.folder_open,
          title: 'Daha fazla dosyaya göz atın',
          subtitle: '',
          onTap: () {},
        ),
      ],
    );
  }
  
  Widget _buildFileSourceItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      key: _scaffoldKey,
      appBar: _isSearching ? _buildSearchAppBar(theme) : _buildMainAppBar(theme),
      drawer: _buildDrawer(theme),
      body: _buildBody(theme),
      bottomNavigationBar: _buildBottomNavBar(theme),
      floatingActionButton: _buildFAB(theme),
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
      bottom: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(icon: Icon(Icons.history), text: 'Son'),
          Tab(icon: Icon(Icons.phone_iphone), text: 'Cihazda'),
          Tab(icon: Icon(Icons.star), text: 'Favoriler'),
        ],
      ),
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
        decoration: InputDecoration(
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
    if (_currentTabIndex == 0) {
      return _buildRecentTab();
    } else if (_currentTabIndex == 1) {
      return _buildDeviceTab();
    } else if (_currentTabIndex == 2) {
      return _buildFavoritesTab();
    }
    return Container();
  }
  
  Widget _buildRecentTab() {
    if (_filteredFiles.isEmpty) {
      return _buildEmptyState('Henüz dosya yok');
    }
    
    return ListView.builder(
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
      itemCount: _filteredFiles.length,
      itemBuilder: (context, index) {
        return _buildPDFCard(_filteredFiles[index], index);
      },
    );
  }
  
  Widget _buildBottomNavBar(ThemeData theme) {
    return BottomNavigationBar(
      currentIndex: _currentTabIndex,
      onTap: (index) {
        setState(() {
          _currentTabIndex = index;
          _tabController.animateTo(index);
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
  
  Widget _buildDrawer(ThemeData theme) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: theme.primaryColor,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.picture_as_pdf, color: Color(0xFFE53935)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'PDF Reader',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Dev Software',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          _buildDrawerItem(
            icon: Icons.info,
            title: 'Hakkında',
            onTap: () {
              Navigator.pop(context);
              _showAboutDialog();
            },
          ),
          _buildDrawerItem(
            icon: Icons.settings,
            title: 'Ayarlar',
            onTap: () {
              Navigator.pop(context);
              _showSettingsDialog();
            },
          ),
          _buildDrawerItem(
            icon: Icons.privacy_tip,
            title: 'Gizlilik',
            onTap: () {
              Navigator.pop(context);
              _showPrivacyDialog();
            },
          ),
          _buildDrawerItem(
            icon: Icons.help,
            title: 'Yardım',
            onTap: () {
              Navigator.pop(context);
              _showHelpDialog();
            },
          ),
          const Divider(),
          _buildDrawerItem(
            icon: Icons.exit_to_app,
            title: 'Çıkış',
            onTap: () {
              exit(0);
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: onTap,
    );
  }
  
  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hakkında'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PDF Reader by Dev Software'),
            SizedBox(height: 8),
            Text('Bu uygulama, PDF dosyalarını hızlı, güvenli ve verimli bir şekilde görüntülemek, yönetmek ve temel düzeyde düzenlemek için tasarlanmıştır.'),
            SizedBox(height: 8),
            Text('Tüm Hakları Saklıdır © 2025 Dev Software.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
  
  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ayarlar'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('Uygulama Dili'),
                subtitle: const Text('Türkçe'),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('PDF Dili'),
                subtitle: const Text('Türkçe'),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.dark_mode),
                title: const Text('Tema'),
                subtitle: const Text('Sistem'),
                onTap: () {},
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
  
  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gizlilik'),
        content: const SingleChildScrollView(
          child: Text(
            'Kişisel verilerinizin ve belge gizliliğinizin bizim için en önemli öncelik olduğunu garanti ederiz. Uygulama, dosyalarınızı sunucularımıza yüklemeden cihazınızda yerel olarak işleyecek şekilde tasarlanmıştır.\n\nDev Software olarak, kullanıcılarımızın hiçbir kişisel verisini üçüncü taraflarla paylaşmayız.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
  
  void _showHelpDialog() {
    final TextEditingController emailController = TextEditingController();
    final TextEditingController subjectController = TextEditingController();
    final TextEditingController messageController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yardım'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sorununuzu bize iletin. Ekibimiz en kısa sürede dönüş yapacaktır.'),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'E-posta Adresiniz',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(
                  labelText: 'Konu Başlığı',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Sorununuz',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mesajınız gönderildi')),
              );
              Navigator.pop(context);
            },
            child: const Text('Gönder'),
          ),
        ],
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
    String viewerUrl;
    
    if (widget.pdfFile.base64 != null) {
      // Base64 verisi varsa data URL oluştur
      viewerUrl = 'asset://flutter_assets/assets/web/viewer.html?file=data:application/pdf;base64,${widget.pdfFile.base64}';
    } else if (widget.pdfFile.path != null) {
      // Dosya yolu varsa file URL oluştur
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
              // Share functionality
            },
          ),
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () {
              // Print functionality
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // More options
            },
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
            onLoadStop: (controller, url) {
              setState(() {
                _isLoading = false;
              });
            },
            onProgressChanged: (controller, progress) {
              setState(() {
                _progress = progress / 100;
              });
            },
            onConsoleMessage: (controller, consoleMessage) {
              print('PDF Viewer Console: ${consoleMessage.message}');
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
