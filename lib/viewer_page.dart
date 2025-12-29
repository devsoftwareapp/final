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
  InAppWebViewController? _controller;

  Uint8List _decodeBase64(String base64) {
    if (base64.contains(',')) {
      base64 = base64.split(',').last;
    }
    return base64Decode(base64);
  }

  /* =============================
     DOSYA KAYDETME
     ============================= */
  Future<void> _savePdf(String base64, String name) async {
    PermissionStatus status = await Permission.storage.request();
    if (!status.isGranted) return;

    final dir = Directory('/storage/emulated/0/Download/PDF Reader');
    if (!await dir.exists()) await dir.create(recursive: true);

    File file = File('${dir.path}/$name');
    int i = 1;
    while (await file.exists()) {
      file = File('${dir.path}/(${i++})_$name');
    }

    await file.writeAsBytes(_decodeBase64(base64));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("PDF kaydedildi"),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: InAppWebView(
          /* 🔥 viewer.html HER SEFERİNDE YENİ */
          initialUrlRequest: URLRequest(
            url: WebUri(
              "file:///android_asset/flutter_assets/assets/web/viewer.html?_=${DateTime.now().millisecondsSinceEpoch}",
            ),
          ),

          /* 🔒 CACHE KAPALI */
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            allowFileAccess: true,
            allowUniversalAccessFromFileURLs: true,
            cacheEnabled: false,
            clearCache: true,
          ),

          onWebViewCreated: (controller) {
            _controller = controller;

            /* ===== JS → FLUTTER KÖPRÜLERİ ===== */

            controller.addJavaScriptHandler(
              handlerName: 'sharePdf',
              callback: (args) async {
                final bytes = _decodeBase64(args[0]);
                final dir = await getTemporaryDirectory();
                final file = File('${dir.path}/${args[1]}');
                await file.writeAsBytes(bytes);
                await Share.shareXFiles([XFile(file.path)]);
              },
            );

            controller.addJavaScriptHandler(
              handlerName: 'printPdf',
              callback: (args) async {
                await Printing.layoutPdf(
                  name: args[1],
                  onLayout: (_) async => _decodeBase64(args[0]),
                );
              },
            );

            controller.addJavaScriptHandler(
              handlerName: 'downloadPdf',
              callback: (args) {
                _savePdf(args[0], args[1]);
              },
            );
          },

          /* 🔥 SADE VE GARANTİLİ ENJEKSİYON */
          onLoadStop: (controller, url) async {
            final safeName = widget.pdfName.replaceAll("'", "\\'");
            await controller.evaluateJavascript(source: """
              sessionStorage.setItem('currentPdfData', '${widget.pdfBase64}');
              sessionStorage.setItem('currentPdfName', '$safeName');
            """);
          },
        ),
      ),
    );
  }
}
