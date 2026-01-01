import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/pdf_service.dart';

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  InAppWebViewController? webViewController;
  late final PDFService _pdfService;

  @override
  void initState() {
    super.initState();
    _pdfService = PDFService();
  }

  @override
  void dispose() {
    _cleanupViewer();
    super.dispose();
  }

  Future<void> _cleanupViewer() async {
    if (webViewController != null) {
      await webViewController!.evaluateJavascript(source: '''
        (function () {
          try {
            if (typeof viewerPdfManager !== 'undefined' &&
                viewerPdfManager.cleanup) {
              viewerPdfManager.cleanup();
            }
            sessionStorage.clear();
          } catch (e) {}
        })();
      ''');
    }
    await _pdfService.cleanupTempFiles();
  }

  Future<void> _goBack() async {
    await _cleanupViewer();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _goBack();
        return false;
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(
                "file:///android_asset/flutter_assets/assets/web/viewer.html",
              ),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              allowFileAccess: true,
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
              useHybridComposition: true,
              domStorageEnabled: true,
              databaseEnabled: true,
              cacheEnabled: true,
              hardwareAcceleration: true,
              mixedContentMode:
                  MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            ),
            initialUserScripts:
                UnmodifiableListView<UserScript>([
              UserScript(
                source: '''
                  window.goBackToIndex = function () {
                    window.flutter_inappwebview
                      .callHandler('goBackToIndex');
                  };
                ''',
                injectionTime:
                    UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            onWebViewCreated: (controller) {
              webViewController = controller;

              controller.addJavaScriptHandler(
                handlerName: 'goBackToIndex',
                callback: (_) async => _goBack(),
              );

              controller.addJavaScriptHandler(
                handlerName: 'getPdfPath',
                callback: (args) {
                  final sourcePath = args[0];
                  final fileName = args.length > 1
                      ? args[1]
                      : sourcePath.split('/').last;
                  return _pdfService.getPdfPath(
                    sourcePath,
                    fileName,
                  );
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'readPdfFile',
                callback: (args) =>
                    _pdfService.readPdfFile(args[0]),
              );

              controller.addJavaScriptHandler(
                handlerName: 'sharePdf',
                callback: (args) =>
                    _pdfService.sharePdf(
                      args[0],
                      args.length > 1 ? args[1] : null,
                    ),
              );

              controller.addJavaScriptHandler(
                handlerName: 'printPdf',
                callback: (args) =>
                    _pdfService.printPdf(
                      context,
                      args[0],
                      args.length > 1 ? args[1] : null,
                    ),
              );

              controller.addJavaScriptHandler(
                handlerName: 'downloadPdf',
                callback: (args) =>
                    _pdfService.downloadPdf(
                      context,
                      args[0],
                      args.length > 1 ? args[1] : null,
                    ),
              );
            },
          ),
        ),
      ),
    );
  }
}
