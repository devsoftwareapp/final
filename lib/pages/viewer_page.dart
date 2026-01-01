import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/pdf_service.dart';
import 'dart:collection';
import 'dart:io';

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  InAppWebViewController? webViewController;
  late PDFService _pdfService;
  bool _isLoading = true;
  String _loadingMessage = 'PDF yükleniyor...';

  @override
  void initState() {
    super.initState();
    _pdfService = PDFService();
    debugPrint("📄 Viewer Page başlatıldı");
  }

  @override
  void dispose() {
    _cleanupViewer();
    super.dispose();
  }

  // ==================== VIEWER TEMİZLEME ====================
  Future<void> _cleanupViewer() async {
    debugPrint("🗑️ Viewer temizleniyor...");
    
    if (webViewController != null) {
      await webViewController!.evaluateJavascript(source: """
        (async function() {
          try {
            console.log("🗑️ Viewer IndexedDB ve storage temizleniyor...");
            
            // IndexedDB cleanup
            if (typeof viewerPdfManager !== 'undefined' && viewerPdfManager.cleanup) {
              await viewerPdfManager.cleanup();
              console.log("✅ Viewer: IndexedDB Manager temizlendi");
            }
            
            // Session storage temizle
            sessionStorage.clear();
            console.log("✅ Viewer: Session storage temizlendi");
            
            // Local storage'daki PDF verilerini temizle
            const keysToRemove = [];
            for (let i = 0; i < localStorage.length; i++) {
              const key = localStorage.key(i);
              if (key && (key.startsWith('last') || key.includes('Pdf') || key.includes('Blob'))) {
                keysToRemove.push(key);
              }
            }
            keysToRemove.forEach(key => localStorage.removeItem(key));
            console.log("✅ Viewer: Local storage temizlendi:", keysToRemove.length, "anahtar");
            
            // Tüm Blob URL'leri temizle
            if (typeof window.activeBlobUrls !== 'undefined') {
              window.activeBlobUrls.forEach(url => {
                try {
                  URL.revokeObjectURL(url);
                } catch (e) {}
              });
              window.activeBlobUrls = [];
              console.log("✅ Viewer: Blob URL'ler temizlendi");
            }
            
            // PDFViewerApplication'ı kapat
            if (typeof PDFViewerApplication !== 'undefined') {
              try {
                if (PDFViewerApplication.pdfDocument) {
                  await PDFViewerApplication.pdfDocument.destroy();
                  console.log("✅ Viewer: PDF Document destroy edildi");
                }
                if (PDFViewerApplication.close) {
                  await PDFViewerApplication.close();
                  console.log("✅ Viewer: PDF Viewer kapatıldı");
                }
              } catch (e) {
                console.log("⚠️ Viewer: PDF Viewer kapatma hatası:", e);
              }
            }
            
            console.log("✅ Viewer tamamen temizlendi (IndexedDB mode)");
            return true;
          } catch (e) {
            console.error("❌ Viewer temizleme hatası:", e);
            return false;
          }
        })();
      """);
    }
    
    // Flutter tarafındaki temp dosyaları temizle
    await _pdfService.cleanupTempFiles();
    
    debugPrint("✅ Viewer temizlendi");
  }

  // ==================== GERİ DÖN ====================
  Future<void> _goBack() async {
    debugPrint("⬅️ Viewer'dan index'e dönülüyor...");
    
    // Loading göster
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadingMessage = 'Kapatılıyor...';
      });
    }
    
    await _cleanupViewer();
    
    // Kısa bir gecikme (cleanup tamamlansın)
    await Future.delayed(const Duration(milliseconds: 300));
    
    if (mounted) {
      Navigator.pop(context);
    }
  }

  // ==================== LOADING GÖSTERİCİ ====================
  Widget _buildLoadingIndicator() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
              strokeWidth: 3,
            ),
            const SizedBox(height: 24),
            Text(
              _loadingMessage,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Lütfen bekleyin...',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _goBack();
        return false;
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              // WebView
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri("file:///android_asset/flutter_assets/assets/web/viewer.html"),
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
                  builtInZoomControls: true,
                  safeBrowsingEnabled: false,
                  sharedCookiesEnabled: true,
                  thirdPartyCookiesEnabled: true,
                  cacheEnabled: true,
                  clearCache: false,
                  supportZoom: true,
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
                      console.log("📄 Viewer Page - IndexedDB ArrayBuffer Mode");
                      console.log("📦 IndexedDB durumu:", typeof indexedDB !== 'undefined' ? 'Destekleniyor' : 'Desteklenmiyor');
                      
                      window.activeBlobUrls = window.activeBlobUrls || [];
                      
                      if (typeof indexedDB === 'undefined') {
                        console.error("❌ Viewer: IndexedDB desteklenmiyor!");
                      } else {
                        console.log("✅ Viewer: IndexedDB hazır");
                      }
                      
                      // Index'e dön fonksiyonu
                      window.goBackToIndex = function() {
                        console.log("⬅️ Viewer: Index'e dönülüyor");
                        window.flutter_inappwebview.callHandler('goBackToIndex');
                      };
                      
                      // Android interface mock
                      if (typeof Android === 'undefined') {
                        window.Android = {
                          openSettings: function() {
                            console.log("⚙️ Viewer: Ayarlar açılıyor");
                          }
                        };
                      }
                    """,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  ),
                ]),
                onWebViewCreated: (controller) {
                  webViewController = controller;
                  debugPrint("🌐 Viewer WebView oluşturuldu - IndexedDB Mode");

                  // ==================== HANDLER: INDEX'E DÖN ====================
                  controller.addJavaScriptHandler(
                    handlerName: 'goBackToIndex',
                    callback: (args) async {
                      debugPrint("⬅️ Viewer: goBackToIndex handler çağrıldı");
                      await _goBack();
                    },
                  );

                  // ==================== HANDLER: PDF PATH AL ====================
                  controller.addJavaScriptHandler(
                    handlerName: 'getPdfPath',
                    callback: (args) async {
                      try {
                        String sourcePath = args[0];
                        String fileName = args.length > 1 ? args[1] : sourcePath.split('/').last;
                        
                        debugPrint("📄 Viewer: PDF path istendi (IndexedDB için): $fileName");
                        
                        final tempPath = await _pdfService.getPdfPath(sourcePath, fileName);
                        
                        if (tempPath != null) {
                          debugPrint("✅ Viewer: PDF path hazır: $tempPath");
                          return tempPath;
                        } else {
                          debugPrint("❌ Viewer: PDF path alınamadı");
                          return null;
                        }
                      } catch (e) {
                        debugPrint("❌ Viewer: PDF path hatası: $e");
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
                        final size = await _pdfService.getFileSize(filePath);
                        debugPrint("📏 Viewer: Dosya boyutu: ${_pdfService.formatFileSize(size)}");
                        return size;
                      } catch (e) {
                        debugPrint("❌ Viewer: Dosya boyutu alma hatası: $e");
                        return 0;
                      }
                    },
                  );

                  // ==================== HANDLER: DOSYA OKU (BINARY) ====================
                  controller.addJavaScriptHandler(
                    handlerName: 'readPdfFile',
                    callback: (args) async {
                      try {
                        String filePath = args[0];
                        debugPrint("📖 Viewer: PDF dosyası okunuyor (IndexedDB için): $filePath");
                        
                        final bytes = await _pdfService.readPdfFile(filePath);
                        
                        if (bytes != null) {
                          final sizeInMB = bytes.length / (1024 * 1024);
                          debugPrint("✅ Viewer: PDF okundu: ${sizeInMB.toStringAsFixed(2)} MB - IndexedDB'ye gönderiliyor");
                          return bytes;
                        } else {
                          debugPrint("❌ Viewer: Dosya bulunamadı: $filePath");
                          return null;
                        }
                      } catch (e) {
                        debugPrint("❌ Viewer: Dosya okuma hatası: $e");
                        return null;
                      }
                    },
                  );

                  // ==================== HANDLER: PAYLAŞ ====================
                  controller.addJavaScriptHandler(
                    handlerName: 'sharePdf',
                    callback: (args) async {
                      try {
                        String filePath = args[0];
                        String? fileName = args.length > 1 ? args[1] : null;
                        
                        debugPrint("📤 Viewer: PDF paylaşılıyor: ${fileName ?? filePath}");
                        
                        await _pdfService.sharePdf(filePath, fileName);
                        debugPrint("✅ Viewer: PDF paylaşıldı");
                      } catch (e) {
                        debugPrint("❌ Viewer: Paylaşma hatası: $e");
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
                        
                        debugPrint("🖨️ Viewer: PDF yazdırılıyor: ${fileName ?? filePath}");
                        
                        await _pdfService.printPdf(context, filePath, fileName);
                        debugPrint("✅ Viewer: Yazdırma tamamlandı");
                      } catch (e) {
                        debugPrint("❌ Viewer: Yazdırma hatası: $e");
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
                        
                        debugPrint("💾 Viewer: PDF indiriliyor: ${fileName ?? sourcePath}");
                        
                        await _pdfService.downloadPdf(context, sourcePath, fileName);
                      } catch (e) {
                        debugPrint("❌ Viewer: İndirme hatası: $e");
                      }
                    },
                  );

                  // ==================== HANDLER: INDEXEDDB DESTEK KONTROLÜ ====================
                  controller.addJavaScriptHandler(
                    handlerName: 'checkIndexedDBSupport',
                    callback: (args) async {
                      debugPrint("✅ Viewer: IndexedDB desteği kontrolü");
                      return true;
                    },
                  );
                },
                onLoadStart: (controller, url) {
                  debugPrint("🌐 Viewer: Sayfa yükleniyor: ${url.toString()}");
                  if (mounted) {
                    setState(() {
                      _isLoading = true;
                      _loadingMessage = 'PDF yükleniyor...';
                    });
                  }
                },
                onLoadStop: (controller, url) async {
                  debugPrint("✅ Viewer: Sayfa yüklendi: ${url.toString()}");
                  
                  // IndexedDB'yi başlat ve PDF'i yükle
                  await controller.evaluateJavascript(source: """
                    (async function() {
                      try {
                        console.log("📦 Viewer: IndexedDB başlatılıyor...");
                        
                        if (typeof indexedDB === 'undefined') {
                          console.error("❌ Viewer: IndexedDB desteklenmiyor!");
                          return;
                        }
                        
                        if (typeof viewerPdfManager !== 'undefined' && viewerPdfManager.init) {
                          const success = await viewerPdfManager.init();
                          console.log("📦 Viewer IndexedDB Manager: " + (success ? "✅ Başarılı" : "❌ Başarısız"));
                          
                          if (success) {
                            console.log("📄 Viewer: PDF yükleniyor...");
                            
                            if (typeof loadPdfIntoViewer === 'function') {
                              await loadPdfIntoViewer();
                              console.log("✅ Viewer: PDF yükleme fonksiyonu çağrıldı");
                            } else {
                              console.error("❌ Viewer: loadPdfIntoViewer fonksiyonu bulunamadı!");
                            }
                          }
                        } else {
                          console.error("❌ Viewer: viewerPdfManager bulunamadı!");
                        }
                        
                        console.log("✅ Viewer: IndexedDB hazır (ArrayBuffer mode)");
                        
                      } catch (e) {
                        console.error("❌ Viewer: IndexedDB başlatma hatası:", e);
                      }
                    })();
                  """);
                  
                  // Loading'i kapat
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                },
                onProgressChanged: (controller, progress) {
                  debugPrint("📊 Viewer: Yükleme %$progress");
                  
                  if (mounted && progress < 100) {
                    setState(() {
                      _loadingMessage = 'Yükleniyor... %$progress';
                    });
                  }
                },
                onConsoleMessage: (controller, consoleMessage) {
                  final message = consoleMessage.message;
                  final level = consoleMessage.messageLevel;
                  
                  String prefix = "📄 VIEWER JS";
                  if (level == ConsoleMessageLevel.ERROR) {
                    prefix = "❌ VIEWER ERROR";
                  } else if (level == ConsoleMessageLevel.WARNING) {
                    prefix = "⚠️ VIEWER WARN";
                  } else if (level == ConsoleMessageLevel.DEBUG) {
                    prefix = "🐛 VIEWER DEBUG";
                  }
                  
                  debugPrint("$prefix: $message");
                },
                onLoadError: (controller, url, code, message) {
                  debugPrint("❌ Viewer: Yükleme hatası: $message (code: $code)");
                  
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('❌ Yükleme hatası: $message'),
                        backgroundColor: Colors.red,
                        action: SnackBarAction(
                          label: 'Geri',
                          textColor: Colors.white,
                          onPressed: () => _goBack(),
                        ),
                      ),
                    );
                  }
                },
                onLoadHttpError: (controller, url, statusCode, description) {
                  debugPrint("❌ Viewer: HTTP hatası: $description (status: $statusCode)");
                },
                onPermissionRequest: (controller, permissionRequest) async {
                  debugPrint("🔒 Viewer: İzin isteği: ${permissionRequest.resources}");
                  return PermissionResponse(
                    resources: permissionRequest.resources,
                    action: PermissionResponseAction.GRANT,
                  );
                },
              ),
              
              // Loading Overlay
              if (_isLoading)
                _buildLoadingIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}


