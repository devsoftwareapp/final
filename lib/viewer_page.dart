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
              "Cihazınızdaki dosyaları görmek, düzenlemek ve güncellemek için lütfen gerekli izni verin.",
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

  Future<void> _savePdfToFile(String base64Data, String originalName) async {
    PermissionStatus status;
    if (Platform.isAndroid) {
      status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) status = await Permission.storage.status;
    } else {
      status = await Permission.storage.status;
    }

    if (!status.isGranted) {
      _showPermissionDialog(base64Data, originalName);
      return;
    }

    String baseFileName = originalName.contains('.') 
        ? "${originalName.substring(0, originalName.lastIndexOf('.'))}_update" 
        : "${originalName}_update";
    
    final directory = Directory('/storage/emulated/0/Download/PDF Reader');
    if (!await directory.exists()) await directory.create(recursive: true);

    int counter = 0;
    String finalFileName = "$baseFileName.pdf";
    File file = File('${directory.path}/$finalFileName');

    while (await file.exists()) {
      counter++;
      finalFileName = "$baseFileName($counter).pdf";
      file = File('${directory.path}/$finalFileName');
    }

    try {
      await file.writeAsBytes(_decodeBase64(base64Data));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Kaydedildi: $finalFileName"), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) { debugPrint("Hata: $e"); }
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
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;

            // Share Handler
            controller.addJavaScriptHandler(handlerName: 'sharePdf', callback: (args) async {
              final bytes = _decodeBase64(args[0]);
              final tempDir = await getTemporaryDirectory();
              final file = File('${tempDir.path}/${args[1]}');
              await file.writeAsBytes(bytes);
              await Share.shareXFiles([XFile(file.path)], text: args[1]);
            });

            // Print Handler
            controller.addJavaScriptHandler(handlerName: 'printPdf', callback: (args) async {
              await Printing.layoutPdf(onLayout: (format) async => _decodeBase64(args[0]), name: args[1]);
            });

            // Download Handler
            controller.addJavaScriptHandler(handlerName: 'downloadPdf', callback: (args) {
              _savePdfToFile(args[0], args[1]);
            });
          },
          onLoadStop: (controller, url) async {
            // Sayfa yüklendiğinde veriyi sessionStorage'a aktar
            await controller.evaluateJavascript(source: """
              sessionStorage.setItem('currentPdfData', '${widget.pdfBase64}');
              sessionStorage.setItem('currentPdfName', '${widget.pdfName}');
              // Viewer zaten DOMContentLoaded ile veriyi otomatik çekecek
            """);
          },
        ),
      ),
    );
  }
}
