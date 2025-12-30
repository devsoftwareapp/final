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

  // PDF İndirme işlemi için izin ve kayıt fonksiyonu
  Future<void> _savePdfToFile(String base64Data, String originalName) async {
    // Android 11+ için Manage External Storage, altı için Storage izni kontrolü
    PermissionStatus status;
    if (Platform.isAndroid) {
      // Önce Tüm Dosya Erişimini kontrol et
      if (await Permission.manageExternalStorage.status.isGranted) {
        status = PermissionStatus.granted;
      } else {
        // İzin yoksa iste
        status = await Permission.manageExternalStorage.request();
      }
      
      // Eğer Manage External Storage desteklenmiyorsa veya reddedildiyse eski storage iznine bak
      if (!status.isGranted) {
         status = await Permission.storage.request();
      }
    } else {
      status = await Permission.storage.request();
    }

    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Dosya kaydetmek için izin gerekli.")),
        );
        // İzin verilmediyse ayarlara yönlendir
        openAppSettings();
      }
      return;
    }

    // Dosya yolu ve isim çakışma kontrolü
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

    // İndirilenler klasörüne kaydet
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

  // Viewer'dan index'e güvenli dönüş
  Future<bool> _goBackFromViewer() async {
    if (_isViewerOpen && webViewController != null) {
      try {
        await webViewController!.evaluateJavascript(source: """
          try {
            if (window.PDFViewerApplication) {
              PDFViewerApplication.close();
            }
          } catch (error) {}
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
        debugPrint("Viewer çıkış hatası: $e");
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
              supportZoom: false,
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;

              // --- JS ENJEKSİYONU: HTML içindeki Android.openSettings çağrılarını yakalar ---
              controller.addUserScript(UserScript(
                  source: """
                    window.Android = {
                      openSettings: function() {
                        // HTML'deki Android.openSettings() çağrısını Flutter handler'a yönlendir
                        window.flutter_inappwebview.callHandler('openSettings');
                      },
                      checkPermission: function() {
                        // HTML senkron cevap bekliyor ama Flutter asenkron. 
                        // False dönüp, asenkron handler'ın UI'ı güncellemesini bekliyoruz.
                        return false; 
                      },
                      listPDFs: function() { return ""; } // Placeholder
                    };
                  """,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: true
              ));

              // --- 1. AYARLARA GİT HANDLER (TÜM DOSYA ERİŞİMİ İÇİN) ---
              controller.addJavaScriptHandler(
                handlerName: 'openSettings',
                callback: (args) async {
                  // Doğrudan "Tüm Dosyalara Erişim" ekranını açar (Android 11+)
                  var status = await Permission.manageExternalStorage.request();
                  
                  // Eğer kullanıcı izni verip geri dönerse, UI'ı güncellemek için sayfayı uyarabiliriz
                  if (status.isGranted) {
                    controller.evaluateJavascript(source: "if(typeof scanDeviceForPDFs === 'function') scanDeviceForPDFs();");
                  } else {
                    // Eğer manageExternalStorage çalışmazsa veya eski cihazsa genel ayarları aç
                    if (!await Permission.manageExternalStorage.isGranted) {
                       await openAppSettings();
                    }
                  }
                },
              );

              // --- 2. İZİN KONTROL HANDLER (SEKME GEÇİŞLERİ İÇİN) ---
              controller.addJavaScriptHandler(
                handlerName: 'checkDevicePermission',
                callback: (args) async {
                  PermissionStatus status = await Permission.manageExternalStorage.status;
                  
                  if (!status.isGranted) {
                     status = await Permission.storage.status;
                  }

                  final bool isGranted = status.isGranted;

                  // HTML arayüzünü güncelle (Banner'ı gizle/göster)
                  if (isGranted) {
                    await controller.evaluateJavascript(source: """
                      if(document.getElementById('permissionContainer')) {
                        document.getElementById('permissionContainer').style.display='none';
                        document.getElementById('deviceList').style.display='grid';
                      }
                    """);
                    // İzin varsa, dosya listeleme işlemi burada tetiklenebilir
                    // (Native dosya listeleme kodu eklenmelidir)
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

              // --- PDF GÖRÜNTÜLEYİCİ AÇMA ---
              controller.addJavaScriptHandler(
                handlerName: 'openPdfViewer',
                callback: (args) {
                  final String base64Data = args[0];
                  final String pdfName = args[1];
                  
                  setState(() {
                    _isViewerOpen = true;
                    _currentViewerPdfName = pdfName;
                  });
                  
                  controller.evaluateJavascript(source: """
                    sessionStorage.setItem('currentPdfData', '$base64Data');
                    sessionStorage.setItem('currentPdfName', '$pdfName');
                    sessionStorage.setItem('usingOPFS', 'false');
                    window.location.href = 'viewer.html';
                  """);
                },
              );

              // --- PAYLAŞMA ---
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

              // --- YAZDIRMA ---
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

              // --- İNDİRME ---
              controller.addJavaScriptHandler(
                handlerName: 'downloadPdf',
                callback: (args) async {
                  final String base64Data = args[0];
                  final String originalName = args[1];
                  _savePdfToFile(base64Data, originalName);
                },
              );

              // --- GERİ TUŞU YÖNETİMİ ---
              controller.addJavaScriptHandler(
                handlerName: 'androidBackPressed',
                callback: (args) async {
                  try {
                    final currentUrl = await controller.getUrl();
                    if (currentUrl?.toString().contains('viewer.html') == true) {
                      await _goBackFromViewer();
                      return true; 
                    }
                    return false;
                  } catch (e) {
                    return false;
                  }
                },
              );
            },
            onLoadStop: (controller, url) async {
              final urlString = url?.toString() ?? '';
              setState(() {
                _isViewerOpen = urlString.contains('viewer.html');
              });
              
              // Sayfa yüklendiğinde, eğer ana sayfadaysak ve cihaz sekmesi açıksa izin kontrolü yap
              if (urlString.contains('index.html')) {
                controller.evaluateJavascript(source: """
                  // Eğer aktif tab 'device' ise izin kontrolü tetikle
                  if (document.querySelector('.tab.active') && document.querySelector('.tab.active').dataset.tab === 'device') {
                     if (window.flutter_inappwebview.callHandler) {
                        window.flutter_inappwebview.callHandler('checkDevicePermission');
                     }
                  }
                """);
              }
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
