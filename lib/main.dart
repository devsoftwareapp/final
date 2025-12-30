import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isAndroid) {
    InAppWebViewController.setWebContentsDebuggingEnabled(true);
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
        primarySwatch: Colors.blue,
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

class _WebViewPageState extends State<WebViewPage> {
  InAppWebViewController? webViewController;
  DateTime? _lastBackPressTime;
  bool _isViewerOpen = false;
  String? _currentViewerPdfName;
  bool _isCheckingPermission = false;

  Uint8List _decodeBase64(String base64String) {
    if (base64String.contains(',')) {
      base64String = base64String.split(',').last;
    }
    return base64Decode(base64String);
  }

  // MERKEZİ İZİN KONTROL FONKSİYONU (HATASIZ)
  Future<bool> _checkAndRequestPermission(String context) async {
    debugPrint("İzin kontrolü başlatılıyor: $context");
    
    if (_isCheckingPermission) return false;
    _isCheckingPermission = true;

    try {
      // Android 11+ için manageExternalStorage, diğerleri için storage
      Permission permission;
      if (Platform.isAndroid) {
        // Önce manageExternalStorage kontrol et
        final manageStatus = await Permission.manageExternalStorage.status;
        if (manageStatus.isPermanentlyDenied) {
          permission = Permission.manageExternalStorage;
        } else {
          permission = Permission.storage;
        }
      } else {
        permission = Permission.storage;
      }

      // İzin durumunu kontrol et
      PermissionStatus status = await permission.status;
      
      debugPrint("İzin durumu: ${status.toString()}");

      if (status.isGranted) {
        debugPrint("İzin ZATEN VERİLMİŞ");
        _isCheckingPermission = false;
        return true;
      }

      if (status.isPermanentlyDenied) {
        debugPrint("İzin KALICI REDDEDİLMİŞ");
        _isCheckingPermission = false;
        return false;
      }

      // İzin iste
      debugPrint("İzin isteniyor...");
      PermissionStatus result = await permission.request();
      
      debugPrint("İzin sonucu: ${result.toString()}");
      
      _isCheckingPermission = false;
      
      if (result.isGranted) {
        debugPrint("İzin VERİLDİ");
        return true;
      } else {
        debugPrint("İzin REDDEDİLDİ");
        return false;
      }
    } catch (e) {
      debugPrint("İzin hatası: $e");
      _isCheckingPermission = false;
      return false;
    }
  }

  // İZİN DİYALOĞU (GÖRSELDEKİ GİBİ)
  void _showPermissionDialog({
    required String title,
    required String message,
    required String cancelText,
    required String confirmText,
    required Function onConfirm,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Kırmızı ikon alanı
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_open_rounded, size: 48, color: Colors.redAccent),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(cancelText, style: const TextStyle(color: Colors.grey)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      Navigator.pop(context);
                      onConfirm();
                    },
                    child: Text(confirmText),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  // 1. VIEWER'DAKİ İNDİR/KAYDET İKONU İÇİN
  Future<void> _handleViewerDownload(String base64Data, String originalName) async {
    bool hasPermission = await _checkAndRequestPermission("viewer_download");
    
    if (!hasPermission) {
      _showPermissionDialog(
        title: "Dosya Erişimi Gerekli",
        message: "PDF dosyasını kaydetmek için dosya erişim izni gerekli.",
        cancelText: "Şimdi Değil",
        confirmText: "Ayarlara Gidin",
        onConfirm: () => openAppSettings(),
      );
      return;
    }

    // İzin varsa kaydet
    await _savePdfToFile(base64Data, originalName);
  }

  // 2. FAB - PDF AÇ İÇİN
  Future<void> _handleFabOpenPdf() async {
    bool hasPermission = await _checkAndRequestPermission("fab_open_pdf");
    
    if (!hasPermission) {
      _showPermissionDialog(
        title: "Dosya Seçimi Gerekli",
        message: "Cihazınızdan PDF seçebilmemiz için dosya erişim izni gerekli.",
        cancelText: "Vazgeç",
        confirmText: "Ayarlara Gidin",
        onConfirm: () => openAppSettings(),
      );
      return;
    }

    // İzin varsa JavaScript'i çalıştır (HTML'deki file input'u tetikle)
    if (webViewController != null) {
      await webViewController!.evaluateJavascript(source: """
        // HTML'deki file input'u tetikle
        document.getElementById('pdfFileInput').click();
      """);
    }
  }

  // 3. CİHAZDA SEKME İÇİN İZİN KONTROLÜ
  Future<void> _handleDeviceTabPermission() async {
    bool hasPermission = await _checkAndRequestPermission("device_tab");
    
    if (webViewController != null) {
      // JavaScript'e izin durumunu bildir
      await webViewController!.evaluateJavascript(source: """
        // Android objesine izin durumunu set et
        if (typeof window.flutterSetPermissionStatus === 'function') {
          window.flutterSetPermissionStatus(${hasPermission ? 'true' : 'false'});
        }
        
        // Eğer izin yoksa permission modal'ı göster
        if (!${hasPermission}) {
          if (typeof showPermissionModal === 'function') {
            showPermissionModal();
          }
        } else {
          // İzin varsa cihaz PDF'lerini tara
          if (typeof scanDeviceForPDFs === 'function') {
            scanDeviceForPDFs();
          }
        }
      """);
    }
    
    if (!hasPermission) {
      _showPermissionDialog(
        title: "Cihaz Dosyalarına Erişim",
        message: "Cihazınızdaki PDF dosyalarını görmek için dosya erişim izni gerekli.",
        cancelText: "Vazgeç",
        confirmText: "Ayarlara Gidin",
        onConfirm: () => openAppSettings(),
      );
    }
  }

  // PDF KAYDETME FONKSİYONU (OPFS UYUMLU)
  Future<void> _savePdfToFile(String base64Data, String originalName) async {
    try {
      // İsimlendirme mantığı
      String baseFileName;
      String extension;
      
      if (originalName.contains('.')) {
        int lastDot = originalName.lastIndexOf('.');
        baseFileName = originalName.substring(0, lastDot);
        extension = originalName.substring(lastDot);
      } else {
        baseFileName = originalName;
        extension = ".pdf";
      }

      // Klasör hazırlığı
      final directory = Directory('/storage/emulated/0/Download/PDF Reader');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // Dosya çakışma kontrolü
      int counter = 0;
      String finalFileName = "$baseFileName$extension";
      File file = File('${directory.path}/$finalFileName');

      while (await file.exists()) {
        counter++;
        finalFileName = "$baseFileName($counter)$extension";
        file = File('${directory.path}/$finalFileName');
      }

      // Yazma işlemi
      final bytes = _decodeBase64(base64Data);
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Kaydedildi: $finalFileName"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: "AÇ",
              textColor: Colors.white,
              onPressed: () {
                // Kaydedilen dosyayı OPFS ile viewer'da aç
                if (webViewController != null) {
                  webViewController!.evaluateJavascript(source: """
                    // Base64 verisini OPFS'ye kaydet
                    const base64Data = '$base64Data';
                    const pdfName = '$finalFileName';
                    
                    // OPFS fonksiyonunu çağır
                    if (typeof window.saveToOPFSAndOpen === 'function') {
                      window.saveToOPFSAndOpen(base64Data, pdfName);
                    } else {
                      // Fallback: normal açma
                      sessionStorage.setItem('currentPdfData', base64Data);
                      sessionStorage.setItem('currentPdfName', pdfName);
                      sessionStorage.setItem('usingOPFS', 'false');
                      window.location.href = 'viewer.html';
                    }
                  """);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Kaydetme hatası: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Kaydetme başarısız oldu"),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // OPFS İLE PDF KAYDETME FONKSİYONU
  Future<void> _saveToOPFSAndOpen(String base64Data, String pdfName) async {
    if (webViewController != null) {
      await webViewController!.evaluateJavascript(source: """
        // OPFS'ye kaydet ve aç
        (async function() {
          const base64Data = '$base64Data';
          const pdfName = '$pdfName';
          
          try {
            // OPFS desteği kontrol et
            if (navigator.storage && navigator.storage.getDirectory) {
              const root = await navigator.storage.getDirectory();
              const pdfDir = await root.getDirectoryHandle('pdfs', { create: true });
              
              // Base64'ten ArrayBuffer'a çevir
              const base64 = base64Data.split(',')[1];
              const binaryString = atob(base64);
              const bytes = new Uint8Array(binaryString.length);
              for (let i = 0; i < binaryString.length; i++) {
                bytes[i] = binaryString.charCodeAt(i);
              }
              
              // OPFS'ye kaydet
              const fileHandle = await pdfDir.getFileHandle(pdfName, { create: true });
              const writable = await fileHandle.createWritable();
              await writable.write(bytes);
              await writable.close();
              
              // current.pdf olarak da kaydet
              const currentHandle = await pdfDir.getFileHandle('current.pdf', { create: true });
              const currentWritable = await currentHandle.createWritable();
              await currentWritable.write(bytes);
              await currentWritable.close();
              
              console.log('PDF OPFS\'ye kaydedildi: ' + pdfName);
              
              // Session storage'a kaydet
              sessionStorage.setItem('currentPdfName', pdfName);
              sessionStorage.setItem('usingOPFS', 'true');
            } else {
              // OPFS desteklenmiyorsa sessionStorage
              sessionStorage.setItem('currentPdfData', base64Data);
              sessionStorage.setItem('currentPdfName', pdfName);
              sessionStorage.setItem('usingOPFS', 'false');
            }
            
            // Viewer'a yönlendir
            window.location.href = 'viewer.html';
            
          } catch (error) {
            console.error('OPFS kaydetme hatası:', error);
            // Fallback: normal session storage
            sessionStorage.setItem('currentPdfData', base64Data);
            sessionStorage.setItem('currentPdfName', pdfName);
            sessionStorage.setItem('usingOPFS', 'false');
            window.location.href = 'viewer.html';
          }
        })();
      """);
    }
  }

  // Viewer'dan index'e geri dönme
  Future<bool> _goBackFromViewer() async {
    if (_isViewerOpen && webViewController != null) {
      try {
        await webViewController!.evaluateJavascript(source: """
          try {
            if (typeof goBackToIndex === 'function') {
              goBackToIndex();
            } else {
              window.location.href = 'index.html';
            }
          } catch (error) {
            console.error("Geri dönme hatası:", error);
            window.location.href = 'index.html';
          }
        """);
        
        setState(() {
          _isViewerOpen = false;
          _currentViewerPdfName = null;
        });
        
        return true;
      } catch (e) {
        debugPrint("Viewer'dan çıkış hatası: $e");
      }
    }
    return false;
  }

  // Çift tıklama ile uygulamadan çıkma
  Future<bool> _exitApp() async {
    final now = DateTime.now();
    final isDoubleTap = _lastBackPressTime != null && 
        now.difference(_lastBackPressTime!) < const Duration(seconds: 2);
    
    if (isDoubleTap) {
      return true;
    } else {
      _lastBackPressTime = now;
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Çıkmak için tekrar basın"),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Önce viewer'dan çıkmayı dene
        if (await _goBackFromViewer()) {
          return false;
        }
        
        // Uygulamadan çıkma kontrolü
        return await _exitApp();
      },
      child: Scaffold(
        body: SafeArea(
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
              cacheEnabled: true,
              transparentBackground: true,
              javaScriptCanOpenWindowsAutomatically: true,
              verticalScrollBarEnabled: true,
              horizontalScrollBarEnabled: true,
              supportZoom: false,
              mediaPlaybackRequiresUserGesture: false,
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;

              // Android objesini ve OPFS fonksiyonlarını oluştur
              controller.evaluateJavascript(source: """
                // Flutter permission fonksiyonu
                window.flutterSetPermissionStatus = function(status) {
                  window._hasPermission = status;
                };
                
                // OPFS'ye kaydet ve aç fonksiyonu
                window.saveToOPFSAndOpen = function(base64Data, pdfName) {
                  return new Promise(async (resolve, reject) => {
                    try {
                      // OPFS desteği kontrol et
                      if (navigator.storage && navigator.storage.getDirectory) {
                        const root = await navigator.storage.getDirectory();
                        const pdfDir = await root.getDirectoryHandle('pdfs', { create: true });
                        
                        // Base64'ten ArrayBuffer'a çevir
                        const base64 = base64Data.split(',')[1];
                        const binaryString = atob(base64);
                        const bytes = new Uint8Array(binaryString.length);
                        for (let i = 0; i < binaryString.length; i++) {
                          bytes[i] = binaryString.charCodeAt(i);
                        }
                        
                        // OPFS'ye kaydet
                        const fileHandle = await pdfDir.getFileHandle(pdfName, { create: true });
                        const writable = await fileHandle.createWritable();
                        await writable.write(bytes);
                        await writable.close();
                        
                        // current.pdf olarak da kaydet
                        const currentHandle = await pdfDir.getFileHandle('current.pdf', { create: true });
                        const currentWritable = await currentHandle.createWritable();
                        await currentWritable.write(bytes);
                        await currentWritable.close();
                        
                        console.log('PDF OPFS\'ye kaydedildi: ' + pdfName);
                        
                        // Session storage'a kaydet
                        sessionStorage.setItem('currentPdfName', pdfName);
                        sessionStorage.setItem('usingOPFS', 'true');
                      } else {
                        // OPFS desteklenmiyorsa sessionStorage
                        sessionStorage.setItem('currentPdfData', base64Data);
                        sessionStorage.setItem('currentPdfName', pdfName);
                        sessionStorage.setItem('usingOPFS', 'false');
                      }
                      
                      // Viewer'a yönlendir
                      window.location.href = 'viewer.html';
                      resolve(true);
                      
                    } catch (error) {
                      console.error('OPFS kaydetme hatası:', error);
                      // Fallback: normal session storage
                      sessionStorage.setItem('currentPdfData', base64Data);
                      sessionStorage.setItem('currentPdfName', pdfName);
                      sessionStorage.setItem('usingOPFS', 'false');
                      window.location.href = 'viewer.html';
                      resolve(true);
                    }
                  });
                };
                
                // Flutter'dan mesaj alma
                window.addEventListener('flutterInAppWebViewPlatformReady', function() {
                  console.log('Flutter WebView hazır');
                });
              """);

              // 1. PDF Viewer açma handler'ı (OPFS UYUMLU)
              controller.addJavaScriptHandler(
                handlerName: 'openPdfViewer',
                callback: (args) {
                  if (args.length >= 2) {
                    final String base64Data = args[0];
                    final String pdfName = args[1];
                    
                    setState(() {
                      _isViewerOpen = true;
                      _currentViewerPdfName = pdfName;
                    });
                    
                    // OPFS'ye kaydet ve aç
                    _saveToOPFSAndOpen(base64Data, pdfName);
                  }
                },
              );

              // 2. PDF Paylaşma handler'ı
              controller.addJavaScriptHandler(
                handlerName: 'sharePdf',
                callback: (args) async {
                  if (args.length >= 2) {
                    try {
                      final String base64Data = args[0];
                      final String fileName = args[1];
                      final bytes = _decodeBase64(base64Data);
                      final tempDir = await getTemporaryDirectory();
                      final file = File('${tempDir.path}/$fileName');
                      await file.writeAsBytes(bytes);
                      await Share.shareXFiles([XFile(file.path)], text: fileName);
                    } catch (e) {
                      debugPrint("Paylaşma hatası: $e");
                    }
                  }
                },
              );

              // 3. PDF Yazdırma handler'ı
              controller.addJavaScriptHandler(
                handlerName: 'printPdf',
                callback: (args) async {
                  if (args.length >= 2) {
                    try {
                      final String base64Data = args[0];
                      final String fileName = args[1];
                      final bytes = _decodeBase64(base64Data);
                      await Printing.layoutPdf(onLayout: (format) async => bytes, name: fileName);
                    } catch (e) {
                      debugPrint("Yazdırma hatası: $e");
                    }
                  }
                },
              );

              // 4. PDF İndirme handler'ı (VIEWER'DAKİ İKON)
              controller.addJavaScriptHandler(
                handlerName: 'downloadPdf',
                callback: (args) async {
                  if (args.length >= 2) {
                    final String base64Data = args[0];
                    final String originalName = args[1];
                    await _handleViewerDownload(base64Data, originalName);
                  }
                },
              );

              // 5. FAB - PDF AÇ handler'ı
              controller.addJavaScriptHandler(
                handlerName: 'openFabPdf',
                callback: (args) async {
                  await _handleFabOpenPdf();
                },
              );

              // 6. CİHAZDA SEKME İZİN KONTROLÜ
              controller.addJavaScriptHandler(
                handlerName: 'checkDevicePermission',
                callback: (args) async {
                  await _handleDeviceTabPermission();
                },
              );

              // 7. Ayarları açma
              controller.addJavaScriptHandler(
                handlerName: 'openSettings',
                callback: (args) async {
                  await openAppSettings();
                },
              );

              // 8. Android back button handler
              controller.addJavaScriptHandler(
                handlerName: 'androidBackPressed',
                callback: (args) async {
                  try {
                    final currentUrl = await controller.getUrl();
                    final isViewerPage = currentUrl?.toString().contains('viewer.html') == true;
                    
                    if (isViewerPage) {
                      await _goBackFromViewer();
                      return true;
                    }
                    
                    return false;
                  } catch (e) {
                    debugPrint("Back button error: $e");
                    return false;
                  }
                },
              );
            },
            onLoadStart: (controller, url) async {
              final urlString = url?.toString() ?? '';
              
              setState(() {
                _isViewerOpen = urlString.contains('viewer.html');
                
                if (!_isViewerOpen) {
                  _currentViewerPdfName = null;
                }
              });
              
              // Eğer index.html'ye döndüysek, izin durumunu kontrol et
              if (urlString.contains('index.html')) {
                await Future.delayed(const Duration(milliseconds: 500));
                // Cihaz sekmesi aktifse izin kontrolü yap
                controller.evaluateJavascript(source: """
                  setTimeout(function() {
                    const activeTab = document.querySelector('.tab.active');
                    if (activeTab && activeTab.dataset.tab === 'device') {
                      if (typeof flutter_inappwebview !== 'undefined' && flutter_inappwebview.callHandler) {
                        flutter_inappwebview.callHandler('checkDevicePermission');
                      }
                    }
                  }, 1000);
                """);
              }
            },
            onLoadStop: (controller, url) async {
              final urlString = url?.toString() ?? '';
              
              setState(() {
                _isViewerOpen = urlString.contains('viewer.html');
              });
              
              if (urlString.contains('index.html')) {
                setState(() {
                  _isViewerOpen = false;
                  _currentViewerPdfName = null;
                });
              }
            },
            onConsoleMessage: (controller, consoleMessage) {
              debugPrint("WebView Console [${consoleMessage.messageLevel}]: ${consoleMessage.message}");
            },
            onReceivedError: (controller, request, error) {
              debugPrint("WebView Error: $error");
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    webViewController?.dispose();
    super.dispose();
  }
}
