import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/pdf_service.dart';
import '../services/permission_service.dart';
import 'viewer_page.dart';
import 'dart:collection';

class IndexPage extends StatefulWidget {
  const IndexPage({super.key});

  @override
  State<IndexPage> createState() => _IndexPageState();
}

class _IndexPageState extends State<IndexPage> with WidgetsBindingObserver {
  InAppWebViewController? webViewController;
  DateTime? _lastBackPressTime;
  
  late PDFService _pdfService;
  late PermissionService _permissionService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pdfService = PDFService();
    _permissionService = PermissionService();
    debugPrint("🏠 Index Page başlatıldı");
  }

  @override
  void dispose() {
    _pdfService.cleanupTempFiles();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("📱 Index: Uygulama geri döndü");
      _checkAndUpdatePermissionStatus();
    }
  }

  Future<void> _checkAndUpdatePermissionStatus() async {
    if (webViewController == null) return;
    
    await webViewController!.evaluateJavascript(source: """
      (function() {
        console.log("📱 Index: İzin durumu güncelleniyor");
        if (typeof onAndroidResume === 'function') {
          onAndroidResume();
        }
        if (typeof scanDeviceForPDFs === 'function') {
          setTimeout(() => scanDeviceForPDFs(), 500);
        }
      })();
    """);
  }

  Future<void> _navigateToViewer(String pdfName) async {
    debugPrint("🔄 Viewer'a geçiş: $pdfName");
    
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ViewerPage()),
      );
      
      debugPrint("🔙 Viewer'dan dönüldü");
      _checkAndUpdatePermissionStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (webViewController != null) {
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
                  console.log("🏠 Index Page - IndexedDB ArrayBuffer Mode");
                  console.log("📦 IndexedDB durumu:", typeof indexedDB !== 'undefined' ? 'Destekleniyor' : 'Desteklenmiyor');
                  
                  window.activeBlobUrls = window.activeBlobUrls || [];
                  
                  if (typeof indexedDB === 'undefined') {
                    console.error("❌ IndexedDB desteklenmiyor!");
                  } else {
                    console.log("✅ IndexedDB hazır");
                  }
                  
                  window.navigateToViewer = function(pdfName) {
                    console.log("📄 Viewer'a geçiliyor:", pdfName);
                    window.flutter_inappwebview.callHandler('navigateToViewer', pdfName);
                  };
                  
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
              debugPrint("🌐 Index WebView oluşturuldu - IndexedDB Mode");

              // ==================== HANDLER: VIEWER'A GEÇİŞ ====================
              controller.addJavaScriptHandler(
                handlerName: 'navigateToViewer',
                callback: (args) async {
                  String pdfName = args.isNotEmpty ? args[0] : "belge.pdf";
                  await _navigateToViewer(pdfName);
                },
              );

              // ==================== HANDLER: İZİN KONTROLÜ ====================
              controller.addJavaScriptHandler(
                handlerName: 'checkStoragePermission',
                callback: (args) async {
                  final hasPermission = await _permissionService.checkStoragePermission();
                  debugPrint("🔒 Index: İzin kontrolü: $hasPermission");
                  return hasPermission;
                },
              );

              // ==================== HANDLER: İZİN İSTE ====================
              controller.addJavaScriptHandler(
                handlerName: 'requestStoragePermission',
                callback: (args) async {
                  debugPrint("🔒 Index: İzin isteniyor...");
                  final granted = await _permissionService.requestStoragePermission();
                  debugPrint("🔒 Index: İzin sonucu: $granted");
                  return granted;
                },
              );

              // ==================== HANDLER: PDF LİSTESİ ====================
              controller.addJavaScriptHandler(
                handlerName: 'listPdfFiles',
                callback: (args) async {
                  debugPrint("📋 Index: PDF listesi istendi");
                  try {
                    final jsonResult = await _pdfService.listPdfFiles();
                    debugPrint("✅ Index: PDF listesi hazır");
                    return jsonResult;
                  } catch (e) {
                    debugPrint("❌ Index: PDF listeleme hatası: $e");
                    return "[]";
                  }
                },
              );

              // ==================== HANDLER: PDF PATH AL ====================
              controller.addJavaScriptHandler(
                handlerName: 'getPdfPath',
                callback: (args) async {
                  try {
                    String sourcePath = args[0];
                    String fileName = args.length > 1 ? args[1] : sourcePath.split('/').last;
                    
                    debugPrint("📄 Index: PDF path istendi (IndexedDB için): $fileName");
                    
                    final tempPath = await _pdfService.getPdfPath(sourcePath, fileName);
                    
                    if (tempPath != null) {
                      debugPrint("✅ Index: PDF path hazır: $tempPath");
                      return tempPath;
                    } else {
                      debugPrint("❌ Index: PDF path alınamadı");
                      return null;
                    }
                  } catch (e) {
                    debugPrint("❌ Index: PDF path hatası: $e");
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
                      debugPrint("📏 Index: Dosya boyutu: ${_pdfService.formatFileSize(stat.size)}");
                      return stat.size;
                    }
                  } catch (e) {
                    debugPrint("❌ Index: Dosya boyutu alma hatası: $e");
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
                    debugPrint("📖 Index: PDF dosyası okunuyor (IndexedDB için): $filePath");
                    
                    final bytes = await _pdfService.readPdfFile(filePath);
                    
                    if (bytes != null) {
                      final sizeInMB = bytes.length / (1024 * 1024);
                      debugPrint("✅ Index: PDF okundu: ${sizeInMB.toStringAsFixed(2)} MB - IndexedDB'ye gönderiliyor");
                      return bytes;
                    } else {
                      debugPrint("❌ Index: Dosya bulunamadı: $filePath");
                      return null;
                    }
                  } catch (e) {
                    debugPrint("❌ Index: Dosya okuma hatası: $e");
                    return null;
                  }
                },
              );

              // ==================== HANDLER: AYARLARI AÇ ====================
              controller.addJavaScriptHandler(
                handlerName: 'openSettingsForPermission',
                callback: (args) async {
                  debugPrint("⚙️ Index: Ayarlar açılıyor...");
                  await _permissionService.openAppSettings();
                },
              );

              // ==================== HANDLER: PAYLAŞ ====================
              controller.addJavaScriptHandler(
                handlerName: 'sharePdf',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    String? fileName = args.length > 1 ? args[1] : null;
                    
                    debugPrint("📤 Index: PDF paylaşılıyor: ${fileName ?? filePath}");
                    
                    await _pdfService.sharePdf(filePath, fileName);
                    debugPrint("✅ Index: PDF paylaşıldı");
                  } catch (e) {
                    debugPrint("❌ Index: Paylaşma hatası: $e");
                  }
                },
              );

              // ==================== HANDLER: YAZDIR ====================
              controller.addJavaScriptHandler(
                handlerName: 'printPdf',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    String? fileName = args.length > 1 ? args[1] : null;
                    
                    debugPrint("🖨️ Index: PDF yazdırılıyor: ${fileName ?? filePath}");
                    
                    await _pdfService.printPdf(context, filePath, fileName);
                    debugPrint("✅ Index: Yazdırma tamamlandı");
                  } catch (e) {
                    debugPrint("❌ Index: Yazdırma hatası: $e");
                  }
                },
              );

              // ==================== HANDLER: İNDİR ====================
              controller.addJavaScriptHandler(
                handlerName: 'downloadPdf',
                callback: (args) async {
                  try {
                    String sourcePath = args[0];
                    String? fileName = args.length > 1 ? args[1] : null;
                    
                    debugPrint("💾 Index: PDF indiriliyor: ${fileName ?? sourcePath}");
                    
                    await _pdfService.downloadPdf(context, sourcePath, fileName);
                  } catch (e) {
                    debugPrint("❌ Index: İndirme hatası: $e");
                  }
                },
              );

              // ==================== HANDLER: INDEXEDDB DESTEK KONTROLÜ ====================
              controller.addJavaScriptHandler(
                handlerName: 'checkIndexedDBSupport',
                callback: (args) async {
                  debugPrint("✅ Index: IndexedDB desteği kontrolü");
                  return true;
                },
              );

              // ==================== HANDLER: STORAGE BİLGİSİ ====================
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
                      'maxPdfSize': 100,
                      'storageType': 'indexeddb-arraybuffer'
                    });
                  } catch (e) {
                    debugPrint("❌ Index: Storage bilgisi hatası: $e");
                    return "{}";
                  }
                },
              );
            },
            onLoadStart: (controller, url) {
              debugPrint("🌐 Index: Sayfa yükleniyor: ${url.toString()}");
            },
            onLoadStop: (controller, url) async {
              debugPrint("✅ Index: Sayfa yüklendi: ${url.toString()}");
              
              await _checkAndUpdatePermissionStatus();
              
              // IndexedDB'yi başlat
              await controller.evaluateJavascript(source: """
                (async function() {
                  try {
                    console.log("📦 Index: IndexedDB başlatılıyor...");
                    
                    if (typeof indexedDB === 'undefined') {
                      console.error("❌ Index: IndexedDB desteklenmiyor!");
                      return;
                    }
                    
                    if (typeof pdfManager !== 'undefined' && pdfManager.init) {
                      const success = await pdfManager.init();
                      console.log("📦 Index IndexedDB Manager: " + (success ? "✅ Başarılı" : "❌ Başarısız"));
                      
                      if (success) {
                        const info = await pdfManager.getStorageInfo();
                        if (info) {
                          console.log("💾 Index Storage kullanımı: " + info.usedMB + " MB / " + info.quotaMB + " MB");
                        }
                      }
                    }
                    
                    console.log("✅ Index: IndexedDB hazır (ArrayBuffer mode)");
                    
                  } catch (e) {
                    console.error("❌ Index: IndexedDB başlatma hatası:", e);
                  }
                })();
              """);
            },
            onConsoleMessage: (controller, consoleMessage) {
              final message = consoleMessage.message;
              final level = consoleMessage.messageLevel;
              
              String prefix = "🏠 INDEX JS";
              if (level == ConsoleMessageLevel.ERROR) {
                prefix = "❌ INDEX ERROR";
              } else if (level == ConsoleMessageLevel.WARNING) {
                prefix = "⚠️ INDEX WARN";
              } else if (level == ConsoleMessageLevel.DEBUG) {
                prefix = "🐛 INDEX DEBUG";
              }
              
              debugPrint("$prefix: $message");
            },
            onLoadError: (controller, url, code, message) {
              debugPrint("❌ Index: Yükleme hatası: $message (code: $code)");
              
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
              debugPrint("❌ Index: HTTP hatası: $description (status: $statusCode)");
            },
            onPermissionRequest: (controller, permissionRequest) async {
              debugPrint("🔒 Index: İzin isteği: ${permissionRequest.resources}");
              return PermissionResponse(
                resources: permissionRequest.resources,
                action: PermissionResponseAction.GRANT,
              );
            },
            onProgressChanged: (controller, progress) {
              if (progress == 100) {
                debugPrint("✅ Index: Sayfa yükleme tamamlandı (%100)");
              }
            },
          ),
        ),
      ),
    );
  }
}

