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

  Uint8List _decodeBase64(String base64String) {
    if (base64String.contains(',')) {
      base64String = base64String.split(',').last;
    }
    return base64Decode(base64String);
  }

  // İzin diyalog penceresi (HTML tarafı tetiklerse kullanılabilir)
  void _showPermissionDialog(String base64Data, String originalName) {
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_open_rounded, size: 48, color: Colors.redAccent),
            ),
            const SizedBox(height: 24),
            const Text(
              "Dosya Erişimi Gerekli",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 12),
            const Text(
              "Cihazınızdaki dosyaları görmek, düzenlemek ve güncellemek için lütfen gerekli izni verin.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
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
                    child: const Text("Şimdi Değil", style: TextStyle(color: Colors.grey)),
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
                      if (await Permission.manageExternalStorage.request().isPermanentlyDenied) {
                        openAppSettings();
                      }
                    },
                    child: const Text("Ayarlara Gidin"),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  // PDF'i İndirilenler klasörüne kaydetme
  Future<void> _savePdfToFile(String base64Data, String originalName) async {
    PermissionStatus status;
    if (Platform.isAndroid) {
      status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        status = await Permission.storage.status;
      }
    } else {
      status = await Permission.storage.status;
    }

    if (!status.isGranted) {
      _showPermissionDialog(base64Data, originalName);
      return;
    }

    String baseFileName;
    String extension;
    if (originalName.contains('.')) {
      int lastDot = originalName.lastIndexOf('.');
      baseFileName = "${originalName.substring(0, lastDot)}_update";
      extension = originalName.substring(lastDot);
    } else {
      baseFileName = "${originalName}_update";
      extension = ".pdf";
    }

    final directory = Directory('/storage/emulated/0/Download/PDF Reader');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    int counter = 0;
    String finalFileName = "$baseFileName$extension";
    File file = File('${directory.path}/$finalFileName');

    while (await file.exists()) {
      counter++;
      finalFileName = "$baseFileName($counter)$extension";
      file = File('${directory.path}/$finalFileName');
    }

    try {
      final bytes = _decodeBase64(base64Data);
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Kaydedildi: $finalFileName"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Kaydetme Hatası: $e");
    }
  }

  // Viewer'dan güvenli çıkış ve OPFS temizliği
  Future<bool> _goBackFromViewer() async {
    if (_isViewerOpen && webViewController != null) {
      try {
        await webViewController!.evaluateJavascript(source: """
          try {
            // Blob URL'leri temizle
            const blobUrl = sessionStorage.getItem('currentPdfBlobUrl');
            if (blobUrl) {
              URL.revokeObjectURL(blobUrl);
              sessionStorage.removeItem('currentPdfBlobUrl');
            }
            
            // PDF viewer'ı kapat
            if (window.PDFViewerApplication) {
              try {
                PDFViewerApplication.close();
              } catch (e) {
                console.log("PDF viewer kapatılamadı:", e);
              }
            }
            
            console.log("Viewer temizlendi, index.html'ye yönlendiriliyor...");
          } catch (error) {
            console.error("Viewer temizleme hatası:", error);
          }
        """);
        
        await webViewController!.loadUrl(
          urlRequest: URLRequest(
            url: WebUri("file:///android_asset/flutter_assets/assets/web/index.html"),
          ),
        );
        
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
        if (await _goBackFromViewer()) {
          return false;
        }
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
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;

              // --- UserScript Hatası Giderildi: userScript parametresi eklendi ---
              controller.addUserScript(userScript: UserScript(
                  source: """
                    window.Android = {
                      openSettings: function() {
                        window.flutter_inappwebview.callHandler('openSettings');
                      },
                      checkPermission: function() {
                        return false; 
                      },
                      listPDFs: function() { return ""; }
                    };
                  """,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: true
              ));

              // --- İzin Ayarlarına Git ---
              controller.addJavaScriptHandler(
                handlerName: 'openSettings',
                callback: (args) async {
                  var status = await Permission.manageExternalStorage.request();
                  if (status.isGranted) {
                    controller.evaluateJavascript(source: "if(typeof scanDeviceForPDFs === 'function') scanDeviceForPDFs();");
                  } else {
                    if (!await Permission.manageExternalStorage.isGranted) {
                       await openAppSettings();
                    }
                  }
                },
              );

              // --- İzin Kontrolü ---
              controller.addJavaScriptHandler(
                handlerName: 'checkDevicePermission',
                callback: (args) async {
                  PermissionStatus status = await Permission.manageExternalStorage.status;
                  if (!status.isGranted) {
                     status = await Permission.storage.status;
                  }
                  final bool isGranted = status.isGranted;

                  if (isGranted) {
                    await controller.evaluateJavascript(source: """
                      if(document.getElementById('permissionContainer')) {
                        document.getElementById('permissionContainer').style.display='none';
                        document.getElementById('deviceList').style.display='grid';
                      }
                    """);
                  } else {
                    await controller.evaluateJavascript(source: """
                      if(document.getElementById('permissionContainer')) {
                        document.getElementById('permissionContainer').style.display='block';
                        document.getElementById('deviceList').style.display='none';
                      }
                    """);
                  }
                  return isGranted;
                },
              );

              // --- PDF Görüntüleyici Açma (OPFS Uyumlu) ---
              controller.addJavaScriptHandler(
                handlerName: 'openPdfViewer',
                callback: (args) {
                  final String base64Data = args[0];
                  final String pdfName = args[1];
                  
                  setState(() {
                    _isViewerOpen = true;
                    _currentViewerPdfName = pdfName;
                  });
                  
                  // Base64 verisini OPFS'ye yazan ve viewer.html'i açan JS kodu
                  controller.evaluateJavascript(source: """
                    const usingOPFS = navigator.storage && navigator.storage.getDirectory;
                    if (usingOPFS) {
                      sessionStorage.setItem('usingOPFS', 'true');
                      (async function() {
                        try {
                          const root = await navigator.storage.getDirectory();
                          const pdfDir = await root.getDirectoryHandle('pdfs', { create: true });
                          
                          // Varsa eski dosyayı temizle
                          try { await pdfDir.removeEntry('current.pdf'); } catch (e) {}
                          
                          // Base64'ü Binary'e çevir
                          var b64 = '$base64Data';
                          if (b64.includes(',')) b64 = b64.split(',')[1];
                          
                          const binaryString = atob(b64);
                          const bytes = new Uint8Array(binaryString.length);
                          for (let i = 0; i < binaryString.length; i++) {
                            bytes[i] = binaryString.charCodeAt(i);
                          }
                          
                          // Dosyayı kendi adıyla kaydet
                          const fileHandle = await pdfDir.getFileHandle('$pdfName', { create: true });
                          const writable = await fileHandle.createWritable();
                          await writable.write(bytes);
                          await writable.close();
                          
                          // Dosyayı current.pdf olarak kaydet (viewer için)
                          const currentHandle = await pdfDir.getFileHandle('current.pdf', { create: true });
                          const currentWritable = await currentHandle.createWritable();
                          await currentWritable.write(bytes);
                          await currentWritable.close();
                          
                          console.log('PDF OPFS sistemine kaydedildi: $pdfName');
                        } catch (error) {
                          console.error('OPFS yazma hatası, sessionStorage kullanılıyor:', error);
                          sessionStorage.setItem('currentPdfData', '$base64Data');
                          sessionStorage.setItem('usingOPFS', 'false');
                        }
                        
                        sessionStorage.setItem('currentPdfName', '$pdfName');
                        window.location.href = 'viewer.html';
                      })();
                    } else {
                      // OPFS yoksa klasik yöntem
                      sessionStorage.setItem('currentPdfData', '$base64Data');
                      sessionStorage.setItem('currentPdfName', '$pdfName');
                      sessionStorage.setItem('usingOPFS', 'false');
                      window.location.href = 'viewer.html';
                    }
                  """);
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'sharePdf',
                callback: (args) async {
                  try {
                    final String base64Data = args[0];
                    final String fileName = args[1];
                    final bytes = _decodeBase64(base64Data);
                    final tempDir = await getTemporaryDirectory();
                    final file = File('${tempDir.path}/$fileName');
                    await file.writeAsBytes(bytes);
                    await Share.shareXFiles([XFile(file.path)], text: fileName);
                  } catch (e) {
                    debugPrint("Paylaşma Hatası: $e");
                  }
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'printPdf',
                callback: (args) async {
                  try {
                    final String base64Data = args[0];
                    final String fileName = args[1];
                    final bytes = _decodeBase64(base64Data);
                    await Printing.layoutPdf(onLayout: (format) async => bytes, name: fileName);
                  } catch (e) {
                    debugPrint("Yazdırma Hatası: $e");
                  }
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'downloadPdf',
                callback: (args) async {
                  final String base64Data = args[0];
                  final String originalName = args[1];
                  _savePdfToFile(base64Data, originalName);
                },
              );

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
                // Anasayfaya dönüldüğünde izin durumunu kontrol et
                controller.evaluateJavascript(source: """
                  if (document.querySelector('.tab.active') && document.querySelector('.tab.active').dataset.tab === 'device') {
                     if (window.flutter_inappwebview.callHandler) {
                        window.flutter_inappwebview.callHandler('checkDevicePermission');
                     }
                  }
                """);
              }
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
