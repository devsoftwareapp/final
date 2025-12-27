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
    // Veriyi güvenli bir şekilde alalım
    final args = ModalRoute.of(context)!.settings.arguments;
    final String pdfBase64 = args != null ? args as String : "";

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
            // Android için en stabil yerel yol formatı:
            initialUrlRequest: URLRequest(
              url: WebUri("file:///android_asset/flutter_assets/assets/iframe.html"),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true, // sessionStorage için kritik
              allowFileAccess: true,
              allowContentAccess: true,
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
              useHybridComposition: true,
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;

              // Paylaşma Handler
              controller.addJavaScriptHandler(handlerName: 'flutterShare', callback: (args) async {
                if (args.isNotEmpty) {
                  await _handleShare(args[0]['pdfData'], args[0]['pdfName']);
                }
              });

              // Yazdırma Handler
              controller.addJavaScriptHandler(handlerName: 'flutterPrint', callback: (args) async {
                if (args.isNotEmpty) {
                  await _handlePrint(args[0]['pdfData']);
                }
              });
            },
            onLoadStop: (controller, url) async {
              // Sayfa tamamen yüklendiğinde veriyi enjekte et
              if (pdfBase64.isNotEmpty) {
                await controller.evaluateJavascript(source: """
                  sessionStorage.setItem('pdfData', '$pdfBase64');
                  if (typeof loadPdf === 'function') { 
                    loadPdf(); 
                  }
                """);
              }
              setState(() => _isLoading = false);
            },
            onLoadError: (controller, url, code, message) {
              debugPrint("Iframe Yükleme Hatası: $message");
              setState(() => _isLoading = false);
            },
          ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  // Flutter AppBar'dan HTML'deki fonksiyonu çağırmak için
  void _triggerJSHandler(String action) {
    webViewController?.evaluateJavascript(source: "if(window.$action) { window.$action(); }");
  }

  // Paylaşma Mantığı
  Future<void> _handleShare(String rawData, String? fileName) async {
    try {
      final String base64String = rawData.contains(',') ? rawData.split(',').last : rawData;
      final bytes = base64Decode(base64String.trim());
      
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
      final String base64String = rawData.contains(',') ? rawData.split(',').last : rawData;
      final bytes = base64Decode(base64String.trim());
      await Printing.layoutPdf(onLayout: (format) async => bytes);
    } catch (e) {
      _showError("Yazdırma Hatası: $e");
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}
