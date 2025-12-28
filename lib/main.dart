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

  Uint8List _decodeBase64(String base64String) {
    if (base64String.contains(',')) {
      base64String = base64String.split(',').last;
    }
    return base64Decode(base64String);
  }

  // İzinleri kontrol eden ve gerekirse isteyen fonksiyon
  Future<bool> _checkAndRequestPermission() async {
    // Android 11 ve üzeri için 'Tüm Dosyalara Erişim' kontrolü
    if (await Permission.manageExternalStorage.isGranted) return true;
    
    // Klasik depolama izni kontrolü
    if (await Permission.storage.isGranted) return true;

    // Eğer izin yoksa, önce depolama iste, olmazsa manage iste
    var status = await Permission.storage.request();
    if (status.isGranted) return true;

    // Android 11+ için özel izin isteme
    if (await Permission.manageExternalStorage.request().isGranted) return true;

    return false;
  }

  // Dosyayı diske yazan ana fonksiyon
  Future<void> _savePdfToFile(String base64Data, String originalName) async {
    bool hasPermission = await _checkAndRequestPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Dosya kaydetmek için izin verilmedi.")),
        );
      }
      return;
    }

    // 1. İsimlendirme Mantığı: "dosya.pdf" -> "dosya_update.pdf"
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

    // 2. Klasör Hazırlığı
    final directory = Directory('/storage/emulated/0/Download/PDF Reader');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    // 3. Aynı Dosya Varsa Numara Ekleme (1), (2)...
    int counter = 0;
    String finalFileName = "$baseFileName$extension";
    File file = File('${directory.path}/$finalFileName');

    while (await file.exists()) {
      counter++;
      finalFileName = "$baseFileName($counter)$extension";
      file = File('${directory.path}/$finalFileName');
    }

    // 4. Yazma İşlemi
    try {
      final bytes = _decodeBase64(base64Data);
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Kaydedildi: $finalFileName"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print("Kaydetme Hatası: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;

            controller.addJavaScriptHandler(
              handlerName: 'openPdfViewer',
              callback: (args) {
                final String base64Data = args[0];
                final String pdfName = args[1];
                controller.evaluateJavascript(source: """
                  sessionStorage.setItem('currentPdfData', '$base64Data');
                  sessionStorage.setItem('currentPdfName', '$pdfName');
                  window.location.href = 'viewer.html';
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
                  print("Paylaşma Hatası: $e");
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
                  print("Yazdırma Hatası: $e");
                }
              },
            );

            controller.addJavaScriptHandler(
              handlerName: 'downloadPdf',
              callback: (args) async {
                final String base64Data = args[0];
                final String originalName = args[1];

                // İlk tıklamada sadece bir kez onay sorar, izinleri otomatik halleder
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Dosyayı Kaydet"),
                    content: const Text("Düzenlenen PDF 'Download/PDF Reader' klasörüne kaydedilecek. Onaylıyor musunuz?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _savePdfToFile(base64Data, originalName);
                        },
                        child: const Text("Kaydet"),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
