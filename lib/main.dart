import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:collection'; // Hata veren UnmodifiableListView için gerekli kütüphane

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
    cleanBase64 = cleanBase64.replaceAll('\n', '').replaceAll('\r', '').trim();
    return base64Decode(cleanBase64);
  }

  // Cihazdaki PDF dosyalarını tarayıp HTML'in anlayacağı formatta (|| ayırıcısı ile) döndürür
  Future<String> _scanDeviceForPDFs() async {
    try {
      if (Platform.isAndroid) {
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) return "PERMISSION_DENIED";
      }

      final List<String> pdfPaths = [];
      // Android için taranacak ana klasörler
      final List<String> commonPaths = [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Documents',
        '/storage/emulated/0/DCIM',
      ];

      for (final scanPath in commonPaths) {
        final directory = Directory(scanPath);
        if (await directory.exists()) {
          final entities = await directory.list(recursive: false).toList();
          for (var entity in entities) {
            if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
              pdfPaths.add(entity.path);
            }
          }
        }
      }
      return pdfPaths.isEmpty ? "" : pdfPaths.join('||');
    } catch (e) {
      debugPrint("Tarama hatası: $e");
      return "ERROR";
    }
  }

  Future<void> _savePdfToFile(String base64Data, String fileName) async {
    if (Platform.isAndroid) {
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) return;
      }
    }

    try {
      final bytes = _decodeBase64(base64Data);
      Directory? directory = Directory('/storage/emulated/0/Download');
      
      if (!await directory.exists()) {
        directory = await getExternalStorageDirectory();
      }

      if (directory != null) {
        final file = File('${directory.path}/$fileName');
        int counter = 1;
        String finalName = fileName;
        String nameWithoutExt = fileName.replaceAll('.pdf', '');
        
        File finalFile = file;
        while (await finalFile.exists()) {
            finalName = '$nameWithoutExt ($counter).pdf';
            finalFile = File('${directory.path}/$finalName');
            counter++;
        }
        
        await finalFile.writeAsBytes(bytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kaydedildi: $finalName'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      debugPrint("Kayıt hatası: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (webViewController != null) {
          if (_isViewerOpen) {
             await webViewController!.evaluateJavascript(source: "window.location.href = 'index.html';");
             setState(() => _isViewerOpen = false);
             return false; 
          } else {
             final result = await webViewController!.evaluateJavascript(source: "window.androidBackPressed ? window.androidBackPressed() : false;");
             if (result == 'exit_check') return true;
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
              allowUniversalAccessFromFileURLs: true,
              useHybridComposition: true,
              domStorageEnabled: true,
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: """
                  if (typeof Android === 'undefined') {
                    window.Android = {
                      openSettings: function() { window.flutter_inappwebview.callHandler('openSettings'); },
                      checkPermission: function() { return window.flutter_inappwebview.callHandler('checkPermission'); },
                      listPDFs: function() { return window.flutter_inappwebview.callHandler('listPDFs'); },
                      shareFile: function(base64, name) { window.flutter_inappwebview.callHandler('sharePdf', base64, name); },
                      printFile: function(base64) { window.flutter_inappwebview.callHandler('printPdf', base64); }
                    };
                  }
                """,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            onWebViewCreated: (controller) {
              webViewController = controller;

              // İzin Durumu Kontrolü
              controller.addJavaScriptHandler(handlerName: 'checkPermission', callback: (args) async {
                if (Platform.isAndroid) {
                  return await Permission.manageExternalStorage.isGranted;
                }
                return await Permission.storage.isGranted;
              });

              // Ayarlar Sayfasını Aç (MANAGE_EXTERNAL_STORAGE için)
              controller.addJavaScriptHandler(handlerName: 'openSettings', callback: (args) async {
                if (Platform.isAndroid) {
                  try {
                    final packageInfo = await PackageInfo.fromPlatform();
                    final intent = AndroidIntent(
                      action: 'android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION',
                      data: 'package:${packageInfo.packageName}',
                    );
                    await intent.launch();
                  } catch (e) {
                    await openAppSettings();
                  }
                } else {
                  await openAppSettings();
                }
              });

              // Cihazdaki PDF'leri Listele
              controller.addJavaScriptHandler(handlerName: 'listPDFs', callback: (args) async {
                return await _scanDeviceForPDFs();
              });

              // Paylaşım İşlemi
              controller.addJavaScriptHandler(handlerName: 'sharePdf', callback: (args) async {
                final bytes = _decodeBase64(args[0]);
                final tempDir = await getTemporaryDirectory();
                final file = File('${tempDir.path}/${args[1]}');
                await file.writeAsBytes(bytes);
                await Share.shareXFiles([XFile(file.path)]);
              });

              // Yazdırma İşlemi
              controller.addJavaScriptHandler(handlerName: 'printPdf', callback: (args) async {
                final bytes = _decodeBase64(args[0]);
                await Printing.layoutPdf(onLayout: (format) async => bytes);
              });
            },
            onLoadStart: (controller, url) {
               setState(() { _isViewerOpen = url.toString().contains("viewer.html"); });
            },
            onConsoleMessage: (controller, consoleMessage) {
              debugPrint("JS: ${consoleMessage.message}");
            },
          ),
        ),
      ),
    );
  }
}
