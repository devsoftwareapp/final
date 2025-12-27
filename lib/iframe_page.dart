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
      // Top bar'ı HTML içinde yaptığın için Scaffold'da AppBar kullanmıyoruz
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri("file:///android_asset/flutter_assets/assets/iframe.html"),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            allowFileAccess: true,
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,
            useHybridComposition: true,
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;

            // --- JAVASCRIPT HANDLERS ---

            // 1. PAYLAŞMA
            controller.addJavaScriptHandler(handlerName: 'flutterShare', callback: (args) async {
              final String rawData = args[0]['pdfData'];
              final String fileName = args[0]['pdfName'];
              
              try {
                final String base64String = rawData.contains(',') ? rawData.split(',').last : rawData;
                final bytes = base64Decode(base64String);

                final tempDir = await getTemporaryDirectory();
                final file = File('${tempDir.path}/$fileName');
                await file.writeAsBytes(bytes);

                await Share.shareXFiles([XFile(file.path)], text: '$fileName Paylaşılıyor');
              } catch (e) {
                debugPrint("Paylaşma Hatası: $e");
              }
            });

            // 2. YAZDIRMA
            controller.addJavaScriptHandler(handlerName: 'flutterPrint', callback: (args) async {
              final String rawData = args[0]['pdfData'];
              final String fileName = args[0]['pdfName'];

              try {
                final String base64String = rawData.contains(',') ? rawData.split(',').last : rawData;
                final bytes = base64Decode(base64String);

                await Printing.layoutPdf(
                  onLayout: (format) async => bytes,
                  name: fileName,
                );
              } catch (e) {
                debugPrint("Yazdırma Hatası: $e");
              }
            });
          },
        ),
      ),
    );
  }
}
