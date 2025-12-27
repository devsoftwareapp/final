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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri("file:///android_asset/flutter_assets/assets/iframe.html")),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            allowFileAccess: true,
            allowFileAccessFromFileURLs: true, 
            allowUniversalAccessFromFileURLs: true,
            domStorageEnabled: true,
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;

            // Paylaşma İşlemi
            controller.addJavaScriptHandler(handlerName: 'flutterShare', callback: (args) async {
              final String data = args[0]['pdfData'];
              final String name = args[0]['pdfName'];
              try {
                final bytes = base64Decode(data.split(',').last);
                final tempDir = await getTemporaryDirectory();
                final file = File('${tempDir.path}/$name');
                await file.writeAsBytes(bytes);
                await Share.shareXFiles([XFile(file.path)]);
              } catch (e) { debugPrint("Paylaşma Hatası: $e"); }
            });

            // Yazdırma İşlemi
            controller.addJavaScriptHandler(handlerName: 'flutterPrint', callback: (args) async {
              final String data = args[0]['pdfData'];
              try {
                final bytes = base64Decode(data.split(',').last);
                await Printing.layoutPdf(onLayout: (format) async => bytes);
              } catch (e) { debugPrint("Yazdırma Hatası: $e"); }
            });
          },
          // JS loglarını Flutter terminaline düşürür
          onConsoleMessage: (controller, consoleMessage) {
            debugPrint("WEB LOG: ${consoleMessage.message}");
          },
        ),
      ),
    );
  }
}
