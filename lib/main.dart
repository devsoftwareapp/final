import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Uygulama ayarlardan geri döndüğünde
      _checkAndUpdatePermissionStatus();
    }
  }

  // İzin durumunu kontrol et ve JS'e bildir
  Future<void> _checkAndUpdatePermissionStatus() async {
    if (webViewController == null) return;
    
    final hasPermission = await _checkStoragePermission();
    
    // JS tarafına izin durumunu bildir ve yeniden tarama tetikle
    await webViewController!.evaluateJavascript(source: """
      (function() {
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
      // Android 13+ için
      if (await Permission.photos.isGranted || 
          await Permission.videos.isGranted ||
          await Permission.audio.isGranted) {
        return true;
      }
      
      // Android 11-12 için manageExternalStorage
      if (await Permission.manageExternalStorage.isGranted) {
        return true;
      }
      
      // Android 10 ve altı için storage
      if (await Permission.storage.isGranted) {
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
        // Yaygın PDF dizinlerini tara
        List<String> searchPaths = [
          '/storage/emulated/0/Download',
          '/storage/emulated/0/Documents',
          '/storage/emulated/0/DCIM',
        ];

        for (String path in searchPaths) {
          try {
            final directory = Directory(path);
            if (await directory.exists()) {
              await for (var entity in directory.list(recursive: true, followLinks: false)) {
                if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
                  try {
                    final stat = await entity.stat();
                    pdfFiles.add({
                      'path': entity.path,
                      'name': entity.path.split('/').last,
                      'size': stat.size,
                      'modified': stat.modified.toIso8601String(),
                    });
                  } catch (e) {
                    debugPrint("Dosya bilgisi alınamadı: ${entity.path}");
                  }
                }
              }
            }
          } catch (e) {
            debugPrint("Dizin tarama hatası: $path - $e");
          }
        }
      }
    } catch (e) {
      debugPrint("PDF listeleme hatası: $e");
    }
    
    return pdfFiles;
  }

  // Dosya boyutunu formatla
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // Base64 temizleme ve decode işlemi
  Uint8List _decodeBase64(String base64String) {
    String cleanBase64 = base64String;
    if (base64String.contains(',')) {
      cleanBase64 = base64String.split(',').last;
    }
    cleanBase64 = cleanBase64.replaceAll('\n', '').replaceAll('\r', '').trim();
    return base64Decode(cleanBase64);
  }

  // Dosyayı İndirme/Kaydetme Fonksiyonu
  Future<void> _savePdfToFile(String base64Data, String fileName) async {
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
        if (!status.isGranted) return;
      }
    }

    try {
      final bytes = _decodeBase64(base64Data);
      
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (!await directory.exists()) {
        directory = await getExternalStorageDirectory();
      }

      if (directory != null) {
        final file = File('${directory.path}/$fileName');
        int counter = 1;
        String finalName = fileName;
        String nameWithoutExt = fileName.replaceAll('.pdf', '');
        
        while (await file.exists()) {
          finalName = '$nameWithoutExt ($counter).pdf';
          counter++;
        }
        
        final finalFile = File('${directory.path}/$finalName');
        await finalFile.writeAsBytes(bytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Kaydedildi: ${finalFile.path}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Dosya kaydetme hatası: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dosya kaydedilemedi.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (webViewController != null) {
          if (_isViewerOpen) {
            final result = await webViewController!.evaluateJavascript(
              source: "window.viewerBackPressed ? window.viewerBackPressed() : false;"
            );
            if (result == 'exit_viewer') {
              return false;
            }
            return false;
          } else {
            final result = await webViewController!.evaluateJavascript(
              source: "window.androidBackPressed ? window.androidBackPressed() : false;"
            );
            
            if (result == 'exit_check') {
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
              // ✅ OPFS desteği için gerekli
              sharedCookiesEnabled: true,
              thirdPartyCookiesEnabled: true,
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: """
                  if (typeof Android === 'undefined') {
                    window.Android = {
                      openSettings: function() {
                        window.flutter_inappwebview.callHandler('openSettingsForPermission');
                      },
                      checkPermission: function() {
                        // Async yapacağız, şimdilik false dön
                        return false;
                      },
                      listPDFs: function() {
                        // Bu fonksiyon artık kullanılmayacak
                        return "";
                      },
                      getFileAsBase64: function(path) {
                        // Bu fonksiyon için async handler ekleyeceğiz
                        return "";
                      },
                      shareFile: function(base64, name) {
                        window.flutter_inappwebview.callHandler('sharePdf', base64, name);
                      },
                      shareFileByPath: function(path) {
                        window.flutter_inappwebview.callHandler('sharePdfByPath', path);
                      },
                      printFile: function(base64) {
                        window.flutter_inappwebview.callHandler('printPdf', base64, 'belge.pdf');
                      }
                    };
                  }
                """,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            onWebViewCreated: (controller) {
              webViewController = controller;

              // --- HANDLER: İZİN DURUMU KONTROL ET ---
              controller.addJavaScriptHandler(
                handlerName: 'checkStoragePermission',
                callback: (args) async {
                  return await _checkStoragePermission();
                },
              );

              // --- HANDLER: PDF DOSYALARINI LİSTELE ---
              controller.addJavaScriptHandler(
                handlerName: 'listPdfFiles',
                callback: (args) async {
                  final pdfFiles = await _listPdfFiles();
                  return jsonEncode(pdfFiles);
                },
              );

              // --- HANDLER: DOSYA İÇERİĞİNİ BASE64 OLARAK AL ---
              controller.addJavaScriptHandler(
                handlerName: 'getFileAsBase64',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      final bytes = await file.readAsBytes();
                      
                      // ✅ Büyük dosyalar için sessionStorage yerine OPFS kullanılacak
                      // Bu yüzden sadece base64 string dönüyoruz
                      return 'data:application/pdf;base64,${base64Encode(bytes)}';
                    }
                  } catch (e) {
                    debugPrint("Dosya okuma hatası: $e");
                  }
                  return null;
                },
              );

              // --- HANDLER: AYARLARI AÇ ---
              controller.addJavaScriptHandler(
                handlerName: 'openSettingsForPermission',
                callback: (args) async {
                  debugPrint("Ayarlar isteği alındı...");
                  if (Platform.isAndroid) {
                    try {
                      final packageInfo = await PackageInfo.fromPlatform();
                      final packageName = packageInfo.packageName;

                      final intent = AndroidIntent(
                        action: 'android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION',
                        data: 'package:$packageName',
                      );
                      await intent.launch();
                    } catch (e) {
                      debugPrint("Özel ayar intent hatası: $e");
                      await openAppSettings();
                    }
                  } else {
                    await openAppSettings();
                  }
                },
              );

              // --- HANDLER: PAYLAŞ ---
              controller.addJavaScriptHandler(
                handlerName: 'sharePdf',
                callback: (args) async {
                  try {
                    String base64Data = args[0];
                    String fileName = args.length > 1 ? args[1] : 'document.pdf';
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

              // --- HANDLER: PATH İLE PAYLAŞ ---
              controller.addJavaScriptHandler(
                handlerName: 'sharePdfByPath',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      await Share.shareXFiles([XFile(file.path)]);
                    } else {
                      debugPrint("Dosya bulunamadı: $filePath");
                    }
                  } catch (e) {
                    debugPrint("Path ile paylaşma hatası: $e");
                  }
                },
              );

              // --- HANDLER: YAZDIR ---
              controller.addJavaScriptHandler(
                handlerName: 'printPdf',
                callback: (args) async {
                  try {
                    String base64Data = args[0];
                    String fileName = args.length > 1 ? args[1] : 'document.pdf';
                    final bytes = _decodeBase64(base64Data);
                    
                    await Printing.layoutPdf(
                      onLayout: (format) async => bytes,
                      name: fileName,
                    );
                  } catch (e) {
                    debugPrint("Yazdırma Hatası: $e");
                  }
                },
              );

              // --- HANDLER: PATH İLE YAZDIR ---
              controller.addJavaScriptHandler(
                handlerName: 'printPdfByPath',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      final bytes = await file.readAsBytes();
                      await Printing.layoutPdf(
                        onLayout: (format) async => bytes,
                        name: file.path.split('/').last,
                      );
                    } else {
                      debugPrint("Dosya bulunamadı: $filePath");
                    }
                  } catch (e) {
                    debugPrint("Path ile yazdırma hatası: $e");
                  }
                },
              );

              // --- HANDLER: İNDİR ---
              controller.addJavaScriptHandler(
                handlerName: 'downloadPdf',
                callback: (args) async {
                  try {
                    String base64Data = args[0];
                    String fileName = args.length > 1 ? args[1] : 'document.pdf';
                    await _savePdfToFile(base64Data, fileName);
                  } catch (e) {
                    debugPrint("İndirme Hatası: $e");
                  }
                },
              );

              // --- HANDLER: OPFS BOYUT KONTROLÜ ---
              controller.addJavaScriptHandler(
                handlerName: 'checkOPFSSupport',
                callback: (args) async {
                  // OPFS WebView'de destekleniyor
                  return true;
                },
              );
            },
            onLoadStart: (controller, url) {
              setState(() {
                _isViewerOpen = url.toString().contains("viewer.html");
              });
            },
            onLoadStop: (controller, url) async {
              setState(() {
                _isViewerOpen = url.toString().contains("viewer.html");
              });
              
              // Sayfa yüklendikten sonra izin durumunu kontrol et
              await _checkAndUpdatePermissionStatus();
            },
            onConsoleMessage: (controller, consoleMessage) {
              debugPrint("JS Console: ${consoleMessage.message}");
            },
            // ✅ OPFS için gerekli - Storage erişim hatalarını önle
            onPermissionRequest: (controller, permissionRequest) async {
              return PermissionResponse(
                resources: permissionRequest.resources,
                action: PermissionResponseAction.GRANT,
              );
            },
          ),
        ),
      ),
    );
  }
}
