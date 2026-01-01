import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  InAppWebViewController? webViewController;
  bool _isLoading = true;
  String _loadingMessage = 'PDF yükleniyor...';
  final GlobalKey _webViewKey = GlobalKey();
  
  // PDF Verisi
  Uint8List? _currentPdfData;
  String? _currentPdfName;
  int? _currentPdfSize;

  @override
  void initState() {
    super.initState();
    debugPrint("📄 Viewer Page başlatıldı");
    _initializeViewer();
  }

  @override
  void dispose() {
    _cleanupViewer();
    super.dispose();
  }

  // ==================== İNİTİALİZE ====================
  Future<void> _initializeViewer() async {
    debugPrint("🔄 Viewer başlatılıyor...");
    
    // Önce IndexedDB'deki PDF'i al
    await _loadPdfFromIndexedDB();
  }

  // ==================== INDEXEDDB'DEN PDF YÜKLE ====================
  Future<void> _loadPdfFromIndexedDB() async {
    try {
      debugPrint("📂 IndexedDB'den PDF yükleniyor...");
      
      // Burada gerçek IndexedDB verisi alınacak
      // Şimdilik boş veri ile başlatıyoruz
      _currentPdfData = Uint8List(0);
      _currentPdfName = "document.pdf";
      
      debugPrint("✅ IndexedDB PDF hazırlandı");
    } catch (e) {
      debugPrint("❌ IndexedDB yükleme hatası: $e");
    }
  }

  // ==================== VIEWER TEMİZLEME ====================
  Future<void> _cleanupViewer() async {
    debugPrint("🗑️ Viewer temizleniyor...");
    
    if (webViewController != null) {
      try {
        await webViewController!.evaluateJavascript(source: """
          (async function() {
            try {
              console.log("🗑️ Viewer IndexedDB temizleniyor...");
              
              if (typeof viewerPdfManager !== 'undefined' && viewerPdfManager.cleanup) {
                await viewerPdfManager.cleanup();
                console.log("✅ Viewer IndexedDB temizlendi");
              }
              
              return true;
            } catch (e) {
              console.error("❌ Temizleme hatası:", e);
              return false;
            }
          })();
        """);
      } catch (e) {
        debugPrint("⚠️ WebView temizleme hatası: $e");
      }
    }
    
    debugPrint("✅ Viewer temizlendi");
  }

  // ==================== GERİ DÖN ====================
  Future<void> _goBack() async {
    debugPrint("⬅️ Viewer'dan çıkılıyor...");
    
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadingMessage = 'Kapatılıyor...';
      });
    }
    
    await _cleanupViewer();
    await Future.delayed(const Duration(milliseconds: 300));
    
    if (mounted) {
      Navigator.pop(context);
    }
  }

  // ==================== PDF İNDİR/KAYDET ====================
  Future<void> _downloadPdf() async {
    if (_currentPdfData == null) {
      _showSnackBar('PDF verisi bulunamadı');
      return;
    }
    
    try {
      // İzin kontrolü
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      
      if (!status.isGranted) {
        _showSnackBar('Depolama izni verilmedi');
        return;
      }
      
      // Klasör yolu
      final directory = await getApplicationDocumentsDirectory();
      final pdfFolder = Directory('${directory.path}/Download/PDF Reader');
      
      if (!await pdfFolder.exists()) {
        await pdfFolder.create(recursive: true);
        debugPrint("📁 Klasör oluşturuldu: ${pdfFolder.path}");
      }
      
      // Dosya adı
      String fileName = _currentPdfName ?? 'document_${DateTime.now().millisecondsSinceEpoch}.pdf';
      if (!fileName.toLowerCase().endsWith('.pdf')) {
        fileName = '$fileName.pdf';
      }
      
      // Dosya yolu
      final filePath = '${pdfFolder.path}/$fileName';
      final file = File(filePath);
      
      // Dosyayı kaydet
      await file.writeAsBytes(_currentPdfData!);
      
      // Dosya boyutu
      final fileSize = await file.length();
      final sizeMB = fileSize / 1024 / 1024;
      
      debugPrint("✅ PDF kaydedildi: $filePath (${sizeMB.toStringAsFixed(2)} MB)");
      
      if (mounted) {
        _showSnackBar('PDF kaydedildi: $fileName', isSuccess: true);
        
        // Bilgi göster
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('✅ PDF Kaydedildi'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dosya: $fileName'),
                const SizedBox(height: 8),
                Text('Boyut: ${sizeMB.toStringAsFixed(2)} MB'),
                const SizedBox(height: 8),
                Text('Konum: Download/PDF Reader/'),
                const SizedBox(height: 16),
                const Text(
                  'Dosyanız telefonunuzun dosya yöneticisinde "Download/PDF Reader/" klasöründe bulunabilir.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
      }
      
    } catch (e) {
      debugPrint("❌ PDF kaydetme hatası: $e");
      _showSnackBar('PDF kaydedilemedi: $e');
    }
  }

  // ==================== PDF PAYLAŞ ====================
  Future<void> _sharePdf() async {
    if (_currentPdfData == null) {
      _showSnackBar('PDF verisi bulunamadı');
      return;
    }
    
    try {
      // Geçici dosya oluştur
      final tempDir = await getTemporaryDirectory();
      String fileName = _currentPdfName ?? 'document_${DateTime.now().millisecondsSinceEpoch}.pdf';
      if (!fileName.toLowerCase().endsWith('.pdf')) {
        fileName = '$fileName.pdf';
      }
      
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(_currentPdfData!);
      
      debugPrint("📤 PDF paylaşılıyor: $fileName");
      
      // Share API ile paylaş
      await Share.shareXFiles(
        [XFile(tempFile.path, mimeType: 'application/pdf')],
        subject: fileName,
        text: 'PDF Dosyası: $fileName',
      );
      
      // Geçici dosyayı temizle
      await Future.delayed(const Duration(seconds: 2));
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      
      debugPrint("✅ PDF paylaşıldı");
      
    } catch (e) {
      debugPrint("❌ PDF paylaşma hatası: $e");
      _showSnackBar('PDF paylaşılamadı: $e');
    }
  }

  // ==================== PDF YAZDIR ====================
  Future<void> _printPdf() async {
    if (_currentPdfData == null) {
      _showSnackBar('PDF verisi bulunamadı');
      return;
    }
    
    try {
      debugPrint("🖨️ PDF yazdırılıyor...");
      
      // Yazdırma için WebView'deki PDF'i kullan
      if (webViewController != null) {
        await webViewController!.evaluateJavascript(source: """
          (function() {
            try {
              if (window.PDFViewerApplication) {
                window.PDFViewerApplication.print();
                return true;
              } else {
                return false;
              }
            } catch (e) {
              console.error("Yazdırma hatası:", e);
              return false;
            }
          })();
        """);
      } else {
        _showSnackBar('Yazdırma başlatılamadı');
      }
      
    } catch (e) {
      debugPrint("❌ PDF yazdırma hatası: $e");
      _showSnackBar('PDF yazdırılamadı: $e');
    }
  }

  // ==================== PDF VERİSİNİ AL ====================
  Future<Map<String, dynamic>?> _getPdfDataFromWebView() async {
    try {
      if (webViewController != null) {
        final result = await webViewController!.evaluateJavascript(source: """
          (async function() {
            try {
              console.log("📦 PDF verisi alınıyor...");
              
              if (typeof window.flutterCommunication !== 'undefined' && 
                  typeof window.flutterCommunication.getPdfInfo === 'function') {
                const pdfInfo = await window.flutterCommunication.getPdfInfo();
                console.log("📄 PDF bilgisi alındı:", pdfInfo);
                return pdfInfo;
              }
              
              if (typeof getUpdatedPdfData === 'function') {
                const pdfData = await getUpdatedPdfData();
                if (pdfData && pdfData.data) {
                  return {
                    name: pdfData.name || "document.pdf",
                    size: pdfData.size || 0,
                    hasData: true
                  };
                }
              }
              
              return null;
            } catch (e) {
              console.error("PDF verisi alma hatası:", e);
              return null;
            }
          })();
        """);
        
        if (result != null && result is Map) {
          return Map<String, dynamic>.from(result);
        }
      }
    } catch (e) {
      debugPrint("❌ PDF verisi alma hatası: $e");
    }
    
    return null;
  }

  // ==================== PDF ARRAYBUFFER AL ====================
  Future<Uint8List?> _getPdfArrayBufferFromWebView() async {
    try {
      if (webViewController != null) {
        debugPrint("📦 PDF ArrayBuffer alınıyor...");
        
        // JavaScript'ten ArrayBuffer al
        final result = await webViewController!.evaluateJavascript(source: """
          (async function() {
            try {
              if (typeof window.flutterCommunication !== 'undefined' && 
                  typeof window.flutterCommunication.getPdfArrayBuffer === 'function') {
                const arrayBuffer = await window.flutterCommunication.getPdfArrayBuffer();
                if (arrayBuffer) {
                  // ArrayBuffer'ı base64'e çevir
                  const uint8Array = new Uint8Array(arrayBuffer);
                  let binary = '';
                  const chunkSize = 32768;
                  
                  for (let i = 0; i < uint8Array.length; i += chunkSize) {
                    const chunk = uint8Array.subarray(i, Math.min(i + chunkSize, uint8Array.length));
                    binary += String.fromCharCode.apply(null, chunk);
                  }
                  
                  return btoa(binary);
                }
              }
              return null;
            } catch (e) {
              console.error("ArrayBuffer alma hatası:", e);
              return null;
            }
          })();
        """);
        
        if (result != null && result is String) {
          // Base64'ten Uint8List'e çevir
          final bytes = base64.decode(result);
          debugPrint("✅ PDF ArrayBuffer alındı: ${bytes.length} bytes");
          return Uint8List.fromList(bytes);
        }
      }
    } catch (e) {
      debugPrint("❌ PDF ArrayBuffer alma hatası: $e");
    }
    
    return null;
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

  // ==================== SNACKBAR ====================
  void _showSnackBar(String message, {bool isSuccess = false}) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Tamam',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
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
                key: _webViewKey,
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
                      
                      window.activeBlobUrls = window.activeBlobUrls || [];
                      
                      // Flutter iletişim için global fonksiyonlar
                      window.flutterHandlerReady = true;
                      
                      // Index'e dön fonksiyonu
                      window.goBackToIndex = function() {
                        console.log("⬅️ Viewer: Index'e dönülüyor");
                        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                          window.flutter_inappwebview.callHandler('goBackToIndex');
                        }
                      };
                      
                      console.log("✅ Viewer JavaScript hazır");
                    """,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  ),
                ]),
                onWebViewCreated: (controller) {
                  webViewController = controller;
                  debugPrint("🌐 Viewer WebView oluşturuldu");

                  // ==================== HANDLER: INDEX'E DÖN ====================
                  controller.addJavaScriptHandler(
                    handlerName: 'goBackToIndex',
                    callback: (args) async {
                      debugPrint("⬅️ Handler: goBackToIndex");
                      await _goBack();
                    },
                  );

                  // ==================== HANDLER: PDF İNDİR ====================
                  controller.addJavaScriptHandler(
                    handlerName: 'handleDownloadPdf',
                    callback: (args) async {
                      debugPrint("💾 Handler: handleDownloadPdf");
                      
                      if (mounted) {
                        setState(() {
                          _isLoading = true;
                          _loadingMessage = 'PDF alınıyor...';
                        });
                      }
                      
                      try {
                        // Önce PDF verisini al
                        final pdfData = await _getPdfArrayBufferFromWebView();
                        
                        if (pdfData != null) {
                          _currentPdfData = pdfData;
                          
                          // PDF bilgilerini al
                          final pdfInfo = await _getPdfDataFromWebView();
                          if (pdfInfo != null) {
                            _currentPdfName = pdfInfo['name']?.toString();
                            _currentPdfSize = pdfInfo['size'] != null ? int.tryParse(pdfInfo['size'].toString()) : null;
                          }
                          
                          debugPrint("📄 PDF hazır: ${_currentPdfName}, ${_currentPdfData?.length} bytes");
                          
                          // İndirme/kaydetme işlemini başlat
                          await _downloadPdf();
                        } else {
                          _showSnackBar('PDF verisi alınamadı');
                        }
                      } catch (e) {
                        debugPrint("❌ PDF indirme hatası: $e");
                        _showSnackBar('PDF indirilemedi: $e');
                      }
                      
                      if (mounted) {
                        setState(() {
                          _isLoading = false;
                        });
                      }
                    },
                  );

                  // ==================== HANDLER: PDF PAYLAŞ ====================
                  controller.addJavaScriptHandler(
                    handlerName: 'handleSharePdf',
                    callback: (args) async {
                      debugPrint("📤 Handler: handleSharePdf");
                      
                      if (mounted) {
                        setState(() {
                          _isLoading = true;
                          _loadingMessage = 'PDF alınıyor...';
                        });
                      }
                      
                      try {
                        // Önce PDF verisini al
                        final pdfData = await _getPdfArrayBufferFromWebView();
                        
                        if (pdfData != null) {
                          _currentPdfData = pdfData;
                          
                          // PDF bilgilerini al
                          final pdfInfo = await _getPdfDataFromWebView();
                          if (pdfInfo != null) {
                            _currentPdfName = pdfInfo['name']?.toString();
                          }
                          
                          debugPrint("📄 PDF hazır: ${_currentPdfName}, ${_currentPdfData?.length} bytes");
                          
                          // Paylaşma işlemini başlat
                          await _sharePdf();
                        } else {
                          _showSnackBar('PDF verisi alınamadı');
                        }
                      } catch (e) {
                        debugPrint("❌ PDF paylaşma hatası: $e");
                        _showSnackBar('PDF paylaşılamadı: $e');
                      }
                      
                      if (mounted) {
                        setState(() {
                          _isLoading = false;
                        });
                      }
                    },
                  );

                  // ==================== HANDLER: PDF YAZDIR ====================
                  controller.addJavaScriptHandler(
                    handlerName: 'handlePrintPdf',
                    callback: (args) async {
                      debugPrint("🖨️ Handler: handlePrintPdf");
                      await _printPdf();
                    },
                  );

                  debugPrint("✅ Tüm handler'lar kaydedildi");
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
                  
                  // PDF yükleme işlemi başlat
                  await controller.evaluateJavascript(source: """
                    (async function() {
                      try {
                        console.log("📦 Viewer: PDF yükleme başlatılıyor...");
                        
                        if (typeof viewerPdfManager !== 'undefined' && viewerPdfManager.init) {
                          const success = await viewerPdfManager.init();
                          console.log("📦 Viewer IndexedDB: " + (success ? "✅ Başarılı" : "❌ Başarısız"));
                          
                          if (success && typeof loadPdfIntoViewer === 'function') {
                            await loadPdfIntoViewer();
                            console.log("✅ Viewer: PDF yüklendi");
                          }
                        }
                        
                        console.log("✅ Viewer hazır");
                        return true;
                      } catch (e) {
                        console.error("❌ Viewer hazırlama hatası:", e);
                        return false;
                      }
                    })();
                  """);
                  
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                },
                onProgressChanged: (controller, progress) {
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
                  }
                  
                  debugPrint("$prefix: $message");
                },
                onLoadError: (controller, url, code, message) {
                  debugPrint("❌ Viewer: Yükleme hatası: $message");
                  
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                    
                    _showSnackBar('Yükleme hatası: $message');
                  }
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
