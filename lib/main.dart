import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

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
            
            controller.addJavaScriptHandler(
              handlerName: 'checkPermission',
              callback: (args) async {
                return await _checkAndroidPermission();
              },
            );
            
            controller.addJavaScriptHandler(
              handlerName: 'listPDFs',
              callback: (args) async {
                return await _scanDeviceForPDFs();
              },
            );
            
            // Uygulama geri geldiğinde kontrol
            controller.addJavaScriptHandler(
              handlerName: 'onResume',
              callback: (args) async {
                return await _checkAndroidPermission();
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

  // GERÇEK TARAMA FONKSİYONU
  Future<String> _scanDeviceForPDFs() async {
    try {
      final permissionStatus = await _checkAndroidPermission();
      if (permissionStatus != 'granted') {
        return 'PERMISSION_DENIED';
      }
      
      print('Starting real PDF scan...');
      
      // Tüm önemli dizinleri tarayalım
      final List<String> pdfPaths = [];
      
      // Android'in ana dizinleri
      final List<String> directoriesToScan = [
        '/storage/emulated/0/',
        '/sdcard/',
        '/storage/self/primary/',
      ];
      
      for (var directoryPath in directoriesToScan) {
        try {
          final dir = Directory(directoryPath);
          if (await dir.exists()) {
            print('Scanning directory: $directoryPath');
            final files = await _scanDirectoryForPDFs(dir);
            pdfPaths.addAll(files);
          }
        } catch (e) {
          print('Error scanning $directoryPath: $e');
        }
      }
      
      // Ek olarak Downloads, Documents, DCIM gibi spesifik klasörler
      final List<String> specificFolders = [
        'Download',
        'Documents',
        'DCIM',
        'Pictures',
        'Books',
        'Telegram',
        'WhatsApp',
        'Movies',
        'Music'
      ];
      
      for (var folder in specificFolders) {
        try {
          final path = '/storage/emulated/0/$folder';
          final dir = Directory(path);
          if (await dir.exists()) {
            print('Scanning folder: $folder');
            final files = await _scanDirectoryForPDFs(dir);
            pdfPaths.addAll(files);
          }
        } catch (e) {
          print('Error scanning folder $folder: $e');
        }
      }
      
      print('Found ${pdfPaths.length} PDF files');
      
      if (pdfPaths.isEmpty) {
        return 'NO_PDFS_FOUND||';
      }
      
      return pdfPaths.join('||');
    } catch (e) {
      print('Error in _scanDeviceForPDFs: $e');
      return 'ERROR||$e';
    }
  }

  // Dizin tarama fonksiyonu
  Future<List<String>> _scanDirectoryForPDFs(Directory dir) async {
    final List<String> pdfFiles = [];
    
    try {
      final List<FileSystemEntity> entities = dir.listSync(recursive: true);
      
      for (var entity in entities) {
        if (entity is File) {
          final path = entity.path.toLowerCase();
          if (path.endsWith('.pdf')) {
            pdfFiles.add(entity.path);
            
            // Çok fazla dosya bulunursa sınırla
            if (pdfFiles.length > 1000) {
              break;
            }
          }
        }
      }
    } catch (e) {
      print('Error scanning ${dir.path}: $e');
    }
    
    return pdfFiles;
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
