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
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:crypto/crypto.dart';

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
  
  final Map<String, String> _indexedDBTempFiles = {};
  
  DateTime? _lastShareCall;
  DateTime? _lastPrintCall;
  DateTime? _lastDownloadCall;
  final Duration _callThrottle = const Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPackageInfo();
    debugPrint("🚀 PDF Reader başlatıldı - TEK DOSYA GÖSTERİM MODU");
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

  Future<bool> _checkStoragePermission() async {
    if (Platform.isAndroid) {
      try {
        final android13Permissions = await Future.wait([
          Permission.photos.status,
          Permission.videos.status,
          Permission.audio.status,
        ]);
        
        if (android13Permissions.any((status) => status.isGranted)) {
          debugPrint("✅ IndexedDB: Android 13+ MEDIA izinleri mevcut");
          return true;
        }
        
        final manageStorageStatus = await Permission.manageExternalStorage.status;
        if (manageStorageStatus.isGranted) {
          debugPrint("✅ IndexedDB: MANAGE_EXTERNAL_STORAGE izni mevcut");
          return true;
        }
        
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

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      try {
        debugPrint("🔐 IndexedDB için izin isteniyor...");
        
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

  Future<void> _openManageStorageSettings() async {
    debugPrint("⚙️ DOĞRUDAN Dosya Erişim İzni Ayarları açılıyor...");
    
    try {
      if (Platform.isAndroid) {
        String packageName = _packageInfo.packageName;
        debugPrint("📦 Paket adı: $packageName");
        
        try {
          final uri = Uri.parse("intent:#Intent;action=android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION;package=$packageName;end");
          
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
            debugPrint("✅ Dosya Erişim İzni Ayarları açıldı (Intent)");
          } else {
            debugPrint("⚠️ Intent açılamadı, fallback kullanılıyor");
            final fallbackUri = Uri.parse("package:$packageName");
            await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
          }
        } catch (e) {
          debugPrint("❌ Intent hatası: $e");
          final generalSettingsUri = Uri.parse("package:$packageName");
          await launchUrl(generalSettingsUri, mode: LaunchMode.externalApplication);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lütfen "Tüm dosyalara erişim" iznini verin'),
              duration: Duration(seconds: 5),
              backgroundColor: Colors.blue,
            ),
          );
        }
        
        await Future.delayed(const Duration(seconds: 3));
        
        final hasPermission = await _checkStoragePermission();
        if (hasPermission) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ İzin verildi! PDF\'ler yükleniyor...'),
                duration: Duration(seconds: 3),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        final settingsUri = Uri.parse('app-settings:');
        if (await canLaunchUrl(settingsUri)) {
          await launchUrl(settingsUri);
          debugPrint("✅ Ayarlar açıldı (iOS)");
        }
      }
    } catch (e) {
      debugPrint("❌ Dosya Erişim İzni Ayarları açma hatası: $e");
      
      try {
        String packageName = _packageInfo.packageName;
        final fallbackUri = Uri.parse("package:$packageName");
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
        debugPrint("✅ Fallback ayarlar açıldı");
      } catch (e2) {
        debugPrint("❌ Fallback ayarlar açma hatası: $e2");
      }
    }
  }

  Future<void> _openAppSettings() async {
    debugPrint("⚙️ IndexedDB için genel ayarlar açılıyor...");
    try {
      String packageName = _packageInfo.packageName;
      final settingsUri = Uri.parse("package:$packageName");
      
      if (await canLaunchUrl(settingsUri)) {
        await launchUrl(settingsUri, mode: LaunchMode.externalApplication);
        debugPrint("✅ IndexedDB: Genel ayarlar açıldı");
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

  Future<List<Map<String, dynamic>>> _listPdfFiles() async {
    List<Map<String, dynamic>> pdfFiles = [];
    try {
      if (Platform.isAndroid) {
        debugPrint("📂 TEK DOSYA MODU: PDF dosyaları taranıyor...");
        
        List<String> searchPaths = [
          '/storage/emulated/0/Download',
        ];
        
        Set<String> seenHashes = {};
        Set<String> seenNames = {};
        
        for (String path in searchPaths) {
          try {
            final directory = Directory(path);
            if (await directory.exists()) {
              await _scanDirectoryForUniquePDFs(directory, pdfFiles, seenHashes, seenNames, 0);
            } else {
              debugPrint("⚠️ Dizin mevcut değil: $path");
            }
          } catch (e) {
            debugPrint("⚠️ Dizin tarama hatası: $path - $e");
            continue;
          }
        }
        
        debugPrint("✅ TEK DOSYA MODU: ${pdfFiles.length} benzersiz PDF bulundu");
        
        for (var file in pdfFiles) {
          debugPrint("📄 ${file['name']} - ${file['sizeMB'].toStringAsFixed(2)} MB");
        }
      }
    } catch (e) {
      debugPrint("❌ PDF listeleme hatası: $e");
    }
    return pdfFiles;
  }

  Future<void> _scanDirectoryForUniquePDFs(
    Directory directory,
    List<Map<String, dynamic>> pdfFiles,
    Set<String> seenHashes,
    Set<String> seenNames,
    int depth,
  ) async {
    try {
      final contents = directory.list(recursive: false);
      
      await for (var entity in contents) {
        if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
          try {
            final stat = await entity.stat();
            final sizeInMB = stat.size / (1024 * 1024);
            
            if (sizeInMB > 50) {
              debugPrint("⚠️ Büyük dosya atlandı: ${entity.path}");
              continue;
            }
            
            final fileName = entity.path.split('/').last;
            final nameSizeKey = '${fileName}_${stat.size}';
            
            if (seenNames.contains(nameSizeKey)) {
              debugPrint("⏭️ Aynı isim+boyut atlandı: $fileName");
              continue;
            }
            
            final fileHash = await _calculateFileHash(entity, stat);
            if (seenHashes.contains(fileHash)) {
              debugPrint("⏭️ Aynı hash atlandı: $fileName");
              continue;
            }
            
            final contentHash = await _calculateContentHash(entity);
            final fullHash = '${fileHash}_$contentHash';
            
            if (seenHashes.contains(fullHash)) {
              debugPrint("⏭️ Aynı içerik atlandı: $fileName");
              continue;
            }
            
            seenHashes.add(fileHash);
            seenHashes.add(fullHash);
            seenNames.add(nameSizeKey);
            
            pdfFiles.add({
              'path': entity.path,
              'name': fileName,
              'size': stat.size,
              'sizeMB': sizeInMB,
              'modified': stat.modified.toIso8601String(),
              'hash': fullHash,
              'deviceOnly': true,
              'uniqueKey': fullHash,
            });
            
            debugPrint("✅ Eklendi: $fileName (${sizeInMB.toStringAsFixed(2)} MB)");
            
          } catch (e) {
            debugPrint("⚠️ Dosya bilgisi alınamadı: ${entity.path} - $e");
          }
        } else if (entity is Directory && depth < 2) {
          final dirName = entity.path.split('/').last.toLowerCase();
          if (!dirName.startsWith('.') && 
              dirName != 'android' && 
              dirName != 'lost+found' &&
              !dirName.contains('cache') &&
              !dirName.contains('temp') &&
              !dirName.contains('system')) {
            
            await _scanDirectoryForUniquePDFs(entity, pdfFiles, seenHashes, seenNames, depth + 1);
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Dizin tarama hatası (${directory.path}): $e");
    }
  }

  Future<String> _calculateFileHash(File file, FileStat stat) async {
    try {
      final statHash = '${file.path}_${stat.size}_${stat.modified.millisecondsSinceEpoch}';
      final digest = md5.convert(utf8.encode(statHash));
      return digest.toString();
    } catch (e) {
      debugPrint("⚠️ Stat hash hesaplanamadı: $e");
      return '${file.path.hashCode}_${stat.size}';
    }
  }

  Future<String> _calculateContentHash(File file) async {
    try {
      final randomAccessFile = await file.open();
      try {
        final buffer = await randomAccessFile.read(4096);
        await randomAccessFile.close();
        
        if (buffer.isNotEmpty) {
          final digest = md5.convert(buffer);
          return digest.toString();
        } else {
          return 'empty';
        }
      } catch (e) {
        await randomAccessFile.close();
        return 'error_${e.hashCode}';
      }
    } catch (e) {
      debugPrint("⚠️ İçerik hash hesaplanamadı: $e");
      return 'read_error';
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
                  console.log("🚀 Flutter WebView - TEK DOSYA GÖSTERİM MODU");
                  console.log("📦 IndexedDB durumu:", typeof indexedDB !== 'undefined' ? '✅ Destekleniyor' : '❌ Desteklenmiyor');
                  
                  window.activeBlobUrls = window.activeBlobUrls || [];
                  
                  if (typeof indexedDB === 'undefined') {
                    console.error("❌ CRITICAL: IndexedDB desteklenmiyor!");
                  } else {
                    console.log("✅ IndexedDB hazır - TEK DOSYA MODU");
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
              debugPrint("🌐 TEK DOSYA MODU WebView oluşturuldu");
              
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
                        debugPrint("📋 TEK DOSYA MODU PDF taraması tamamlandı: ${pdfFiles.length} dosya");
                      } catch (e) {
                        debugPrint("❌ PDF tarama hatası: $e");
                      }
                    }
                  });
                },
              );
              
              controller.addJavaScriptHandler(
                handlerName: 'checkStoragePermission',
                callback: (args) async {
                  final hasPermission = await _checkStoragePermission();
                  debugPrint("🔒 TEK DOSYA MODU İzin kontrolü: $hasPermission");
                  return hasPermission;
                },
              );
              
              controller.addJavaScriptHandler(
                handlerName: 'requestStoragePermission',
                callback: (args) async {
                  debugPrint("🔐 TEK DOSYA MODU için izin isteniyor...");
                  final granted = await _requestStoragePermission();
                  debugPrint("🔐 TEK DOSYA MODU İzin sonucu: $granted");
                  return granted;
                },
              );
              
              controller.addJavaScriptHandler(
                handlerName: 'listPdfFiles',
                callback: (args) async {
                  debugPrint("📋 TEK DOSYA MODU PDF listesi istendi");
                  try {
                    final pdfFiles = await _listPdfFiles();
                    
                    debugPrint("📊 TEK DOSYA MODU: ${pdfFiles.length} benzersiz PDF bulundu");
                    if (pdfFiles.isNotEmpty) {
                      for (var file in pdfFiles) {
                        debugPrint("   📄 ${file['name']} - ${_formatFileSize(file['size'] as int)}");
                      }
                    }
                    
                    final jsonResult = jsonEncode(pdfFiles);
                    return jsonResult;
                  } catch (e) {
                    debugPrint("❌ TEK DOSYA MODU PDF listeleme hatası: $e");
                    return "[]";
                  }
                },
              );
              
              controller.addJavaScriptHandler(
                handlerName: 'getPdfPath',
                callback: (args) async {
                  try {
                    String sourcePath = args[0];
                    String fileName = args.length > 1 ? args[1] : sourcePath.split('/').last;
                    
                    debugPrint("📄 TEK DOSYA MODU için PDF path istendi: $fileName");
                    
                    final tempPath = await _copyPdfToTempForIndexedDB(sourcePath, fileName);
                    
                    if (tempPath != null) {
                      debugPrint("✅ TEK DOSYA MODU PDF path hazır: $tempPath");
                      return tempPath;
                    } else {
                      debugPrint("❌ TEK DOSYA MODU PDF path alınamadı");
                      return null;
                    }
                  } catch (e) {
                    debugPrint("❌ TEK DOSYA MODU PDF path hatası: $e");
                    return null;
                  }
                },
              );
              
              controller.addJavaScriptHandler(
                handlerName: 'getFileSize',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    final file = File(filePath);
                    if (await file.exists()) {
                      final stat = await file.stat();
                      final sizeFormatted = _formatFileSize(stat.size);
                      debugPrint("📏 TEK DOSYA MODU Dosya boyutu: $sizeFormatted");
                      return stat.size;
                    }
                  } catch (e) {
                    debugPrint("❌ TEK DOSYA MODU Dosya boyutu alma hatası: $e");
                  }
                  return 0;
                },
              );
              
              controller.addJavaScriptHandler(
                handlerName: 'readPdfFile',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    debugPrint("📖 TEK DOSYA MODU için PDF dosyası okunuyor: $filePath");
                    
                    final file = File(filePath);
                    if (await file.exists()) {
                      final bytes = await file.readAsBytes();
                      final sizeInMB = bytes.length / (1024 * 1024);
                      debugPrint("✅ TEK DOSYA MODU PDF okundu: ${sizeInMB.toStringAsFixed(2)} MB");
                      return bytes;
                    } else {
                      debugPrint("❌ TEK DOSYA MODU Dosya bulunamadı: $filePath");
                      return null;
                    }
                  } catch (e) {
                    debugPrint("❌ TEK DOSYA MODU Dosya okuma hatası: $e");
                    return null;
                  }
                },
              );
              
              controller.addJavaScriptHandler(
                handlerName: 'openSettingsForPermission',
                callback: (args) async {
                  await _openAppSettings();
                },
              );
              
              // ✅ GÜNCELLENMİŞ PAYLAŞMA HANDLER'I
              controller.addJavaScriptHandler(
                handlerName: 'sharePdfBase64',
                callback: (args) async {
                  if (!_canCallFunction(_lastShareCall)) {
                    debugPrint("⚠️ TEK DOSYA MODU Paylaşma çağrısı çok hızlı, atlandı");
                    return;
                  }
                  _lastShareCall = DateTime.now();
                  
                  try {
                    String base64Data = args[0];
                    String fileName = args.length > 1 ? args[1] : "document.pdf";
                    
                    debugPrint("📤 TEK DOSYA MODU PDF paylaşılıyor: $fileName");
                    
                    // ✅ Base64 prefix kontrolü
                    if (base64Data.startsWith('data:')) {
                      base64Data = base64Data.split(',')[1];
                    }
                    
                    // ✅ Boşluk ve yeni satırları temizle
                    base64Data = base64Data.replaceAll(RegExp(r'\s+'), '');
                    
                    if (base64Data.isEmpty || base64Data.length < 100) {
                      debugPrint("❌ TEK DOSYA MODU Base64 verisi geçersiz: ${base64Data.length} karakter");
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ PDF verisi geçersiz'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    
                    List<int> bytes;
                    try {
                      bytes = base64Decode(base64Data);
                      debugPrint("✅ TEK DOSYA MODU Base64 decode başarılı: ${bytes.length} bytes");
                    } catch (e) {
                      debugPrint("❌ TEK DOSYA MODU Base64 decode hatası: $e");
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ PDF verisi decode edilemedi'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    
                    if (bytes.length < 1024) {
                      debugPrint("❌ TEK DOSYA MODU PDF verisi çok küçük: ${bytes.length} bytes");
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ PDF verisi geçersiz (çok küçük)'),
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
                    
                    debugPrint("✅ TEK DOSYA MODU Temp dosya oluşturuldu: ${tempFile.path}");
                    
                    final result = await Share.shareXFiles([XFile(tempFile.path)], text: fileName);
                    debugPrint("✅ TEK DOSYA MODU PDF paylaşma sonucu: ${result.status}");
                    
                    await tempFile.delete();
                  } catch (e) {
                    debugPrint("❌ TEK DOSYA MODU Paylaşma hatası: $e");
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ Paylaşma hatası: ${e.toString()}'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
              );
              
              // ✅ GÜNCELLENMİŞ YAZDIRMA HANDLER'I
              controller.addJavaScriptHandler(
                handlerName: 'printPdfBase64',
                callback: (args) async {
                  if (!_canCallFunction(_lastPrintCall)) {
                    debugPrint("⚠️ TEK DOSYA MODU Yazdırma çağrısı çok hızlı, atlandı");
                    return;
                  }
                  _lastPrintCall = DateTime.now();
                  
                  try {
                    String base64Data = args[0];
                    String fileName = args.length > 1 ? args[1] : "document.pdf";
                    
                    debugPrint("🖨️ TEK DOSYA MODU PDF yazdırılıyor: $fileName");
                    
                    // ✅ Base64 prefix kontrolü
                    if (base64Data.startsWith('data:')) {
                      base64Data = base64Data.split(',')[1];
                    }
                    
                    // ✅ Boşluk ve yeni satırları temizle
                    base64Data = base64Data.replaceAll(RegExp(r'\s+'), '');
                    
                    if (base64Data.isEmpty || base64Data.length < 100) {
                      debugPrint("❌ TEK DOSYA MODU Base64 verisi geçersiz");
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ PDF verisi geçersiz'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    
                    List<int> bytes;
                    try {
                      bytes = base64Decode(base64Data);
                      debugPrint("✅ TEK DOSYA MODU Base64 decode başarılı: ${bytes.length} bytes");
                    } catch (e) {
                      debugPrint("❌ TEK DOSYA MODU Base64 decode hatası: $e");
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ PDF verisi decode edilemedi'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    
                    if (bytes.length < 1024) {
                      debugPrint("❌ TEK DOSYA MODU PDF verisi çok küçük: ${bytes.length} bytes");
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ PDF verisi geçersiz (çok küçük)'),
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
                    
                    debugPrint("✅ TEK DOSYA MODU Yazdırma tamamlandı");
                  } catch (e) {
                    debugPrint("❌ TEK DOSYA MODU Yazdırma hatası: $e");
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ Yazdırma hatası: ${e.toString()}'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
              );
              
              // ✅ GÜNCELLENMİŞ İNDİRME HANDLER'I
              controller.addJavaScriptHandler(
                handlerName: 'downloadPdfBase64',
                callback: (args) async {
                  if (!_canCallFunction(_lastDownloadCall)) {
                    debugPrint("⚠️ TEK DOSYA MODU İndirme çağrısı çok hızlı, atlandı");
                    return;
                  }
                  _lastDownloadCall = DateTime.now();
                  
                  try {
                    String base64Data = args[0];
                    String fileName = args.length > 1 ? args[1] : "document.pdf";
                    
                    debugPrint("💾 TEK DOSYA MODU PDF indiriliyor: $fileName");
                    
                    // ✅ Base64 prefix kontrolü
                    if (base64Data.startsWith('data:')) {
                      base64Data = base64Data.split(',')[1];
                    }
                    
                    // ✅ Boşluk ve yeni satırları temizle
                    base64Data = base64Data.replaceAll(RegExp(r'\s+'), '');
                    
                    if (base64Data.isEmpty || base64Data.length < 100) {
                      debugPrint("❌ TEK DOSYA MODU Base64 verisi geçersiz");
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ PDF verisi geçersiz'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    
                    List<int> bytes;
                    try {
                      bytes = base64Decode(base64Data);
                      debugPrint("✅ TEK DOSYA MODU Base64 decode başarılı: ${bytes.length} bytes");
                    } catch (e) {
                      debugPrint("❌ TEK DOSYA MODU Base64 decode hatası: $e");
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ PDF verisi decode edilemedi'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    
                    if (bytes.length < 1024) {
                      debugPrint("❌ TEK DOSYA MODU PDF verisi çok küçük: ${bytes.length} bytes");
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ PDF verisi geçersiz (çok küçük)'),
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
                        debugPrint("✅ TEK DOSYA MODU PDF Reader klasörü oluşturuldu");
                      }
                    } else {
                      directory = await getApplicationDocumentsDirectory();
                    }
                    
                    if (directory != null && await directory.exists()) {
                      String nameWithoutExt = fileName.replaceAll('.pdf', '');
                      String finalName = '${nameWithoutExt}_tekmodu.pdf';
                      File targetFile = File('${directory.path}/$finalName');
                      
                      int counter = 1;
                      while (await targetFile.exists()) {
                        finalName = '${nameWithoutExt}_tekmodu ($counter).pdf';
                        targetFile = File('${directory.path}/$finalName');
                        counter++;
                      }
                      
                      await targetFile.writeAsBytes(bytes);
                      debugPrint("✅ TEK DOSYA MODU PDF indirildi: ${targetFile.path}");
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ İndirildi: $finalName'),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  } catch (e) {
                    debugPrint("❌ TEK DOSYA MODU İndirme hatası: $e");
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ İndirme hatası: ${e.toString()}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              );
              
              controller.addJavaScriptHandler(
                handlerName: 'checkIndexedDBSupport',
                callback: (args) async {
                  debugPrint("✅ TEK DOSYA MODU IndexedDB desteği kontrolü: DESTEKLENİYOR");
                  return true;
                },
              );
              
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
                      'storageType': 'indexeddb-tek-dosya-modu',
                      'storagePath': tempDir.path,
                    });
                  } catch (e) {
                    debugPrint("❌ TEK DOSYA MODU Storage bilgisi hatası: $e");
                    return "{}";
                  }
                },
              );
              
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
                    'storageMode': 'indexeddb-tek-dosya-modu',
                    'packageName': _packageInfo.packageName,
                    'appVersion': _packageInfo.version,
                    'indexedDBVersion': '3.0-tek-dosya',
                    'maxFileSizeMB': 50,
                    'scanMode': 'single-file-no-duplicates',
                  });
                },
              );
            },
            onLoadStart: (controller, url) {
              final urlString = url.toString();
              debugPrint("🌐 TEK DOSYA MODU Sayfa yükleniyor: $urlString");
              
              final isViewer = urlString.contains("viewer.html");
              setState(() {
                _isViewerOpen = isViewer;
                _currentUrl = urlString;
              });
              
              if (urlString.contains("index.html") && !urlString.contains("about:blank")) {
                debugPrint("🏠 TEK DOSYA MODU index.html yükleniyor");
                Future.delayed(const Duration(milliseconds: 300), () async {
                  await controller.evaluateJavascript(source: """
                    (function() {
                      console.log("🧹 TEK DOSYA MODU index.html son temizlik...");
                      if (typeof PDFViewerApplication !== 'undefined') {
                        PDFViewerApplication = undefined;
                      }
                      if (typeof viewerPdfManager !== 'undefined') {
                        viewerPdfManager = undefined;
                      }
                      console.log("✅ TEK DOSYA MODU index.html temiz slate hazır");
                    })();
                  """);
                });
              }
            },
            onLoadStop: (controller, url) async {
              final urlString = url.toString();
              debugPrint("✅ TEK DOSYA MODU Sayfa yüklendi: $urlString");
              
              setState(() {
                _isViewerOpen = urlString.contains("viewer.html");
                _currentUrl = urlString;
              });
              
              await _checkAndUpdatePermissionStatus();
              
              await controller.evaluateJavascript(source: """
                (async function() {
                  try {
                    console.log("📦 TEK DOSYA MODU IndexedDB başlatılıyor...");
                    
                    if (typeof indexedDB === 'undefined') {
                      console.error("❌ CRITICAL: IndexedDB desteklenmiyor!");
                      return;
                    }
                    
                    if (typeof pdfManager !== 'undefined' && pdfManager.init) {
                      const success = await pdfManager.init();
                      console.log("📦 TEK DOSYA MODU Main IndexedDB Manager: " + (success ? "✅ Başarılı" : "❌ Başarısız"));
                      if (success) {
                        const info = await pdfManager.getStorageInfo();
                        if (info) {
                          console.log("💾 TEK DOSYA MODU Storage kullanımı: " + info.usedMB + " MB / " + info.quotaMB + " MB");
                        }
                      }
                    }
                    
                    if (typeof viewerPdfManager !== 'undefined' && viewerPdfManager.init) {
                      const success = await viewerPdfManager.init();
                      console.log("📦 TEK DOSYA MODU Viewer IndexedDB Manager: " + (success ? "✅ Başarılı" : "❌ Başarısız"));
                    }
                    
                    console.log("✅ TEK DOSYA MODU hazır - HER DOSYA TEK SEFER");
                  } catch (e) {
                    console.error("❌ TEK DOSYA MODU IndexedDB başlatma hatası:", e);
                  }
                })();
              """);
            },
            onConsoleMessage: (controller, consoleMessage) {
              final message = consoleMessage.message;
              final level = consoleMessage.messageLevel;
              
              String prefix = "📱 TEK DOSYA JS";
              if (level == ConsoleMessageLevel.ERROR) {
                prefix = "❌ TEK DOSYA JS ERROR";
              } else if (level == ConsoleMessageLevel.WARNING) {
                prefix = "⚠️ TEK DOSYA JS WARN";
              } else if (level == ConsoleMessageLevel.DEBUG) {
                prefix = "🐛 TEK DOSYA JS DEBUG";
              }
              
              debugPrint("$prefix: $message");
            },
            onLoadError: (controller, url, code, message) {
              debugPrint("❌ TEK DOSYA MODU Yükleme hatası: $message (code: $code)");
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ Yükleme hatası: $message'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            onLoadHttpError: (controller, url, statusCode, description) {
              debugPrint("❌ TEK DOSYA MODU HTTP hatası: $description (status: $statusCode)");
            },
            onPermissionRequest: (controller, permissionRequest) async {
              debugPrint("🔒 TEK DOSYA MODU İzin isteği: ${permissionRequest.resources}");
              return PermissionResponse(
                resources: permissionRequest.resources,
                action: PermissionResponseAction.GRANT,
              );
            },
            onProgressChanged: (controller, progress) {
              if (progress == 100) {
                debugPrint("✅ TEK DOSYA MODU Sayfa yükleme tamamlandı (%100)");
              }
            },
          ),
        ),
      ),
    );
  }
}
