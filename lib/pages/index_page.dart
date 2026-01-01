import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/pdf_service.dart';
import '../services/permission_service.dart';

class IndexPage extends StatefulWidget {
  const IndexPage({super.key});

  @override
  State<IndexPage> createState() => _IndexPageState();
}

class _IndexPageState extends State<IndexPage>
    with WidgetsBindingObserver {
  InAppWebViewController? webViewController;
  DateTime? _lastBackPressTime;

  late final PDFService _pdfService;
  late final PermissionService _permissionService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pdfService = PDFService();
    _permissionService = PermissionService();

    debugPrint("🏠 Index Page başlatıldı");
  }

  @override
  void dispose() {
    _pdfService.cleanupTempFiles();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("📱 Index: Uygulama geri döndü");
      _checkAndUpdatePermissionStatus();
    }
  }

  Future<void> _checkAndUpdatePermissionStatus() async {
    if (webViewController == null) return;

    await webViewController!.evaluateJavascript(source: '''
      (function () {
        console.log("📱 Index: İzin durumu güncelleniyor");
        if (typeof onAndroidResume === 'function') {
          onAndroidResume();
        }
        if (typeof scanDeviceForPDFs === 'function') {
          setTimeout(() => scanDeviceForPDFs(), 500);
        }
      })();
    ''');
  }

  Future<void> _navigateToViewer(String pdfName) async {
    debugPrint("🔄 Viewer'a geçiş yapılıyor: $pdfName");

    if (!mounted) return;

    await Navigator.pushNamed(context, '/viewer');

    debugPrint("🔙 Viewer'dan geri dönüldü, index yenileniyor");
    _checkAndUpdatePermissionStatus();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (webViewController == null) return true;

        final result = await webViewController!.evaluateJavascript(
          source:
              "window.androidBackPressed ? window.androidBackPressed() : false;",
        );

        if (result == 'exit_check') {
          final now = DateTime.now();

          if (_lastBackPressTime == null ||
              now.difference(_lastBackPressTime!) >
                  const Duration(seconds: 2)) {
            _lastBackPressTime = now;

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Çıkmak için tekrar basın'),
                  duration: Duration(seconds: 2),
                  backgroundColor: Colors.black87,
                ),
              );
            }
            return false;
          }
          return true;
        }

        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(
                "file:///android_asset/flutter_assets/assets/web/index.html",
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
            ),
            initialUserScripts:
                UnmodifiableListView<UserScript>([
              UserScript(
                source: '''
                  console.log("🏠 Index Page - IndexedDB Mode");
                  window.activeBlobUrls = window.activeBlobUrls || [];

                  window.navigateToViewer = function (pdfName) {
                    console.log("📄 Viewer'a geçiliyor:", pdfName);
                    window.flutter_inappwebview
                      .callHandler('navigateToViewer', pdfName);
                  };
                ''',
                injectionTime:
                    UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            onWebViewCreated: (controller) {
              webViewController = controller;
              debugPrint("🌐 Index WebView oluşturuldu");

              controller.addJavaScriptHandler(
                handlerName: 'navigateToViewer',
                callback: (args) async {
                  final pdfName =
                      args.isNotEmpty ? args[0] : "belge.pdf";
                  await _navigateToViewer(pdfName);
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'checkStoragePermission',
                callback: (_) =>
                    _permissionService.checkStoragePermission(),
              );

              controller.addJavaScriptHandler(
                handlerName: 'requestStoragePermission',
                callback: (_) =>
                    _permissionService.requestStoragePermission(),
              );

              controller.addJavaScriptHandler(
                handlerName: 'listPdfFiles',
                callback: (_) => _pdfService.listPdfFiles(),
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
                handlerName: 'openSettingsForPermission',
                callback: (_) =>
                    _permissionService.openAppSettings(),
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
            onLoadStop: (controller, _) async {
              await _checkAndUpdatePermissionStatus();

              await controller.evaluateJavascript(source: '''
                (async function () {
                  try {
                    if (typeof pdfManager !== 'undefined' &&
                        pdfManager.init) {
                      await pdfManager.init();
                      console.log("✅ Index: IndexedDB başlatıldı");
                    }
                  } catch (e) {
                    console.error(
                      "❌ Index: IndexedDB hatası:",
                      e
                    );
                  }
                })();
              ''');
            },
            onConsoleMessage: (_, message) {
              debugPrint("🏠 INDEX JS: ${message.message}");
            },
          ),
        ),
      ),
    );
  }
}
