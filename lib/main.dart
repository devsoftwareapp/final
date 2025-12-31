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

class _WebViewPageState extends State<WebViewPage> {
  InAppWebViewController? webViewController;
  bool _isViewerOpen = false;
  DateTime? _lastBackPressTime;

  // Base64 temizleme ve decode işlemi
  Uint8List _decodeBase64(String base64String) {
    String cleanBase64 = base64String;
    if (base64String.contains(',')) {
      cleanBase64 = base64String.split(',').last;
    }
    // Boşlukları ve satır sonlarını temizle
    cleanBase64 = cleanBase64.replaceAll('\n', '').replaceAll('\r', '').trim();
    return base64Decode(cleanBase64);
  }

  // Dosyayı İndirme/Kaydetme Fonksiyonu
  Future<void> _savePdfToFile(String base64Data, String fileName) async {
    // Kayıt izni kontrolü (Android 10 ve altı için)
    if (Platform.isAndroid) {
      // Android 11+ (API 30) genellikle Scoped Storage kullanır, ancak Download klasörü için izin gerekebilir.
      // Basitlik adına storage izni istiyoruz.
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
        if (!status.isGranted) return;
      }
    }

    try {
      final bytes = _decodeBase64(base64Data);
      
      // Android'de Download klasörüne, iOS'ta Documents klasörüne
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
        // Dosya adı çakışmasını önle
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
          // Javascript tarafındaki back button logic'ini tetikle
          // viewer.html içindeki window.viewerBackPressed ve index.html içindeki window.androidBackPressed
          
          if (_isViewerOpen) {
             // Viewer açıksa JS tarafındaki fonksiyonu çağır
             final result = await webViewController!.evaluateJavascript(source: "window.viewerBackPressed ? window.viewerBackPressed() : false;");
             if (result == 'exit_viewer') {
                return false; // JS halletti, biz bir şey yapmayalım (zaten index'e dönecek)
             }
             // Eğer JS false döndürdüyse native back çalışabilir ama biz genellikle JS'e bırakıyoruz
             return false; 
          } else {
             // Ana ekrandaysa (index.html)
             final result = await webViewController!.evaluateJavascript(source: "window.androidBackPressed ? window.androidBackPressed() : false;");
             
             if (result == 'exit_check') {
               // Çift tıklama ile çıkış onayı
               return true;
             }
             return false;
          }
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        // SafeArea: HTML tasarımınızda zaten padding var, o yüzden bottom'ı false yapıyoruz
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
              useHybridComposition: true, // Android klavye sorunları için
              domStorageEnabled: true,
              displayZoomControls: false,
              builtInZoomControls: false,
              safeBrowsingEnabled: false,
            ),
            // index.html içindeki "Android.openSettings()" çağrısını yakalamak için JS enjekte ediyoruz
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: """
                  // Native Android arayüzünü taklit eden bir proxy nesnesi oluşturuyoruz
                  if (typeof Android === 'undefined') {
                    window.Android = {
                      openSettings: function() {
                        window.flutter_inappwebview.callHandler('openSettingsForPermission');
                      },
                      checkPermission: function() {
                        // Basitçe false dönüyoruz, asıl kontrolü Flutter handler'da yapabiliriz
                        // Ama HTML yapısı gereği burası senkron çalışıyor.
                        return false; 
                      },
                      listPDFs: function() {
                        // Not: Senkron veri dönüşü Flutter bridge ile zordur.
                        // Dosya listeleme için HTML tarafında async bir yapıya geçilmesi önerilir.
                        // Şimdilik boş dönüyoruz.
                        return "";
                      },
                      shareFile: function(base64, name) {
                         window.flutter_inappwebview.callHandler('sharePdf', base64, name);
                      },
                      shareFileByPath: function(path) {
                         // Path ile paylaşım
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

              // --- HANDLER: AYARLARI AÇ (KRİTİK KISIM) ---
              controller.addJavaScriptHandler(
                handlerName: 'openSettingsForPermission',
                callback: (args) async {
                  debugPrint("Ayarlar isteği alındı...");
                  if (Platform.isAndroid) {
                    try {
                      final packageInfo = await PackageInfo.fromPlatform();
                      final packageName = packageInfo.packageName;

                      // Android 11+ (API 30) için "Tüm Dosya Erişimi" ekranı
                      final intent = AndroidIntent(
                        action: 'android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION',
                        data: 'package:$packageName',
                      );
                      await intent.launch();
                    } catch (e) {
                      debugPrint("Özel ayar intent hatası: $e");
                      // Hata olursa genel ayarlara git
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

              // --- HANDLER: İNDİR ---
              controller.addJavaScriptHandler(
                handlerName: 'downloadPdf',
                callback: (args) async {
                  try {
                    String base64Data = args[0];
                    String fileName = args.length > 1 ? args[1] : 'document.pdf';
                    _savePdfToFile(base64Data, fileName);
                  } catch (e) {
                    debugPrint("İndirme Hatası: $e");
                  }
                },
              );
            },
            onLoadStart: (controller, url) {
               setState(() {
                 _isViewerOpen = url.toString().contains("viewer.html");
               });
            },
            onLoadStop: (controller, url) async {
              // Sayfa yüklendiğinde viewer durumunu güncelle
              setState(() {
                 _isViewerOpen = url.toString().contains("viewer.html");
              });
            },
            onConsoleMessage: (controller, consoleMessage) {
              debugPrint("JS Console: ${consoleMessage.message}");
            },
          ),
        ),
      ),
    );
  }
}
