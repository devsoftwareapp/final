import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

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

  // "Tüm dosyalara erişim" ayarına yönlendirme
  Future<void> _openAllFilesAccessPermission() async {
    try {
      if (Platform.isAndroid) {
        // Android 11+ için MANAGE_EXTERNAL_STORAGE izin sayfasını aç
        final intent = AndroidIntent(
          action: 'android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION',
          data: 'package:${await getPackageName()}',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await intent.launch();
      } else {
        // iOS veya diğer platformlar için genel ayarlar
        await openAppSettings();
      }
    } catch (e) {
      debugPrint("All files access permission açma hatası: $e");
      // Fallback olarak genel ayarları aç
      await openAppSettings();
    }
  }

  // Cihazdaki PDF dosyalarını tara
  Future<String> _scanDeviceForPDFs() async {
    try {
      debugPrint("PDF tarama başlatılıyor...");
      
      // İzin kontrolü - Android 11+ için MANAGE_EXTERNAL_STORAGE gerekli
      PermissionStatus status;
      if (Platform.isAndroid) {
        // Önce MANAGE_EXTERNAL_STORAGE iznini kontrol et
        status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          debugPrint("MANAGE_EXTERNAL_STORAGE izni yok");
          return "PERMISSION_DENIED";
        }
      } else {
        status = await Permission.storage.status;
        if (!status.isGranted) {
          return "PERMISSION_DENIED";
        }
      }

      final List<String> pdfPaths = [];

      // Sık kullanılan dizinleri tara
      final List<String> commonPaths = [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Documents',
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Pictures',
      ];

      for (final scanPath in commonPaths) {
        try {
          final directory = Directory(scanPath);
          if (await directory.exists()) {
            final files = await _findPdfFilesInDirectory(directory);
            pdfPaths.addAll(files);
          }
        } catch (e) {
          debugPrint("Dizin tarama hatası ($scanPath): $e");
        }
      }

      // Listeyi string olarak döndür (|| ile ayrılmış)
      return pdfPaths.join('||');
    } catch (e) {
      debugPrint("PDF tarama hatası: $e");
      return "ERROR";
    }
  }

  // Dizindeki PDF dosyalarını bul
  Future<List<String>> _findPdfFilesInDirectory(Directory dir, {int maxDepth = 2, int currentDepth = 0}) async {
    final List<String> pdfPaths = [];
    
    try {
      if (currentDepth >= maxDepth) {
        return pdfPaths;
      }

      final List<FileSystemEntity> entities;
      try {
        entities = await dir.list().toList();
      } catch (e) {
        return pdfPaths;
      }

      for (final entity in entities) {
        try {
          if (entity is File) {
            // Sadece PDF dosyalarını ekle
            if (entity.path.toLowerCase().endsWith('.pdf')) {
              pdfPaths.add(entity.path);
            }
          } else if (entity is Directory) {
            // Sistem dizinlerini atla
            final dirName = entity.path.split('/').last.toLowerCase();
            if (!dirName.startsWith('.') && 
                !['android', 'sys', 'proc', 'dev'].contains(dirName)) {
              final subPdfs = await _findPdfFilesInDirectory(
                entity,
                maxDepth: maxDepth,
                currentDepth: currentDepth + 1
              );
              pdfPaths.addAll(subPdfs);
            }
          }
        } catch (e) {
          // Entity işleme hatası
        }
      }
    } catch (e) {
      debugPrint("Dizin tarama hatası (${dir.path}): $e");
    }
    
    return pdfPaths;
  }

  // Flutter uygulama paket adını al
  Future<String> getPackageName() async {
    if (Platform.isAndroid) {
      final String? packageName = await getApplicationPackageName();
      return packageName ?? 'com.example.pdfreader';
    }
    return 'com.example.pdfreader';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Viewer'dan çıkma kontrolü
        if (_isViewerOpen && webViewController != null) {
          await webViewController!.evaluateJavascript(source: """
            try {
              window.location.href = 'index.html';
            } catch (e) {
              console.log('Back navigation error:', e);
            }
          """);
          setState(() {
            _isViewerOpen = false;
            _currentViewerPdfName = null;
          });
          return false;
        }

        // Çift tıklama ile çıkış
        final now = DateTime.now();
        if (_lastBackPressTime == null || 
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Çıkmak için tekrar basın'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return false;
        }
        return true;
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
            onWebViewCreated: (controller) async {
              webViewController = controller;

              // İzin kontrol handler
              controller.addJavaScriptHandler(
                handlerName: 'checkPermission',
                callback: (args) async {
                  try {
                    PermissionStatus status;
                    if (Platform.isAndroid) {
                      // Android için MANAGE_EXTERNAL_STORAGE iznini kontrol et
                      status = await Permission.manageExternalStorage.status;
                      debugPrint("MANAGE_EXTERNAL_STORAGE izni durumu: ${status.isGranted}");
                    } else {
                      status = await Permission.storage.status;
                    }
                    return status.isGranted ? "true" : "false";
                  } catch (e) {
                    debugPrint("checkPermission error: $e");
                    return "false";
                  }
                },
              );

              // Ayarları açma handler - "Tüm dosyalara erişim" sayfasına yönlendir
              controller.addJavaScriptHandler(
                handlerName: 'openSettings',
                callback: (args) async {
                  try {
                    debugPrint("Tüm dosyalara erişim sayfası açılıyor...");
                    await _openAllFilesAccessPermission();
                    return true;
                  } catch (e) {
                    debugPrint("openSettings error: $e");
                    return false;
                  }
                },
              );

              // PDF listeleme handler
              controller.addJavaScriptHandler(
                handlerName: 'listPDFs',
                callback: (args) async {
                  try {
                    debugPrint("listPDFs handler çağrıldı");
                    final result = await _scanDeviceForPDFs();
                    debugPrint("listPDFs sonucu: ${result.length} karakter");
                    return result;
                  } catch (e) {
                    debugPrint("listPDFs error: $e");
                    return "ERROR";
                  }
                },
              );

              // Dosyayı base64 olarak okuma handler
              controller.addJavaScriptHandler(
                handlerName: 'getFileAsBase64',
                callback: (args) async {
                  try {
                    final filePath = args[0] as String;
                    debugPrint("Base64 için dosya okunuyor: $filePath");
                    
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      final bytes = await file.readAsBytes();
                      final base64 = base64Encode(bytes);
                      final result = "data:application/pdf;base64,$base64";
                      return result;
                    } else {
                      debugPrint("Dosya bulunamadı: $filePath");
                      return null;
                    }
                  } catch (e) {
                    debugPrint("getFileAsBase64 error: $e");
                    return null;
                  }
                },
              );

              // Mevcut handler'ları koru
              controller.addJavaScriptHandler(
                handlerName: 'openPdfViewer',
                callback: (args) {
                  try {
                    final String base64Data = args[0];
                    final String pdfName = args[1];
                    
                    debugPrint("PDF Viewer açılıyor: $pdfName");
                    
                    setState(() {
                      _isViewerOpen = true;
                      _currentViewerPdfName = pdfName;
                    });
                    
                    controller.evaluateJavascript(source: """
                      try {
                        sessionStorage.setItem('currentPdfData', '$base64Data');
                        sessionStorage.setItem('currentPdfName', '$pdfName');
                        window.location.href = 'viewer.html';
                      } catch (e) {
                        console.error('Viewer açma hatası:', e);
                      }
                    """);
                  } catch (e) {
                    debugPrint("openPdfViewer error: $e");
                  }
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'sharePdf',
                callback: (args) async {
                  try {
                    final String base64Data = args[0];
                    final String fileName = args.length > 1 ? args[1] as String : 'document.pdf';
                    
                    debugPrint("PDF paylaşılıyor: $fileName");
                    
                    final bytes = _decodeBase64(base64Data);
                    final tempDir = await getTemporaryDirectory();
                    final file = File('${tempDir.path}/$fileName');
                    await file.writeAsBytes(bytes);
                    
                    await Share.shareXFiles([XFile(file.path)], text: fileName);
                    debugPrint("PDF başarıyla paylaşıldı");
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
                    final String fileName = args.length > 1 ? args[1] as String : 'document.pdf';
                    
                    debugPrint("PDF yazdırılıyor: $fileName");
                    
                    final bytes = _decodeBase64(base64Data);
                    await Printing.layoutPdf(
                      onLayout: (format) async => bytes,
                      name: fileName
                    );
                    
                    debugPrint("PDF başarıyla yazdırma diyaloğu açıldı");
                  } catch (e) {
                    debugPrint("Yazdırma Hatası: $e");
                  }
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'downloadPdf',
                callback: (args) async {
                  try {
                    final String base64Data = args[0];
                    final String originalName = args.length > 1 ? args[1] as String : 'document.pdf';
                    
                    debugPrint("PDF indiriliyor: $originalName");
                    
                    // İzin kontrolü
                    PermissionStatus status;
                    if (Platform.isAndroid) {
                      status = await Permission.manageExternalStorage.status;
                    } else {
                      status = await Permission.storage.status;
                    }
                    
                    if (!status.isGranted) {
                      debugPrint("İzin gerekli");
                      return;
                    }
                    
                    // İzin verildi, kaydet
                    final bytes = _decodeBase64(base64Data);
                    final directory = Directory('/storage/emulated/0/Download/PDF Reader');
                    if (!await directory.exists()) {
                      await directory.create(recursive: true);
                    }
                    
                    String finalFileName = originalName;
                    File file = File('${directory.path}/$finalFileName');
                    
                    int counter = 0;
                    while (await file.exists()) {
                      counter++;
                      final fileNameWithoutExt = originalName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
                      finalFileName = "$fileNameWithoutExt($counter).pdf";
                      file = File('${directory.path}/$finalFileName');
                    }
                    
                    await file.writeAsBytes(bytes);
                    debugPrint("PDF kaydedildi: ${file.path}");
                    
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
                },
              );

              // Android back button handler
              controller.addJavaScriptHandler(
                handlerName: 'androidBackPressed',
                callback: (args) async {
                  try {
                    debugPrint("Android back button pressed");
                    
                    // Mevcut URL'yi kontrol et
                    final currentUrl = await controller.getUrl();
                    final urlString = currentUrl?.toString() ?? '';
                    
                    if (urlString.contains('viewer.html')) {
                      // Viewer sayfasındaysak, index'e dön
                      await controller.evaluateJavascript(source: """
                        try {
                          window.location.href = 'index.html';
                        } catch (e) {
                          console.log('Back navigation error:', e);
                        }
                      """);
                      
                      setState(() {
                        _isViewerOpen = false;
                        _currentViewerPdfName = null;
                      });
                      
                      return true;
                    }
                    
                    return false;
                  } catch (e) {
                    debugPrint("Back button handler error: $e");
                    return false;
                  }
                },
              );

              debugPrint("Tüm JavaScript handler'ları eklendi");
            },
            onLoadStart: (controller, url) async {
              final urlString = url?.toString() ?? '';
              
              setState(() {
                _isViewerOpen = urlString.contains('viewer.html');
                
                if (!_isViewerOpen) {
                  _currentViewerPdfName = null;
                }
              });
              
              debugPrint("Sayfa yükleniyor: $urlString");
            },
            onLoadStop: (controller, url) async {
              final urlString = url?.toString() ?? '';
              debugPrint("Sayfa yüklendi: $urlString");
            },
            onReceivedError: (controller, request, error) {
              debugPrint("WebView Error: ${error.description}");
            },
            onConsoleMessage: (controller, consoleMessage) {
              debugPrint("WebView Console: ${consoleMessage.message}");
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
