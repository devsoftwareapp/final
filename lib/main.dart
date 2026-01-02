import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PDF Reader',
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.red,
      ),
      home: const WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> with WidgetsBindingObserver {
  InAppWebViewController? webViewController;
  bool _isViewerOpen = false;
  DateTime? _lastBackPressTime;
  late PackageInfo _packageInfo;
  String _currentUrl = '';
  
  // IndexedDB için temp dosya takibi
  final Map<String, String> _indexedDBTempFiles = {};
  
  // Çağrı takibi (Çift çağrı önleme)
  DateTime? _lastShareCall;
  DateTime? _lastPrintCall;
  DateTime? _lastDownloadCall;
  final Duration _callThrottle = const Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPackageInfo();
    debugPrint("🚀 PDF Reader başlatıldı - IndexedDB Optimize Edilmiş");
  }

  Future<void> _initPackageInfo() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  @override
  void dispose() {
    _cleanupIndexedDBTempFiles();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("📱 Uygulama ayarlardan geri döndü");
      _checkAndUpdatePermissionStatus();
    }
  }

  // IndexedDB için temp dosyaları temizle
  Future<void> _cleanupIndexedDBTempFiles() async {
    for (var path in _indexedDBTempFiles.values) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          debugPrint("🗑️ IndexedDB temp dosyası silindi: ${file.path}");
        }
      } catch (e) {
        debugPrint("⚠️ IndexedDB temp dosya silinemedi: $e");
      }
    }
    _indexedDBTempFiles.clear();
  }

  Future<void> _checkAndUpdatePermissionStatus() async {
    if (webViewController == null) return;
    
    final hasPermission = await _checkStoragePermission();
    debugPrint("🔒 IndexedDB İzin durumu: $hasPermission");
    
    await webViewController!.evaluateJavascript(source: """
      (function() {
        console.log("📱 Android resume - IndexedDB izin durumu güncelleniyor");
        if (typeof onAndroidResume === 'function') {
          onAndroidResume();
        }
        if (typeof scanDeviceForPDFs === 'function') {
          setTimeout(function() {
            scanDeviceForPDFs();
          }, 500);
        }
      })();
    """);
  }

  // IndexedDB için permission kontrolü
  Future<bool> _checkStoragePermission() async {
    if (Platform.isAndroid) {
      try {
        // Android 13+ için MEDIA izinleri (IndexedDB için önemli)
        final android13Permissions = await Future.wait([
          Permission.photos.status,
          Permission.videos.status,
          Permission.audio.status,
        ]);
        
        if (android13Permissions.any((status) => status.isGranted)) {
          debugPrint("✅ IndexedDB: Android 13+ MEDIA izinleri mevcut");
          return true;
        }
        
        // Android 11-12 için MANAGE_EXTERNAL_STORAGE
        final manageStorageStatus = await Permission.manageExternalStorage.status;
        if (manageStorageStatus.isGranted) {
          debugPrint("✅ IndexedDB: MANAGE_EXTERNAL_STORAGE izni mevcut");
          return true;
        }
        
        // Android 10 ve altı için STORAGE
        final storageStatus = await Permission.storage.status;
        if (storageStatus.isGranted) {
          debugPrint("✅ IndexedDB: STORAGE izni mevcut");
          return true;
        }
        
        debugPrint("❌ IndexedDB: Hiçbir izin mevcut değil");
        return false;
        
      } catch (e) {
        debugPrint("❌ IndexedDB izin kontrol hatası: $e");
        return false;
      }
    }
    return true;
  }

  // IndexedDB için izin iste
  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      try {
        debugPrint("🔐 IndexedDB için izin isteniyor...");
        
        // Önce MANAGE_EXTERNAL_STORAGE dene (IndexedDB için en iyisi)
        if (await Permission.manageExternalStorage.status.isDenied) {
          final result = await Permission.manageExternalStorage.request();
          if (result.isGranted) {
            debugPrint("✅ IndexedDB: MANAGE_EXTERNAL_STORAGE izni verildi");
            return true;
          }
          
          if (result.isPermanentlyDenied) {
            debugPrint("⚠️ IndexedDB: MANAGE_EXTERNAL_STORAGE kalıcı reddedildi");
            await _openManageStorageSettings();
            return false;
          }
        }
        
        // Normal storage iznini dene
        if (await Permission.storage.status.isDenied) {
          final result = await Permission.storage.request();
          if (result.isGranted) {
            debugPrint("✅ IndexedDB: STORAGE izni verildi");
            return true;
          }
          
          if (result.isPermanentlyDenied) {
            debugPrint("⚠️ IndexedDB: STORAGE kalıcı reddedildi");
            await _openManageStorageSettings();
            return false;
          }
        }
        
        // Android 13+ için media izinlerini dene
        final results = await [
          Permission.photos,
          Permission.videos,
          Permission.audio,
        ].request();
        
        if (results.values.any((status) => status.isGranted)) {
          debugPrint("✅ IndexedDB: MEDIA izinlerinden biri verildi");
          return true;
        }
        
        debugPrint("❌ IndexedDB: Hiçbir izin verilmedi");
        return false;
        
      } catch (e) {
        debugPrint("❌ IndexedDB izin isteği hatası: $e");
        return false;
      }
    }
    return true;
  }

  // ✅ DOĞRUDAN Dosya Erişim İzni ayarlarına git
  Future<void> _openManageStorageSettings() async {
    debugPrint("⚙️ DOĞRUDAN Dosya Erişim İzni Ayarları açılıyor...");
    try {
      if (Platform.isAndroid) {
        // DOĞRUDAN Manage Storage Settings'e git
        await AppSettings.openAppSettings(type: AppSettingsType.manageStorage);
        debugPrint("✅ Dosya Erişim İzni Ayarları açıldı");
        
        // Kullanıcıyı bilgilendir
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lütfen "Tüm dosyalara erişim" iznini verin'),
              duration: Duration(seconds: 5),
              backgroundColor: Colors.blue,
            ),
          );
        }
      } else {
        await AppSettings.openAppSettings();
        debugPrint("✅ Ayarlar açıldı (iOS)");
      }
    } catch (e) {
      debugPrint("❌ Dosya Erişim İzni Ayarları açma hatası: $e");
      
      // Fallback: Genel ayarlar
      try {
        await AppSettings.openAppSettings();
        debugPrint("✅ Fallback ayarlar açıldı");
      } catch (e2) {
        debugPrint("❌ Fallback ayarlar açma hatası: $e2");
      }
    }
  }

  Future<void> _openAppSettings() async {
    debugPrint("⚙️ IndexedDB için genel ayarlar açılıyor...");
    try {
      if (Platform.isAndroid) {
        await AppSettings.openAppSettings();
        debugPrint("✅ IndexedDB: Genel ayarlar açıldı");
      } else {
        await AppSettings.openAppSettings();
        debugPrint("✅ IndexedDB: Ayarlar açıldı");
      }
    } catch (e) {
      debugPrint("❌ IndexedDB ayarlar açma hatası: $e");
      
      try {
        await openAppSettings();
        debugPrint("✅ IndexedDB: Ayarlar açıldı (fallback)");
      } catch (e2) {
        debugPrint("❌ IndexedDB Fallback ayarlar açma hatası: $e2");
      }
    }
  }

  // IndexedDB için PDF dosyalarını listele - ✅ UNIQUE PATH KONTROLÜ EKLENDI
  Future<List<Map<String, dynamic>>> _listPdfFiles() async {
    List<Map<String, dynamic>> pdfFiles = [];
    
    try {
      if (Platform.isAndroid) {
        debugPrint("📂 IndexedDB için PDF dosyaları taranıyor...");
        
        List<String> searchPaths = [
          '/storage/emulated/0/Download',
          '/storage/emulated/0/Documents',
          '/storage/emulated/0/DCIM',
          '/storage/emulated/0/Downloads',
          '/storage/emulated/0',
          '/sdcard/Download',
          '/sdcard/Documents',
          '/storage/emulated/0/Android/media',
          '/storage/emulated/0/Android/data',
        ];

        int totalFound = 0;
        Set<String> uniquePaths = {}; // ✅ UNIQUE PATH KONTROLÜ
        
        for (String path in searchPaths) {
          try {
            final directory = Directory(path);
            if (await directory.exists()) {
              await _scanDirectoryRecursiveForIndexedDB(directory, pdfFiles, uniquePaths);
              totalFound = pdfFiles.length;
            }
          } catch (e) {
            debugPrint("⚠️ IndexedDB dizin tarama hatası: $path - $e");
            continue;
          }
        }
        
        debugPrint("✅ IndexedDB için toplam $totalFound PDF dosyası bulundu");
        // Boyuta göre sırala (büyükten küçüğe)
        pdfFiles.sort((a, b) => b['size'].compareTo(a['size']));
      }
    } catch (e) {
      debugPrint("❌ IndexedDB PDF listeleme hatası: $e");
    }
    
    return pdfFiles;
  }

  // IndexedDB için recursive tarama - ✅ UNIQUE PATH KONTROLÜ EKLENDI
  Future<void> _scanDirectoryRecursiveForIndexedDB(
    Directory directory, 
    List<Map<String, dynamic>> pdfFiles,
    Set<String> uniquePaths // ✅ UNIQUE PATH SET'İ
  ) async {
    try {
      final contents = directory.list(recursive: false);
      
      await for (var entity in contents) {
        if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
          try {
            // ✅ UNIQUE PATH KONTROLÜ - AYNI PDF'İ İKİNCİ KEZ EKLEME
            if (uniquePaths.contains(entity.path)) {
              debugPrint("⚠️ Duplicate atlandı: ${entity.path}");
              continue;
            }
            
            final stat = await entity.stat();
            final sizeInMB = stat.size / (1024 * 1024);
            
            // IndexedDB için boyut limiti (50MB - güvenli limit)
            if (sizeInMB > 50) {
              debugPrint("⚠️ IndexedDB: Büyük dosya atlandı: ${entity.path} (${sizeInMB.toStringAsFixed(2)} MB)");
              continue;
            }
            
            // ✅ UNIQUE PATH'İ SET'E EKLE
            uniquePaths.add(entity.path);
            
            pdfFiles.add({
              'path': entity.path,
              'name': entity.path.split('/').last,
              'size': stat.size,
              'modified': stat.modified.toIso8601String(),
              'sizeMB': sizeInMB,
              'indexedDBReady': true,
            });
            
          } catch (e) {
            debugPrint("⚠️ IndexedDB dosya bilgisi alınamadı: ${entity.path}");
          }
        } else if (entity is Directory) {
          final dirName = entity.path.split('/').last.toLowerCase();
          if (!dirName.startsWith('.') && 
              dirName != 'android' && 
              dirName != 'lost+found' &&
              !dirName.contains('cache') &&
              !dirName.contains('temp')) {
            await _scanDirectoryRecursiveForIndexedDB(entity, pdfFiles, uniquePaths);
          }
        }
      }
    } catch (e) {
      debugPrint("❌ IndexedDB dizin tarama hatası (${directory.path}): $e");
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes == 0) return '0 Bytes';
    const k = 1024;
    const dm = 1;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    final i = (bytes == 0) ? 0 : (math.log(bytes) / math.log(k)).floor();
    return '${(bytes / math.pow(k, i)).toStringAsFixed(dm)} ${sizes[i]}';
  }

  // IndexedDB için PDF'yi temp'e kopyala
  Future<String?> _copyPdfToTempForIndexedDB(String sourcePath, String fileName) async {
    try {
      debugPrint("📋 IndexedDB için PDF temp'e kopyalanıyor: $fileName");
      
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        debugPrint("❌ IndexedDB: Kaynak dosya bulunamadı: $sourcePath");
        return null;
      }
      
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/indexeddb_${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final tempFile = File(tempPath);
      
      // Eski temp dosyaları temizle
      final oldFiles = await tempDir.list()
          .where((entity) => entity is File && entity.path.contains('indexeddb_'))
          .toList();
      
      for (var file in oldFiles) {
        try {
          if (file is File) {
            final fileAge = DateTime.now().difference(await file.lastModified());
            if (fileAge > const Duration(hours: 1)) {
              await file.delete();
            }
          }
        } catch (e) {
          // Geçici dosya silme hatasını görmezden gel
        }
      }
      
      await sourceFile.copy(tempPath);
      _indexedDBTempFiles[fileName] = tempPath;
      
      debugPrint("✅ IndexedDB: PDF temp'e kopyalandı: $tempPath");
      return tempPath;
      
    } catch (e) {
      debugPrint("❌ IndexedDB temp kopyalama hatası: $e");
      return null;
    }
  }

  // IndexedDB için viewer reset
  Future<void> _resetViewerAndGoBackForIndexedDB() async {
    if (webViewController == null) return;
    
    debugPrint("🔄 IndexedDB Viewer resetleniyor...");
    
    try {
      await webViewController!.evaluateJavascript(source: """
        (async function() {
          try {
            console.log("🗑️ INDEXEDDB VIEWER FULL RESET başlatılıyor...");
            
            if (typeof viewerPdfManager !== 'undefined' && viewerPdfManager.cleanup) {
              await viewerPdfManager.cleanup();
              console.log("✅ IndexedDB Manager temizlendi");
            }
            
            if (typeof pdfManager !== 'undefined' && pdfManager.cleanup) {
              await pdfManager.cleanup();
              console.log("✅ Main IndexedDB Manager temizlendi");
            }
            
            if (typeof PDFViewerApplication !== 'undefined') {
              try {
                if (PDFViewerApplication.pdfDocument) {
                  await PDFViewerApplication.pdfDocument.destroy();
                  PDFViewerApplication.pdfDocument = null;
                  console.log("✅ IndexedDB PDF Document destroy edildi");
                }
                
                if (PDFViewerApplication.close) {
                  await PDFViewerApplication.close();
                  console.log("✅ IndexedDB PDF Viewer kapatıldı");
                }
                
                PDFViewerApplication.pdfViewer = null;
                PDFViewerApplication.pdfLinkService = null;
                PDFViewerApplication.pdfHistory = null;
                
              } catch (e) {
                console.log("⚠️ IndexedDB PDF Viewer kapatma hatası:", e);
              }
            }
            
            if (typeof window.activeBlobUrls !== 'undefined') {
              window.activeBlobUrls.forEach(url => {
                try {
                  URL.revokeObjectURL(url);
                } catch (e) {}
              });
              window.activeBlobUrls = [];
              console.log("✅ IndexedDB Blob URL'ler temizlendi");
            }
            
            sessionStorage.clear();
            console.log("✅ IndexedDB Session storage temizlendi");
            
            const keysToRemove = [];
            for (let i = 0; i < localStorage.length; i++) {
              const key = localStorage.key(i);
              if (key && (key.startsWith('last') || key.includes('Pdf') || key.includes('Blob') || key.includes('current') || key.includes('indexeddb'))) {
                keysToRemove.push(key);
              }
            }
            keysToRemove.forEach(key => localStorage.removeItem(key));
            console.log("✅ IndexedDB Local storage temizlendi:", keysToRemove.length, "anahtar");
            
            console.log("✅✅✅ INDEXEDDB TAM TEMİZLİK TAMAMLANDI");
            return true;
            
          } catch (e) {
            console.error("❌ IndexedDB Viewer temizleme hatası:", e);
            return false;
          }
        })();
      """);
      
      await _cleanupIndexedDBTempFiles();
      
      debugPrint("🔄 IndexedDB WebView state sıfırlanıyor...");
      
      await webViewController!.loadUrl(
        urlRequest: URLRequest(
          url: WebUri("about:blank"),
        ),
      );
      
      await Future.delayed(const Duration(milliseconds: 200));
      
      await webViewController!.loadUrl(
        urlRequest: URLRequest(
          url: WebUri("file:///android_asset/flutter_assets/assets/web/index.html"),
        ),
      );
      
      setState(() {
        _isViewerOpen = false;
        _currentUrl = 'index.html';
      });
      
      debugPrint("✅✅✅ IndexedDB: index.html'e geri dönüldü");
      
      await Future.delayed(const Duration(milliseconds: 1000), () async {
        if (webViewController != null) {
          await webViewController!.evaluateJavascript(source: """
            (function() {
              console.log("🔄 IndexedDB PDF listesi yenileniyor...");
              if (typeof scanDeviceForPDFs === 'function') {
                scanDeviceForPDFs();
              }
              if (typeof loadData === 'function') {
                loadData();
              }
              if (typeof pdfManager !== 'undefined' && pdfManager.init) {
                setTimeout(function() {
                  pdfManager.init().then(function() {
                    console.log("✅ IndexedDB yeniden başlatıldı");
                  });
                }, 500);
              }
            })();
          """);
        }
      });
      
    } catch (e) {
      debugPrint("❌ IndexedDB Viewer reset hatası: $e");
      
      try {
        await webViewController!.loadUrl(
          urlRequest: URLRequest(
            url: WebUri("file:///android_asset/flutter_assets/assets/web/index.html"),
          ),
        );
        setState(() {
          _isViewerOpen = false;
          _currentUrl = 'index.html';
        });
      } catch (e2) {
        debugPrint("❌ IndexedDB Fallback yükleme hatası: $e2");
      }
    }
  }

  bool _canCallFunction(DateTime? lastCall) {
    if (lastCall == null) return true;
    return DateTime.now().difference(lastCall) > _callThrottle;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (webViewController != null) {
          if (_isViewerOpen) {
            debugPrint("⬅️ IndexedDB Viewer'dan geri dönülüyor...");
            await _resetViewerAndGoBackForIndexedDB();
            return false;
          } else {
            final result = await webViewController!.evaluateJavascript(
              source: "window.androidBackPressed ? window.androidBackPressed() : false;"
            );
            
            if (result == 'exit_check') {
              final now = DateTime.now();
              if (_lastBackPressTime == null || 
                  now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
                _lastBackPressTime = now;
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Çıkmak için tekrar basın'),
                      duration: Duration(seconds: 2),
                      backgroundColor: Colors.black87,
                    ),
                  );
                }
                
                return false;
              }
              
              return true;
            }
            
            return false;
          }
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri("file:///android_asset/flutter_assets/assets/web/index.html"),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              allowFileAccess: true,
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
              useHybridComposition: true,
              domStorageEnabled: true,
              databaseEnabled: true,
              displayZoomControls: false,
              builtInZoomControls: false,
              safeBrowsingEnabled: false,
              sharedCookiesEnabled: true,
              thirdPartyCookiesEnabled: true,
              cacheEnabled: true,
              clearCache: false,
              supportZoom: false,
              disableVerticalScroll: false,
              disableHorizontalScroll: false,
              hardwareAcceleration: true,
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              transparentBackground: false,
              disableContextMenu: false,
              incognito: false,
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: """
                  console.log("🚀 Flutter WebView - IndexedDB Optimize Edilmiş");
                  console.log("📦 IndexedDB durumu:", typeof indexedDB !== 'undefined' ? '✅ Destekleniyor' : '❌ Desteklenmiyor');
                  
                  window.activeBlobUrls = window.activeBlobUrls || [];
                  
                  if (typeof indexedDB === 'undefined') {
                    console.error("❌ CRITICAL: IndexedDB desteklenmiyor!");
                  } else {
                    console.log("✅ IndexedDB hazır - ArrayBuffer + Base64 mode");
                  }
                  
                  if (typeof Android === 'undefined') {
                    window.Android = {
                      openSettings: function() {
                        window.flutter_inappwebview.callHandler('openSettingsForPermission');
                      },
                      openManageStorageSettings: function() {
                        window.flutter_inappwebview.callHandler('openManageStorageSettings');
                      },
                      checkIndexedDBSupport: function() {
                        return typeof indexedDB !== 'undefined';
                      }
                    };
                  }
                """,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            onWebViewCreated: (controller) {
              webViewController = controller;
              debugPrint("🌐 IndexedDB WebView oluşturuldu");

              // ✅ DOĞRUDAN DOSYA ERİŞİM AYARLARI
              controller.addJavaScriptHandler(
                handlerName: 'openManageStorageSettings',
                callback: (args) async {
                  debugPrint("🔧 DOĞRUDAN Dosya Erişim İzni Ayarları açılıyor...");
                  await _openManageStorageSettings();
                  
                  Future.delayed(const Duration(seconds: 2), () async {
                    final hasPermission = await _checkStoragePermission();
                    debugPrint("🔒 IndexedDB İzin durumu (ayarlardan sonra): $hasPermission");
                    
                    if (hasPermission) {
                      try {
                        final pdfFiles = await _listPdfFiles();
                        debugPrint("📋 IndexedDB PDF taraması tamamlandı: ${pdfFiles.length} dosya");
                      } catch (e) {
                        debugPrint("❌ IndexedDB PDF tarama hatası: $e");
                      }
                    }
                  });
                },
              );

              // ==================== INDEXEDDB İZİN DURUMU ====================
              controller.addJavaScriptHandler(
                handlerName: 'checkStoragePermission',
                callback: (args) async {
                  final hasPermission = await _checkStoragePermission();
                  debugPrint("🔒 IndexedDB İzin kontrolü: $hasPermission");
                  return hasPermission;
                },
              );

              // ==================== INDEXEDDB İZİN İSTE ====================
              controller.addJavaScriptHandler(
                handlerName: 'requestStoragePermission',
                callback: (args) async {
                  debugPrint("🔐 IndexedDB için izin isteniyor...");
                  final granted = await _requestStoragePermission();
                  debugPrint("🔐 IndexedDB İzin sonucu: $granted");
                  return granted;
                },
              );

              // ==================== INDEXEDDB PDF LİSTESİ ====================
              controller.addJavaScriptHandler(
                handlerName: 'listPdfFiles',
                callback: (args) async {
                  debugPrint("📋 IndexedDB PDF listesi istendi");
                  try {
                    final pdfFiles = await _listPdfFiles();
                    final jsonResult = jsonEncode(pdfFiles);
                    debugPrint("✅ IndexedDB PDF listesi hazır: ${pdfFiles.length} dosya");
                    return jsonResult;
                  } catch (e) {
                    debugPrint("❌ IndexedDB PDF listeleme hatası: $e");
                    return "[]";
                  }
                },
              );

              // ==================== INDEXEDDB PDF PATH AL ====================
              controller.addJavaScriptHandler(
                handlerName: 'getPdfPath',
                callback: (args) async {
                  try {
                    String sourcePath = args[0];
                    String fileName = args.length > 1 ? args[1] : sourcePath.split('/').last;
                    
                    debugPrint("📄 IndexedDB için PDF path istendi: $fileName");
                    
                    final tempPath = await _copyPdfToTempForIndexedDB(sourcePath, fileName);
                    
                    if (tempPath != null) {
                      debugPrint("✅ IndexedDB PDF path hazır: $tempPath");
                      return tempPath;
                    } else {
                      debugPrint("❌ IndexedDB PDF path alınamadı");
                      return null;
                    }
                  } catch (e) {
                    debugPrint("❌ IndexedDB PDF path hatası: $e");
                    return null;
                  }
                },
              );

              // ==================== INDEXEDDB DOSYA BOYUTU ====================
              controller.addJavaScriptHandler(
                handlerName: 'getFileSize',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      final stat = await file.stat();
                      final sizeFormatted = _formatFileSize(stat.size);
                      debugPrint("📏 IndexedDB Dosya boyutu: $sizeFormatted");
                      return stat.size;
                    }
                  } catch (e) {
                    debugPrint("❌ IndexedDB Dosya boyutu alma hatası: $e");
                  }
                  return 0;
                },
              );

              // ==================== INDEXEDDB DOSYA OKU ====================
              controller.addJavaScriptHandler(
                handlerName: 'readPdfFile',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    debugPrint("📖 IndexedDB için PDF dosyası okunuyor: $filePath");
                    
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      final bytes = await file.readAsBytes();
                      final sizeInMB = bytes.length / (1024 * 1024);
                      debugPrint("✅ IndexedDB PDF okundu: ${sizeInMB.toStringAsFixed(2)} MB - IndexedDB'ye gönderiliyor");
                      
                      // Uint8List olarak döndür
                      return bytes;
                    } else {
                      debugPrint("❌ IndexedDB Dosya bulunamadı: $filePath");
                      return null;
                    }
                  } catch (e) {
                    debugPrint("❌ IndexedDB Dosya okuma hatası: $e");
                    return null;
                  }
                },
              );

              // ==================== INDEXEDDB AYARLARI AÇ ====================
              controller.addJavaScriptHandler(
                handlerName: 'openSettingsForPermission',
                callback: (args) async {
                  await _openAppSettings();
                },
              );

              // ==================== INDEXEDDB PAYLAŞ ====================
              controller.addJavaScriptHandler(
                handlerName: 'sharePdfBase64',
                callback: (args) async {
                  if (!_canCallFunction(_lastShareCall)) {
                    debugPrint("⚠️ IndexedDB Paylaşma çağrısı çok hızlı, atlandı");
                    return;
                  }
                  _lastShareCall = DateTime.now();
                  
                  try {
                    String base64Data = args[0];
                    String fileName = args.length > 1 ? args[1] : "document.pdf";
                    
                    debugPrint("📤 IndexedDB PDF paylaşılıyor: $fileName");
                    
                    if (base64Data.isEmpty || base64Data.length < 100) {
                      debugPrint("❌ IndexedDB Base64 verisi geçersiz");
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ IndexedDB PDF verisi geçersiz'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    
                    final cleanBase64 = base64Data.replaceFirst(
                      RegExp(r'data:application/pdf;base64,'), 
                      ''
                    );
                    
                    List<int> bytes;
                    try {
                      bytes = base64Decode(cleanBase64);
                      debugPrint("✅ IndexedDB Base64 decode başarılı: ${bytes.length} bytes");
                    } catch (e) {
                      debugPrint("❌ IndexedDB Base64 decode hatası: $e");
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ IndexedDB PDF verisi decode edilemedi'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    
                    if (bytes.length < 1024) {
                      debugPrint("❌ IndexedDB PDF verisi çok küçük: ${bytes.length} bytes");
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ IndexedDB PDF verisi geçersiz (çok küçük)'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    
                    final tempDir = await getTemporaryDirectory();
                    final tempFile = File('${tempDir.path}/share_$fileName');
                    await tempFile.writeAsBytes(bytes);
                    
                    debugPrint("✅ IndexedDB Temp dosya oluşturuldu: ${tempFile.path}");
                    
                    final result = await Share.shareXFiles([XFile(tempFile.path)], text: fileName);
                    
                    debugPrint("✅ IndexedDB PDF paylaşma sonucu: ${result.status}");
                    
                    await tempFile.delete();
                    
                  } catch (e) {
                    debugPrint("❌ IndexedDB Paylaşma hatası: $e");
                    
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ IndexedDB Paylaşma hatası: ${e.toString()}'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
              );

              // ==================== INDEXEDDB YAZDIR ====================
              controller.addJavaScriptHandler(
                handlerName: 'printPdfBase64',
                callback: (args) async {
                  if (!_canCallFunction(_lastPrintCall)) {
                    debugPrint("⚠️ IndexedDB Yazdırma çağrısı çok hızlı, atlandı");
                    return;
                  }
                  _lastPrintCall = DateTime.now();
                  
                  try {
                    String base64Data = args[0];
                    String fileName = args.length > 1 ? args[1] : "document.pdf";
                    
                    debugPrint("🖨️ IndexedDB PDF yazdırılıyor: $fileName");
                    
                    if (base64Data.isEmpty || base64Data.length < 100) {
                      debugPrint("❌ IndexedDB Base64 verisi geçersiz");
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ IndexedDB PDF verisi geçersiz'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    
                    final cleanBase64 = base64Data.replaceFirst(
                      RegExp(r'data:application/pdf;base64,'), 
                      ''
                    );
                    
                    List<int> bytes;
                    try {
                      bytes = base64Decode(cleanBase64);
                      debugPrint("✅ IndexedDB Base64 decode başarılı: ${bytes.length} bytes");
                    } catch (e) {
                      debugPrint("❌ IndexedDB Base64 decode hatası: $e");
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ IndexedDB PDF verisi decode edilemedi'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    
                    if (bytes.length < 1024) {
                      debugPrint("❌ IndexedDB PDF verisi çok küçük: ${bytes.length} bytes");
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ IndexedDB PDF verisi geçersiz (çok küçük)'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    
                    await Printing.layoutPdf(
                      onLayout: (format) async => Uint8List.fromList(bytes),
                      name: fileName,
                    );
                    
                    debugPrint("✅ IndexedDB Yazdırma tamamlandı");
                    
                  } catch (e) {
                    debugPrint("❌ IndexedDB Yazdırma hatası: $e");
                    
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ IndexedDB Yazdırma hatası: ${e.toString()}'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
              );

              // ==================== INDEXEDDB İNDİR ====================
              controller.addJavaScriptHandler(
                handlerName: 'downloadPdfBase64',
                callback: (args) async {
                  if (!_canCallFunction(_lastDownloadCall)) {
                    debugPrint("⚠️ IndexedDB İndirme çağrısı çok hızlı, atlandı");
                    return;
                  }
                  _lastDownloadCall = DateTime.now();
                  
                  try {
                    String base64Data = args[0];
                    String fileName = args.length > 1 ? args[1] : "document.pdf";
                    
                    debugPrint("💾 IndexedDB PDF indiriliyor: $fileName");
                    
                    if (base64Data.isEmpty || base64Data.length < 100) {
                      debugPrint("❌ IndexedDB Base64 verisi geçersiz");
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ IndexedDB PDF verisi geçersiz'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    
                    final cleanBase64 = base64Data.replaceFirst(
                      RegExp(r'data:application/pdf;base64,'), 
                      ''
                    );
                    
                    List<int> bytes;
                    try {
                      bytes = base64Decode(cleanBase64);
                      debugPrint("✅ IndexedDB Base64 decode başarılı: ${bytes.length} bytes");
                    } catch (e) {
                      debugPrint("❌ IndexedDB Base64 decode hatası: $e");
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ IndexedDB PDF verisi decode edilemedi'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    
                    if (bytes.length < 1024) {
                      debugPrint("❌ IndexedDB PDF verisi çok küçük: ${bytes.length} bytes");
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ IndexedDB PDF verisi geçersiz (çok küçük)'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    
                    Directory? directory;
                    if (Platform.isAndroid) {
                      directory = Directory('/storage/emulated/0/Download/PDF Reader');
                      if (!await directory.exists()) {
                        await directory.create(recursive: true);
                        debugPrint("✅ IndexedDB PDF Reader klasörü oluşturuldu");
                      }
                    } else {
                      directory = await getApplicationDocumentsDirectory();
                    }

                    if (directory != null && await directory.exists()) {
                      String nameWithoutExt = fileName.replaceAll('.pdf', '');
                      String finalName = '${nameWithoutExt}_indexeddb.pdf';
                      
                      File targetFile = File('${directory.path}/$finalName');
                      
                      int counter = 1;
                      while (await targetFile.exists()) {
                        finalName = '${nameWithoutExt}_indexeddb ($counter).pdf';
                        targetFile = File('${directory.path}/$finalName');
                        counter++;
                      }
                      
                      await targetFile.writeAsBytes(bytes);
                      
                      debugPrint("✅ IndexedDB PDF indirildi: ${targetFile.path}");

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ IndexedDB İndirildi: $finalName'),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                    
                  } catch (e) {
                    debugPrint("❌ IndexedDB İndirme hatası: $e");
                    
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ IndexedDB İndirme hatası: ${e.toString()}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              );

              // ==================== INDEXEDDB DESTEK KONTROLÜ ====================
              controller.addJavaScriptHandler(
                handlerName: 'checkIndexedDBSupport',
                callback: (args) async {
                  debugPrint("✅ IndexedDB desteği kontrolü: DESTEKLENİYOR");
                  return true;
                },
              );

              // ==================== INDEXEDDB STORAGE BİLGİSİ ====================
              controller.addJavaScriptHandler(
                handlerName: 'getStorageInfo',
                callback: (args) async {
                  try {
                    final tempDir = await getTemporaryDirectory();
                    final appDir = await getApplicationDocumentsDirectory();
                    
                    return jsonEncode({
                      'tempDir': tempDir.path,
                      'appDir': appDir.path,
                      'indexedDBSupported': true,
                      'maxPdfSize': 50,
                      'storageType': 'indexeddb-arraybuffer-base64-optimized',
                      'storagePath': tempDir.path,
                    });
                  } catch (e) {
                    debugPrint("❌ IndexedDB Storage bilgisi hatası: $e");
                    return "{}";
                  }
                },
              );

              // ==================== INDEXEDDB UYGULAMA DURUMU ====================
              controller.addJavaScriptHandler(
                handlerName: 'getAppStatus',
                callback: (args) async {
                  return jsonEncode({
                    'platform': Platform.operatingSystem,
                    'version': Platform.operatingSystemVersion,
                    'storageAvailable': await _checkStoragePermission(),
                    'tempDir': (await getTemporaryDirectory()).path,
                    'appDir': (await getApplicationDocumentsDirectory()).path,
                    'indexedDBSupported': true,
                    'storageMode': 'indexeddb-arraybuffer-base64-optimized',
                    'packageName': _packageInfo.packageName,
                    'appVersion': _packageInfo.version,
                    'indexedDBVersion': '2.0',
                    'maxFileSizeMB': 50,
                  });
                },
              );
            },
            onLoadStart: (controller, url) {
              final urlString = url.toString();
              debugPrint("🌐 IndexedDB Sayfa yükleniyor: $urlString");
              
              final isViewer = urlString.contains("viewer.html");
              setState(() {
                _isViewerOpen = isViewer;
                _currentUrl = urlString;
              });
              
              if (urlString.contains("index.html") && !urlString.contains("about:blank")) {
                debugPrint("🏠 IndexedDB index.html yükleniyor");
                Future.delayed(const Duration(milliseconds: 300), () async {
                  await controller.evaluateJavascript(source: """
                    (function() {
                      console.log("🧹 IndexedDB index.html son temizlik...");
                      
                      if (typeof PDFViewerApplication !== 'undefined') {
                        PDFViewerApplication = undefined;
                      }
                      if (typeof viewerPdfManager !== 'undefined') {
                        viewerPdfManager = undefined;
                      }
                      
                      console.log("✅ IndexedDB index.html temiz slate hazır");
                    })();
                  """);
                });
              }
            },
            onLoadStop: (controller, url) async {
              final urlString = url.toString();
              debugPrint("✅ IndexedDB Sayfa yüklendi: $urlString");
              
              setState(() {
                _isViewerOpen = urlString.contains("viewer.html");
                _currentUrl = urlString;
              });
              
              await _checkAndUpdatePermissionStatus();
              
              await controller.evaluateJavascript(source: """
                (async function() {
                  try {
                    console.log("📦 IndexedDB başlatılıyor...");
                    
                    if (typeof indexedDB === 'undefined') {
                      console.error("❌ CRITICAL: IndexedDB desteklenmiyor!");
                      return;
                    }
                    
                    if (typeof pdfManager !== 'undefined' && pdfManager.init) {
                      const success = await pdfManager.init();
                      console.log("📦 Main IndexedDB Manager: " + (success ? "✅ Başarılı" : "❌ Başarısız"));
                      
                      if (success) {
                        const info = await pdfManager.getStorageInfo();
                        if (info) {
                          console.log("💾 IndexedDB Storage kullanımı: " + info.usedMB + " MB / " + info.quotaMB + " MB");
                        }
                      }
                    }
                    
                    if (typeof viewerPdfManager !== 'undefined' && viewerPdfManager.init) {
                      const success = await viewerPdfManager.init();
                      console.log("📦 Viewer IndexedDB Manager: " + (success ? "✅ Başarılı" : "❌ Başarısız"));
                    }
                    
                    console.log("✅ IndexedDB hazır - ArrayBuffer + Base64 mode");
                    
                  } catch (e) {
                    console.error("❌ IndexedDB başlatma hatası:", e);
                  }
                })();
              """);
            },
            onConsoleMessage: (controller, consoleMessage) {
              final message = consoleMessage.message;
              final level = consoleMessage.messageLevel;
              
              String prefix = "📱 INDEXEDDB JS";
              if (level == ConsoleMessageLevel.ERROR) {
                prefix = "❌ INDEXEDDB JS ERROR";
              } else if (level == ConsoleMessageLevel.WARNING) {
                prefix = "⚠️ INDEXEDDB JS WARN";
              } else if (level == ConsoleMessageLevel.DEBUG) {
                prefix = "🐛 INDEXEDDB JS DEBUG";
              }
              
              debugPrint("$prefix: $message");
            },
            onLoadError: (controller, url, code, message) {
              debugPrint("❌ IndexedDB Yükleme hatası: $message (code: $code)");
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ IndexedDB Yükleme hatası: $message'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            onLoadHttpError: (controller, url, statusCode, description) {
              debugPrint("❌ IndexedDB HTTP hatası: $description (status: $statusCode)");
            },
            onPermissionRequest: (controller, permissionRequest) async {
              debugPrint("🔒 IndexedDB İzin isteği: ${permissionRequest.resources}");
              return PermissionResponse(
                resources: permissionRequest.resources,
                action: PermissionResponseAction.GRANT,
              );
            },
            onProgressChanged: (controller, progress) {
              if (progress == 100) {
                debugPrint("✅ IndexedDB Sayfa yükleme tamamlandı (%100)");
              }
            },
          ),
        ),
      ),
    );
  }
}
