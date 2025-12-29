import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:permission_handler/permission_handler.dart';

class ViewerPage extends StatefulWidget {
  final String pdfBase64;
  final String pdfName;

  const ViewerPage({super.key, required this.pdfBase64, required this.pdfName});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  InAppWebViewController? webViewController;

  Uint8List _decodeBase64(String base64String) {
    if (base64String.contains(',')) {
      base64String = base64String.split(',').last;
    }
    return base64Decode(base64String);
  }

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
              decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.folder_open_rounded, size: 48, color: Colors.redAccent),
            ),
            const SizedBox(height: 24),
            const Text("Dosya Erişimi Gerekli", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 12),
            const Text(
              "Cihazınızdaki dosyaları görmek ve kaydetmek için lütfen izin verin.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Şimdi Değil", style: TextStyle(color: Colors.grey)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                    onPressed: () async {
                      Navigator.pop(context);
                      await Permission.manageExternalStorage.request();
                    },
                    child: const Text("Ayarlar"),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Future<void> _savePdfToFile(String base64Data, String originalName) async {
    PermissionStatus status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) status = await Permission.storage.status;

    if (!status.isGranted) {
      _showPermissionDialog(base64Data, originalName);
      return;
    }

    final directory = Directory('/storage/emulated/0/Download/PDF Reader');
    if (!await directory.exists()) await directory.create(recursive: true);

    File file = File('${directory.path}/$originalName');
    try {
      await file.writeAsBytes(_decodeBase64(base64Data));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PDF Kaydedildi"), backgroundColor: Colors.green));
    } catch (e) {
      debugPrint("Hata: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri("file:///android_asset/flutter_assets/assets/web/viewer.html"),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            allowFileAccess: true,
            allowUniversalAccessFromFileURLs: true,
            domStorageEnabled: true,
            clearCache: true, // Önbelleği temizle
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;
            controller.addJavaScriptHandler(handlerName: 'sharePdf', callback: (args) async {
              final bytes = _decodeBase64(args[0]);
              final tempDir = await getTemporaryDirectory();
              final file = File('${tempDir.path}/${args[1]}');
              await file.writeAsBytes(bytes);
              await Share.shareXFiles([XFile(file.path)]);
            });
            controller.addJavaScriptHandler(handlerName: 'printPdf', callback: (args) async {
              await Printing.layoutPdf(onLayout: (format) async => _decodeBase64(args[0]), name: args[1]);
            });
            controller.addJavaScriptHandler(handlerName: 'downloadPdf', callback: (args) {
              _savePdfToFile(args[0], args[1]);
            });
          },
          onLoadStart: (controller, url) async {
            // Veriyi sayfa yüklenirken enjekte ediyoruz
            final String safeBase64 = widget.pdfBase64;
            final String safeName = widget.pdfName.replaceAll("'", "\\'");
            await controller.evaluateJavascript(source: """
              sessionStorage.clear();
              sessionStorage.setItem('currentPdfData', '$safeBase64');
              sessionStorage.setItem('currentPdfName', '$safeName');
            """);
          },
          onLoadStop: (controller, url) async {
            // Sayfa bittiğinde yükleme fonksiyonunu tetikliyoruz
            await controller.evaluateJavascript(source: """
              if (typeof loadPdfIntoViewer === 'function') {
                loadPdfIntoViewer();
              } else {
                setTimeout(function() { if (typeof loadPdfIntoViewer === 'function') loadPdfIntoViewer(); }, 500);
              }
            """);
          },
        ),
      ),
    );
  }
}
