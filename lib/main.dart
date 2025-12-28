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

  // GÖRSELDEKİ İZİN TASARIMINI GÖSTEREN FONKSİYON
  void _showPermissionDialog(String base64Data, String originalName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
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
                    onPressed: () {
                      openAppSettings(); // Ayarlara gönderir
                      Navigator.pop(context);
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

  // Dosyayı diske yazan ana fonksiyon
  Future<void> _savePdfToFile(String base64Data, String originalName) async {
    // 1. İzinleri Kontrol Et
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) status = await Permission.storage.status;

    // Eğer izin yoksa görsel diyaloğu göster ve dur
    if (!status.isGranted) {
      _showPermissionDialog(base64Data, originalName);
      return;
    }

    // 2. İsimlendirme Mantığı
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

    // 3. Klasör Hazırlığı
    final directory = Directory('/storage/emulated/0/Download/PDF Reader');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    // 4. Dosya Çakışma Kontrolü
    int counter = 0;
    String finalFileName = "$baseFileName$extension";
    File file = File('${directory.path}/$finalFileName');

    while (await file.exists()) {
      counter++;
      finalFileName = "$baseFileName($counter)$extension";
      file = File('${directory.path}/$finalFileName');
    }

    // 5. Yazma İşlemi (Sessiz Kayıt)
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
                // Doğrudan akıllı kayıt fonksiyonunu çağırır
                _savePdfToFile(base64Data, originalName);
              },
            );
          },
        ),
      ),
    );
  }
}
