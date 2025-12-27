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
          initialUrlRequest: URLRequest(
            url: WebUri("file:///android_asset/flutter_assets/assets/iframe.html")
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            allowFileAccess: true,
            allowFileAccessFromFileURLs: true, 
            allowUniversalAccessFromFileURLs: true,
            domStorageEnabled: true, // SessionStorage için ZORUNLU
            useHybridComposition: true,
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;

            // Paylaşma
            controller.addJavaScriptHandler(handlerName: 'flutterShare', callback: (args) async {
              try {
                final String rawData = args[0]['pdfData'];
                final String fileName = args[0]['pdfName'] ?? "belge.pdf";
                
                // Base64 temizleme
                final String base64String = rawData.contains(',') ? rawData.split(',').last : rawData;
                final bytes = base64Decode(base64String.trim());

                final tempDir = await getTemporaryDirectory();
                final file = File('${tempDir.path}/$fileName');
                await file.writeAsBytes(bytes);

                await Share.shareXFiles([XFile(file.path)]);
              } catch (e) {
                // Telefonunda hata olup olmadığını anlamak için bir Snackbar gösterelim
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Paylaşma Hatası: $e")));
                }
              }
            });

            // Yazdırma
            controller.addJavaScriptHandler(handlerName: 'flutterPrint', callback: (args) async {
              try {
                final String rawData = args[0]['pdfData'];
                final String base64String = rawData.contains(',') ? rawData.split(',').last : rawData;
                final bytes = base64Decode(base64String.trim());

                await Printing.layoutPdf(onLayout: (format) async => bytes);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Yazdırma Hatası: $e")));
                }
              }
            });
          },
        ),
      ),
    );
  }
}

