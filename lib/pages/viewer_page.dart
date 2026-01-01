import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/pdf_service.dart';
import 'dart:collection';

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  InAppWebViewController? webViewController;
  late PDFService _pdfService;

  @override
  void initState() {
    super.initState();
    _pdfService = PDFService();
    debugPrint("📄 Viewer Page başlatıldı");
  }

  @override
  void dispose() {
    _cleanupViewer();
    super.dispose();
  }

  Future<void> _cleanupViewer() async {
    debugPrint("🗑️ Viewer temizleniyor...");
    
    if (webViewController != null) {
      await webViewController!.evaluateJavascript(source: """
        (async function() {
          try {
            if (typeof viewerPdfManager !== 'undefined' && viewerPdfManager.cleanup) {
              await viewerPdfManager.cleanup();
            }
            sessionStorage.clear();
            console.log("✅ Viewer temizlendi");
          } catch (e) {
            console.error("❌ Viewer temizleme hatası:", e);
          }
        })();
      """);
    }
    
    await _pdfService.cleanupTempFiles();
  }

  Future<void> _goBack() async {
    await _cleanupViewer();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _goBack();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri("file:///android_asset/flutter_assets/assets/web/viewer.html"),
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
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: """
                  console.log("📄 Viewer Page - IndexedDB Mode");
                  window.activeBlobUrls = window.activeBlobUrls || [];
                  
                  window.goBackToIndex = function() {
                    window.flutter_inappwebview.callHandler('goBackToIndex');
                  };
                """,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            onWebViewCreated: (controller) {
              webViewController = controller;
              debugPrint("🌐 Viewer WebView oluşturuldu");

              controller.addJavaScriptHandler(
                handlerName: 'goBackToIndex',
                callback: (args) async {
                  await _goBack();
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'getPdfPath',
                callback: (args) async {
                  String sourcePath = args[0];
                  String fileName = args.length > 1 ? args[1] : sourcePath.split('/').last;
                  return await _pdfService.getPdfPath(sourcePath, fileName);
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'readPdfFile',
                callback: (args) async {
                  return await _pdfService.readPdfFile(args[0]);
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'sharePdf',
                callback: (args) async {
                  await _pdfService.sharePdf(args[0], args.length > 1 ? args[1] : null);
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'printPdf',
                callback: (args) async {
                  await _pdfService.printPdf(context, args[0], args.length > 1 ? args[1] : null);
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'downloadPdf',
                callback: (args) async {
                  await _pdfService.downloadPdf(context, args[0], args.length > 1 ? args[1] : null);
                },
              );
            },
            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(source: """
                (async function() {
                  try {
                    if (typeof viewerPdfManager !== 'undefined' && viewerPdfManager.init) {
                      await viewerPdfManager.init();
                      console.log("✅ Viewer: IndexedDB başlatıldı");
                      
                      if (typeof loadPdfIntoViewer === 'function') {
                        await loadPdfIntoViewer();
                      }
                    }
                  } catch (e) {
                    console.error("❌ Viewer: IndexedDB hatası:", e);
                  }
                })();
              """);
            },
            onConsoleMessage: (controller, consoleMessage) {
              debugPrint("📄 VIEWER JS: ${consoleMessage.message}");
            },
          ),
        ),
      ),
    );
  }
}
