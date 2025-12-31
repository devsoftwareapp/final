import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
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
  
  // OPFS için geçici dosya takibi
  final Map<String, String> _tempFiles = {}; // PDF name -> temp path

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPackageInfo();
    debugPrint("🚀 PDF Reader başlatıldı - FULL OPFS MODE");
  }

  Future<void> _initPackageInfo() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  @override
  void dispose() {
    _cleanupTempFiles();
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

  // Temp dosyaları temizle
  Future<void> _cleanupTempFiles() async {
    for (var path in _tempFiles.values) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint("⚠️ Temp dosya silinemedi: $e");
      }
    }
    _tempFiles.clear();
  }

  // İzin durumunu kontrol et ve JS'e bildir
  Future<void> _checkAndUpdatePermissionStatus() async {
    if (webViewController == null) return;
    
    final hasPermission = await _checkStoragePermission();
    debugPrint("🔒 İzin durumu: $hasPermission");
    
    await webViewController!.evaluateJavascript(source: """
      (function() {
        console.log("📱 Android resume - izin durumu güncelleniyor");
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

  // Storage izin kontrolü
  Future<bool> _checkStoragePermission() async {
    if (Platform.isAndroid) {
      final android13Permissions = await Future.wait([
        Permission.photos.status,
        Permission.videos.status,
        Permission.audio.status,
      ]);
      
      if (android13Permissions.any((status) => status.isGranted)) {
        return true;
      }
      
      final manageStorageStatus = await Permission.manageExternalStorage.status;
      if (manageStorageStatus.isGranted) {
        return true;
      }
      
      final storageStatus = await Permission.storage.status;
      if (storageStatus.isGranted) {
        return true;
      }
      
      return false;
    }
    return true;
  }

  // Cihazdan PDF dosyalarını listele
  Future<List<Map<String, dynamic>>> _listPdfFiles() async {
    List<Map<String, dynamic>> pdfFiles = [];
    
    try {
      if (Platform.isAndroid) {
        debugPrint("📂 PDF dosyaları taranıyor...");
        
        List<String> searchPaths = [
          '/storage/emulated/0/Download',
          '/storage/emulated/0/Documents',
          '/storage/emulated/0/DCIM',
          '/storage/emulated/0/Downloads',
          '/storage/emulated/0',
          '/sdcard/Download',
          '/sdcard/Documents',
        ];

        int totalFound = 0;
        
        for (String path in searchPaths) {
          try {
            final directory = Directory(path);
            if (await directory.exists()) {
              await _scanDirectoryRecursive(directory, pdfFiles);
              totalFound = pdfFiles.length;
            }
          } catch (e) {
            debugPrint("⚠️ Dizin tarama hatası: $path - $e");
            continue;
          }
        }
        
        debugPrint("✅ Toplam $totalFound PDF dosyası bulundu");
        pdfFiles.sort((a, b) => b['size'].compareTo(a['size']));
      }
    } catch (e) {
      debugPrint("❌ PDF listeleme hatası: $e");
    }
    
    return pdfFiles;
  }

  // Dizini recursive olarak tara
  Future<void> _scanDirectoryRecursive(
    Directory directory, 
    List<Map<String, dynamic>> pdfFiles
  ) async {
    try {
      final contents = directory.list(recursive: false);
      
      await for (var entity in contents) {
        if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
          try {
            final stat = await entity.stat();
            final sizeInMB = stat.size / (1024 * 1024);
            
            if (sizeInMB > 500) {
              debugPrint("⚠️ Çok büyük dosya atlandı: ${entity.path} (${sizeInMB.toStringAsFixed(2)} MB)");
              continue;
            }
            
            pdfFiles.add({
              'path': entity.path,
              'name': entity.path.split('/').last,
              'size': stat.size,
              'modified': stat.modified.toIso8601String(),
              'sizeMB': sizeInMB,
            });
            
          } catch (e) {
            debugPrint("⚠️ Dosya bilgisi alınamadı: ${entity.path}");
          }
        } else if (entity is Directory) {
          final dirName = entity.path.split('/').last.toLowerCase();
          if (!dirName.startsWith('.') && 
              dirName != 'android' && 
              dirName != 'lost+found' &&
              !dirName.contains('cache')) {
            await _scanDirectoryRecursive(entity, pdfFiles);
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Dizin tarama hatası (${directory.path}): $e");
    }
  }

  // Dosya boyutunu formatla
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // PDF'i geçici dizine kopyala ve path döndür (OPFS için)
  Future<String?> _copyPdfToTemp(String sourcePath, String fileName) async {
    try {
      debugPrint("📋 PDF temp'e kopyalanıyor: $fileName");
      
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        debugPrint("❌ Kaynak dosya bulunamadı: $sourcePath");
        return null;
      }
      
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$fileName';
      final tempFile = File(tempPath);
      
      // Eğer temp'te varsa ve güncel ise tekrar kopyalama
      if (await tempFile.exists()) {
        final sourceStat = await sourceFile.stat();
        final tempStat = await tempFile.stat();
        
        if (sourceStat.size == tempStat.size && 
            sourceStat.modified.isBefore(tempStat.modified.add(const Duration(minutes: 5)))) {
          debugPrint("✅ Temp dosya güncel, kopyalama atlandı");
          _tempFiles[fileName] = tempPath;
          return tempPath;
        }
      }
      
      // Dosyayı kopyala
      await sourceFile.copy(tempPath);
      _tempFiles[fileName] = tempPath;
      
      debugPrint("✅ PDF temp'e kopyalandı: $tempPath");
      return tempPath;
      
    } catch (e) {
      debugPrint("❌ Temp kopyalama hatası: $e");
      return null;
    }
  }

  // Viewer'ı tamamen resetle ve index.html'e dön
  Future<void> _resetViewerAndGoBack() async {
    if (webViewController == null) return;
    
    debugPrint("🔄 Viewer resetleniyor...");
    
    try {
      // 1. OPFS ve tüm storage'ı temizle
      await webViewController!.evaluateJavascript(source: """
        (async function() {
          try {
            console.log("🗑️ Viewer tamamen temizleniyor...");
            
            // OPFS cleanup
            if (typeof viewerPdfManager !== 'undefined' && viewerPdfManager.cleanup) {
              await viewerPdfManager.cleanup();
              console.log("✅ OPFS temizlendi");
            }
            
            // Session storage temizle
            sessionStorage.clear();
            
            // Local storage'daki PDF verilerini temizle
            const keysToRemove = [];
            for (let i = 0; i < localStorage.length; i++) {
              const key = localStorage.key(i);
              if (key && (key.startsWith('pdf_') || key.includes('chunk'))) {
                keysToRemove.push(key);
              }
            }
            keysToRemove.forEach(key => localStorage.removeItem(key));
            
            // Tüm Blob URL'leri temizle
            if (typeof window.activeBlobUrls !== 'undefined') {
              window.activeBlobUrls.forEach(url => {
                try {
                  URL.revokeObjectURL(url);
                } catch (e) {}
              });
              window.activeBlobUrls = [];
            }
            
            // PDFViewerApplication'ı kapat
            if (typeof PDFViewerApplication !== 'undefined') {
              try {
                if (PDFViewerApplication.pdfDocument) {
                  await PDFViewerApplication.pdfDocument.destroy();
                }
                if (PDFViewerApplication.close) {
                  await PDFViewerApplication.close();
                }
              } catch (e) {
                console.log("⚠️ PDF Viewer kapatma hatası:", e);
              }
            }
            
            console.log("✅ Viewer tamamen temizlendi ve resetlendi");
            return true;
          } catch (e) {
            console.error("❌ Viewer temizleme hatası:", e);
            return false;
          }
        })();
      """);
      
      // 2. Flutter tarafındaki temp dosyaları temizle
      await _cleanupTempFiles();
      
      // 3. index.html'e geri dön
      await webViewController!.loadUrl(
        urlRequest: URLRequest(
          url: WebUri("file:///android_asset/flutter_assets/assets/web/index.html"),
        ),
      );
      
      // 4. State'i güncelle
      setState(() {
        _isViewerOpen = false;
        _currentUrl = 'index.html';
      });
      
      debugPrint("✅ index.html'e geri dönüldü ve viewer resetlendi");
      
      // 5. PDF listesini yeniden yükle
      await Future.delayed(const Duration(milliseconds: 500), () async {
        await webViewController!.evaluateJavascript(source: """
          (function() {
            if (typeof scanDeviceForPDFs === 'function') {
              scanDeviceForPDFs();
              console.log("🔄 PDF listesi yenilendi");
            }
          })();
        """);
      });
      
    } catch (e) {
      debugPrint("❌ Viewer reset hatası: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (webViewController != null) {
          // Viewer açıksa
          if (_isViewerOpen) {
            debugPrint("⬅️ Viewer'dan geri dönülüyor...");
            
            // Viewer'ı resetle ve index.html'e dön
            await _resetViewerAndGoBack();
            
            return false;
          } 
          // Index.html'de isek
          else {
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
              displayZoomControls: false,
              builtInZoomControls: false,
              safeBrowsingEnabled: false,
              // OPFS desteği için kritik
              sharedCookiesEnabled: true,
              thirdPartyCookiesEnabled: true,
              cacheEnabled: true,
              clearCache: false,
              supportZoom: false,
              disableVerticalScroll: false,
              disableHorizontalScroll: false,
              hardwareAcceleration: true,
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              // Büyük dosyalar için ek ayarlar
              transparentBackground: false,
              disableContextMenu: false,
              incognito: false,
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: """
                  console.log("🚀 Flutter WebView başlatılıyor - FULL OPFS MODE");
                  
                  // Blob URL takibi
                  window.activeBlobUrls = window.activeBlobUrls || [];
                  
                  // OPFS desteği kontrolü
                  if (typeof navigator.storage !== 'undefined' && navigator.storage.getDirectory) {
                    console.log("✅ OPFS destekleniyor - Native OPFS kullanılacak");
                  } else {
                    console.log("❌ OPFS desteklenmiyor - IndexedDB fallback");
                  }
                  
                  // Android interface mock (eski kod ile uyumluluk için)
                  if (typeof Android === 'undefined') {
                    window.Android = {
                      openSettings: function() {
                        window.flutter_inappwebview.callHandler('openSettingsForPermission');
                      }
                    };
                  }
                """,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            onWebViewCreated: (controller) {
              webViewController = controller;
              debugPrint("🌐 WebView oluşturuldu - OPFS aktif");

              // ==================== HANDLER: İZİN DURUMU ====================
              controller.addJavaScriptHandler(
                handlerName: 'checkStoragePermission',
                callback: (args) async {
                  final hasPermission = await _checkStoragePermission();
                  debugPrint("🔒 İzin kontrolü: $hasPermission");
                  return hasPermission;
                },
              );

              // ==================== HANDLER: PDF LİSTESİ ====================
              controller.addJavaScriptHandler(
                handlerName: 'listPdfFiles',
                callback: (args) async {
                  debugPrint("📋 PDF listesi istendi");
                  try {
                    final pdfFiles = await _listPdfFiles();
                    final jsonResult = jsonEncode(pdfFiles);
                    debugPrint("✅ PDF listesi hazır: ${pdfFiles.length} dosya");
                    return jsonResult;
                  } catch (e) {
                    debugPrint("❌ PDF listeleme hatası: $e");
                    return "[]";
                  }
                },
              );

              // ==================== HANDLER: PDF PATH AL (OPFS İÇİN) ====================
              controller.addJavaScriptHandler(
                handlerName: 'getPdfPath',
                callback: (args) async {
                  try {
                    String sourcePath = args[0];
                    String fileName = args.length > 1 ? args[1] : sourcePath.split('/').last;
                    
                    debugPrint("📄 PDF path istendi: $fileName");
                    
                    final tempPath = await _copyPdfToTemp(sourcePath, fileName);
                    
                    if (tempPath != null) {
                      debugPrint("✅ PDF path hazır: $tempPath");
                      return tempPath;
                    } else {
                      debugPrint("❌ PDF path alınamadı");
                      return null;
                    }
                  } catch (e) {
                    debugPrint("❌ PDF path hatası: $e");
                    return null;
                  }
                },
              );

              // ==================== HANDLER: DOSYA BOYUTU ====================
              controller.addJavaScriptHandler(
                handlerName: 'getFileSize',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      final stat = await file.stat();
                      debugPrint("📏 Dosya boyutu: ${_formatFileSize(stat.size)}");
                      return stat.size;
                    }
                  } catch (e) {
                    debugPrint("❌ Dosya boyutu alma hatası: $e");
                  }
                  return 0;
                },
              );

              // ==================== HANDLER: DOSYA OKU (BINARY) ====================
              controller.addJavaScriptHandler(
                handlerName: 'readPdfFile',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    debugPrint("📖 PDF dosyası okunuyor: $filePath");
                    
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      final bytes = await file.readAsBytes();
                      final sizeInMB = bytes.length / (1024 * 1024);
                      debugPrint("✅ PDF okundu: ${sizeInMB.toStringAsFixed(2)} MB");
                      
                      // Uint8List olarak döndür (OPFS için)
                      return bytes;
                    } else {
                      debugPrint("❌ Dosya bulunamadı: $filePath");
                      return null;
                    }
                  } catch (e) {
                    debugPrint("❌ Dosya okuma hatası: $e");
                    return null;
                  }
                },
              );

              // ==================== HANDLER: AYARLARI AÇ ====================
              controller.addJavaScriptHandler(
                handlerName: 'openSettingsForPermission',
                callback: (args) async {
                  debugPrint("⚙️ Ayarlar açılıyor...");
                  if (Platform.isAndroid) {
                    try {
                      final packageName = _packageInfo.packageName;
                      final intent = AndroidIntent(
                        action: 'android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION',
                        data: 'package:$packageName',
                        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
                      );
                      await intent.launch();
                    } catch (e) {
                      await openAppSettings();
                    }
                  }
                },
              );

              // ==================== HANDLER: PAYLAŞ (PATH İLE) ====================
              controller.addJavaScriptHandler(
                handlerName: 'sharePdf',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    String fileName = args.length > 1 ? args[1] : filePath.split('/').last;
                    
                    debugPrint("📤 PDF paylaşılıyor: $fileName");
                    
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      await Share.shareXFiles([XFile(file.path)], text: fileName);
                      debugPrint("✅ PDF paylaşıldı");
                    } else {
                      debugPrint("❌ Dosya bulunamadı: $filePath");
                    }
                  } catch (e) {
                    debugPrint("❌ Paylaşma hatası: $e");
                  }
                },
              );

              // ==================== HANDLER: YAZDIR (PATH İLE) ====================
              controller.addJavaScriptHandler(
                handlerName: 'printPdf',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    String fileName = args.length > 1 ? args[1] : filePath.split('/').last;
                    
                    debugPrint("🖨️ PDF yazdırılıyor: $fileName");
                    
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      final bytes = await file.readAsBytes();
                      await Printing.layoutPdf(
                        onLayout: (format) async => bytes,
                        name: fileName,
                      );
                      debugPrint("✅ Yazdırma tamamlandı");
                    } else {
                      debugPrint("❌ Dosya bulunamadı: $filePath");
                    }
                  } catch (e) {
                    debugPrint("❌ Yazdırma hatası: $e");
                    
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ Yazdırma hatası: ${e.toString()}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              );

              // ==================== HANDLER: İNDİR (PATH İLE) ====================
              controller.addJavaScriptHandler(
                handlerName: 'downloadPdf',
                callback: (args) async {
                  try {
                    String sourcePath = args[0];
                    String fileName = args.length > 1 ? args[1] : sourcePath.split('/').last;
                    
                    debugPrint("💾 PDF indiriliyor: $fileName");
                    
                    final sourceFile = File(sourcePath);
                    
                    if (await sourceFile.exists()) {
                      Directory? directory;
                      if (Platform.isAndroid) {
                        directory = Directory('/storage/emulated/0/Download');
                        if (!await directory.exists()) {
                          directory = Directory('/storage/emulated/0/Downloads');
                        }
                      } else {
                        directory = await getApplicationDocumentsDirectory();
                      }

                      if (directory != null && await directory.exists()) {
                        int counter = 1;
                        String finalName = fileName;
                        String nameWithoutExt = fileName.replaceAll('.pdf', '');
                        File targetFile = File('${directory.path}/$finalName');
                        
                        while (await targetFile.exists()) {
                          finalName = '$nameWithoutExt ($counter).pdf';
                          targetFile = File('${directory.path}/$finalName');
                          counter++;
                        }
                        
                        await sourceFile.copy(targetFile.path);
                        debugPrint("✅ PDF indirildi: ${targetFile.path}");

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
                    } else {
                      debugPrint("❌ Kaynak dosya bulunamadı: $sourcePath");
                    }
                  } catch (e) {
                    debugPrint("❌ İndirme hatası: $e");
                    
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

              // ==================== HANDLER: OPFS DESTEK KONTROLÜ ====================
              controller.addJavaScriptHandler(
                handlerName: 'checkOPFSSupport',
                callback: (args) async {
                  debugPrint("✅ OPFS desteği aktif");
                  return true;
                },
              );
              
              // ==================== HANDLER: UYGULAMA DURUMU ====================
              controller.addJavaScriptHandler(
                handlerName: 'getAppStatus',
                callback: (args) async {
                  return jsonEncode({
                    'platform': Platform.operatingSystem,
                    'version': Platform.operatingSystemVersion,
                    'storageAvailable': await _checkStoragePermission(),
                    'tempDir': (await getTemporaryDirectory()).path,
                    'appDir': (await getApplicationDocumentsDirectory()).path,
                    'opfsSupported': true,
                  });
                },
              );
            },
            onLoadStart: (controller, url) {
              final urlString = url.toString();
              debugPrint("🌐 Sayfa yükleniyor: $urlString");
              setState(() {
                _isViewerOpen = urlString.contains("viewer.html");
                _currentUrl = urlString;
              });
            },
            onLoadStop: (controller, url) async {
              final urlString = url.toString();
              debugPrint("✅ Sayfa yüklendi: $urlString");
              
              setState(() {
                _isViewerOpen = urlString.contains("viewer.html");
                _currentUrl = urlString;
              });
              
              // İzin durumunu kontrol et
              await _checkAndUpdatePermissionStatus();
              
              // OPFS'i başlat
              await controller.evaluateJavascript(source: """
                (async function() {
                  try {
                    if (typeof navigator.storage !== 'undefined' && navigator.storage.getDirectory) {
                      console.log("✅ OPFS aktif - initialize ediliyor");
                      
                      // index.html için
                      if (typeof pdfManager !== 'undefined' && pdfManager.init) {
                        const success = await pdfManager.init();
                        console.log("📦 Index OPFS Manager: " + (success ? "Başarılı" : "Başarısız"));
                      }
                      
                      // viewer.html için
                      if (typeof viewerPdfManager !== 'undefined' && viewerPdfManager.init) {
                        const success = await viewerPdfManager.init();
                        console.log("📦 Viewer OPFS Manager: " + (success ? "Başarılı" : "Başarısız"));
                      }
                    } else {
                      console.log("⚠️ OPFS desteklenmiyor, IndexedDB fallback kullanılacak");
                    }
                  } catch (e) {
                    console.error("❌ OPFS başlatma hatası:", e);
                  }
                })();
              """);
            },
            onConsoleMessage: (controller, consoleMessage) {
              final message = consoleMessage.message;
              final level = consoleMessage.messageLevel;
              
              String prefix = "📱 JS";
              if (level == ConsoleMessageLevel.ERROR) {
                prefix = "❌ JS ERROR";
              } else if (level == ConsoleMessageLevel.WARNING) {
                prefix = "⚠️ JS WARN";
              } else if (level == ConsoleMessageLevel.DEBUG) {
                prefix = "🐛 JS DEBUG";
              }
              
              debugPrint("$prefix: $message");
            },
            onLoadError: (controller, url, code, message) {
              debugPrint("❌ Yükleme hatası: $message (code: $code)");
              
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
              debugPrint("❌ HTTP hatası: $description (status: $statusCode)");
            },
            onPermissionRequest: (controller, permissionRequest) async {
              debugPrint("🔒 İzin isteği: ${permissionRequest.resources}");
              return PermissionResponse(
                resources: permissionRequest.resources,
                action: PermissionResponseAction.GRANT,
              );
            },
            onProgressChanged: (controller, progress) {
              if (progress == 100) {
                debugPrint("✅ Sayfa yükleme tamamlandı (%100)");
              }
            },
          ),
        ),
      ),
    );
  }
}


