import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';

class IframePage extends StatefulWidget {
  const IframePage({super.key});

  @override
  State<IframePage> createState() => _IframePageState();
}

class _IframePageState extends State<IframePage> {
  InAppWebViewController? webViewController;
  bool _isLoading = true;

  @override
  Widget build(BuildContext context) {
    // main.dart'tan gönderilen veriyi alıyoruz
    final String pdfBase64 = ModalRoute.of(context)!.settings.arguments as String;

    return Scaffold(
      appBar: AppBar(
        title: const Text("PDF Görüntüle"),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _triggerJSHandler("requestShare"),
          ),
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () => _triggerJSHandler("requestPrint"),
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri("asset:///assets/iframe.html"),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              allowFileAccess: true,
              allowUniversalAccessFromFileURLs: true,
              useHybridComposition: true,
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;

              // Paylaşma İşlemi
              controller.addJavaScriptHandler(handlerName: 'flutterShare', callback: (args) async {
                await _handleShare(args[0]['pdfData'], args[0]['pdfName']);
              });

              // Yazdırma İşlemi
              controller.addJavaScriptHandler(handlerName: 'flutterPrint', callback: (args) async {
                await _handlePrint(args[0]['pdfData']);
              });
            },
            onLoadStop: (controller, url) async {
              // Sayfa yüklendiğinde veriyi HTML içindeki sessionStorage'a yazıyoruz
              await controller.evaluateJavascript(source: """
                sessionStorage.setItem('pdfData', '$pdfBase64');
                if (typeof loadPdf === 'function') { loadPdf(); }
              """);
              setState(() => _isLoading = false);
            },
          ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  // JS tarafındaki bir fonksiyonu tetiklemek için yardımcı
  void _triggerJSHandler(String action) {
    webViewController?.evaluateJavascript(source: "window.$action();");
  }

  // Paylaşma Mantığı
  Future<void> _handleShare(String rawData, String? fileName) async {
    try {
      final bytes = base64Decode(rawData.split(',').last);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${fileName ?? "belge.pdf"}');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      _showError("Paylaşma Hatası: $e");
    }
  }

  // Yazdırma Mantığı
  Future<void> _handlePrint(String rawData) async {
    try {
      final bytes = base64Decode(rawData.split(',').last);
      await Printing.layoutPdf(onLayout: (format) async => bytes);
    } catch (e) {
      _showError("Yazdırma Hatası: $e");
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
