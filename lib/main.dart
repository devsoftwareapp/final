import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: InAppWebView(
          key: webViewKey,
          initialFile: "assets/web/index.html",
          initialOptions: InAppWebViewGroupOptions(
            crossPlatform: InAppWebViewOptions(
              javaScriptEnabled: true,
              useShouldOverrideUrlLoading: true,
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
            ),
            android: AndroidInAppWebViewOptions(
              useHybridComposition: true,
              allowContentAccess: true,
              allowFileAccess: true,
            ),
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;
            
            // JavaScript handler'larını ekle
            controller.addJavaScriptHandler(
              handlerName: 'openSettings',
              callback: (args) {
                _openAndroidSettings();
              },
            );
            
            controller.addJavaScriptHandler(
              handlerName: 'androidBackPressed',
              callback: (args) {
                return _handleAndroidBack();
              },
            );
            
            // İzin kontrolü için handler
            controller.addJavaScriptHandler(
              handlerName: 'checkPermission',
              callback: (args) async {
                return await _checkAndroidPermission();
              },
            );
            
            // PDF listesi için handler (DOSYA BİLGİLERİYLE BİRLİKTE)
            controller.addJavaScriptHandler(
              handlerName: 'listPDFs',
              callback: (args) async {
                final pdfs = await _scanDeviceForPDFs();
                // JSON formatında döndür: {path, size, date}
                return pdfs.map((p) => '${p['path']}||${p['size']}||${p['date']}').join('@@@');
              },
            );
            
            // Tekil dosya bilgisi için handler
            controller.addJavaScriptHandler(
              handlerName: 'getFileInfo',
              callback: (args) async {
                if (args.isNotEmpty) {
                  final filePath = args[0] as String;
                  return await _getFileInfo(filePath);
                }
                return '';
              },
            );
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final uri = navigationAction.request.url;
            
            if (uri != null) {
              if (uri.toString() == 'settings://all_files') {
                _openAndroidSettings();
                return NavigationActionPolicy.CANCEL;
              }
              
              if (uri.scheme == 'http' || uri.scheme == 'https') {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                return NavigationActionPolicy.CANCEL;
              }
            }
            
            return NavigationActionPolicy.ALLOW;
          },
          onLoadStop: (controller, url) async {
            controller.evaluateJavascript(source: '''
              if (typeof window.flutterReady === 'function') {
                window.flutterReady();
              }
            ''');
          },
        ),
      ),
    );
  }

  Future<void> _openAndroidSettings() async {
    try {
      await openAppSettings();
    } catch (e) {
      print('Error opening settings: $e');
      _showSnackBar('Ayarlar açılırken hata oluştu');
    }
  }

  Future<String> _checkAndroidPermission() async {
    if (Platform.isAndroid) {
      try {
        var status = await Permission.manageExternalStorage.status;
        
        if (status.isGranted) {
          return 'granted';
        } else {
          status = await Permission.manageExternalStorage.request();
          return status.isGranted ? 'granted' : 'denied';
        }
      } catch (e) {
        return 'denied';
      }
    }
    return 'denied';
  }

  // GERÇEK TARAMA FONKSİYONU (DOSYA BİLGİLERİYLE)
  Future<List<Map<String, String>>> _scanDeviceForPDFs() async {
    final List<Map<String, String>> pdfFiles = [];
    
    try {
      final permissionStatus = await _checkAndroidPermission();
      if (permissionStatus != 'granted') {
        return pdfFiles;
      }
      
      // Android'in ana dizinleri
      final List<String> directoriesToScan = [
        '/storage/emulated/0/',
        '/sdcard/',
      ];
      
      for (var directoryPath in directoriesToScan) {
        try {
          final dir = Directory(directoryPath);
          if (await dir.exists()) {
            final files = await _scanDirectoryForPDFs(dir);
            pdfFiles.addAll(files);
          }
        } catch (e) {
          print('Error scanning $directoryPath: $e');
        }
      }
      
      print('Found ${pdfFiles.length} PDF files with real info');
      
    } catch (e) {
      print('Error in _scanDeviceForPDFs: $e');
    }
    
    return pdfFiles;
  }

  // Dizin tarama (GERÇEK DOSYA BİLGİLERİYLE)
  Future<List<Map<String, String>>> _scanDirectoryForPDFs(Directory dir) async {
    final List<Map<String, String>> pdfFiles = [];
    
    try {
      final List<FileSystemEntity> entities = dir.listSync(recursive: true);
      
      for (var entity in entities) {
        if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
          try {
            final file = File(entity.path);
            final stat = await file.stat();
            
            // Dosya boyutunu formatla
            String formattedSize = _formatFileSize(stat.size);
            
            // Dosya tarihini formatla
            String formattedDate = _formatFileDate(stat.modified);
            
            pdfFiles.add({
              'path': entity.path,
              'size': formattedSize,
              'date': formattedDate,
            });
            
            // Çok fazla dosya bulunursa sınırla
            if (pdfFiles.length > 500) {
              break;
            }
          } catch (e) {
            // Dosya bilgisi alınamazsa varsayılan değerler
            pdfFiles.add({
              'path': entity.path,
              'size': '~1 MB',
              'date': _getCurrentDate(),
            });
          }
        }
      }
    } catch (e) {
      print('Error scanning ${dir.path}: $e');
    }
    
    return pdfFiles;
  }

  // Dosya boyutunu formatla (Bytes → KB/MB/GB)
  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  // Dosya tarihini formatla
  String _formatFileDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    // Bugün mü?
    if (difference.inDays == 0) {
      return 'Bugün ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
    // Dün mü?
    else if (difference.inDays == 1) {
      return 'Dün ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
    // Bu hafta içinde mi?
    else if (difference.inDays < 7) {
      return '${difference.inDays} gün önce';
    }
    // Tarihi formatla
    else {
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    }
  }

  // Tekil dosya bilgisi al
  Future<String> _getFileInfo(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final stat = await file.stat();
        final size = _formatFileSize(stat.size);
        final date = _formatFileDate(stat.modified);
        
        return '$size||$date';
      }
    } catch (e) {
      print('Error getting file info for $filePath: $e');
    }
    
    return '~1 MB||${_getCurrentDate()}';
  }

  String _getCurrentDate() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  dynamic _handleAndroidBack() {
    webViewController?.evaluateJavascript(source: '''
      if (typeof androidBackPressed === 'function') {
        var result = androidBackPressed();
        result;
      } else {
        false;
      }
    ''').then((value) {
      if (value == 'exit_check') {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Çıkış'),
              content: const Text('Uygulamadan çıkmak istediğinize emin misiniz?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                TextButton(
                  onPressed: () => exit(0),
                  child: const Text('Çık'),
                ),
              ],
            ),
          );
        }
      }
    });
    
    return null;
  }
}
