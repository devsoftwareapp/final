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

  const ViewerPage({
    super.key,
    required this.pdfBase64,
    required this.pdfName,
  });

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  InAppWebViewController? controller;

  Uint8List _decodeBase64(String data) {
    if (data.contains(',')) {
      data = data.split(',').last;
    }
    return base64Decode(data);
  }

  Future<void> _resetAndLoadViewer() async {
    // 1️⃣ WebView context’i tamamen sıfırla
    await controller!.loadUrl(
      urlRequest: URLRequest(url: WebUri("about:blank")),
    );

    await Future.delayed(const Duration(milliseconds: 80));

    // 2️⃣ Viewer’ı tekrar yükle
    await controller!.loadUrl(
      urlRequest: URLRequest(
        url: WebUri(
          "file:///android_asset/flutter_assets/assets/web/viewer.html",
        ),
      ),
    );
  }

  Future<void> _savePdf(String base64, String name) async {
    PermissionStatus status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }

    if (!status.isGranted) return;

    final dir = Directory('/storage/emulated/0/Download/PDF Reader');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File('${dir.path}/$name');
    await file.writeAsBytes(_decodeBase64(base64));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("PDF Kaydedildi")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: InAppWebView(
          key: ValueKey(
            widget.pdfName +
                DateTime.now().millisecondsSinceEpoch.toString(),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            allowFileAccess: true,
            allowUniversalAccessFromFileURLs: true,
            domStorageEnabled: true,
          ),
          onWebViewCreated: (c) async {
            controller = c;

            await _resetAndLoadViewer();

            // Share
            controller!.addJavaScriptHandler(
              handlerName: 'sharePdf',
              callback: (args) async {
                final bytes = _decodeBase64(args[0]);
                final tempDir = await getTemporaryDirectory();
                final file = File('${tempDir.path}/${args[1]}');
                await file.writeAsBytes(bytes);
                await Share.shareXFiles([XFile(file.path)]);
              },
            );

            // Print
            controller!.addJavaScriptHandler(
              handlerName: 'printPdf',
              callback: (args) async {
                await Printing.layoutPdf(
                  name: args[1],
                  onLayout: (_) async => _decodeBase64(args[0]),
                );
              },
            );

            // Download
            controller!.addJavaScriptHandler(
              handlerName: 'downloadPdf',
              callback: (args) {
                _savePdf(args[0], args[1]);
              },
            );
          },
          onLoadStop: (controller, url) async {
            final safeName =
                widget.pdfName.replaceAll("'", "\\'");

            await controller.evaluateJavascript(source: """
              sessionStorage.clear();
              sessionStorage.setItem('currentPdfData', '${widget.pdfBase64}');
              sessionStorage.setItem('currentPdfName', '$safeName');

              if (typeof loadPdfIntoViewer === 'function') {
                loadPdfIntoViewer();
              }
            """);
          },
        ),
      ),
    );
  }
}
