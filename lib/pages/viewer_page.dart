import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/pdf_service.dart';
import 'dart:collection'; // <--- KRİTİK EKSİK BUYDU: UnmodifiableListView için gerekli
import 'dart:io';

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  InAppWebViewController? webViewController;
  late PDFService _pdfService;
  bool _isLoading = true;
  String _loadingMessage = 'PDF yükleniyor...';

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

  // ==================== VIEWER TEMİZLEME ====================
  Future<void> _cleanupViewer() async {
    debugPrint("🗑️ Viewer temizleniyor...");
    
    if (webViewController != null) {
      try {
        await webViewController!.evaluateJavascript(source: """
          (async function() {
            try {
              if (typeof viewerPdfManager !== 'undefined' && viewerPdfManager.cleanup) {
                await viewerPdfManager.cleanup();
              }
              sessionStorage.clear();
              localStorage.clear();
              if (typeof PDFViewerApplication !== 'undefined' && PDFViewerApplication.pdfDocument) {
                await PDFViewerApplication.pdfDocument.destroy();
              }
              return true;
            } catch (e) {
              return false;
            }
          })();
        """);
      } catch (e) {
        debugPrint("⚠️ Cleanup hatası: $e");
      }
    }
    await _pdfService.cleanupTempFiles();
  }

  Future<void> _goBack() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadingMessage = 'Kapatılıyor...';
      });
    }
    await _cleanupViewer();
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Widget _buildLoadingIndicator() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
              strokeWidth: 3,
            ),
            const SizedBox(height: 24),
            Text(_loadingMessage, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Modern Flutter versiyonları için PopScope kullanımı (WillPopScope yerine)
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _goBack();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri("file:///android_asset/flutter_assets/assets/web/viewer.html"),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  allowFileAccess: true,
                  allowFileAccessFromFileURLs: true,
                  allowUniversalAccessFromFileURLs: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  useHybridComposition: true,
                  hardwareAcceleration: true,
                ),
                // BURASI: Hata alınan kısım düzeltildi (dart:collection import edildi)
                initialUserScripts: UnmodifiableListView<UserScript>([
                  UserScript(
                    source: """
                      window.goBackToIndex = function() {
                        window.flutter_inappwebview.callHandler('goBackToIndex');
                      };
                      console.log("✅ Viewer scripts injected");
                    """,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  ),
                ]),
                onWebViewCreated: (controller) {
                  webViewController = controller;
                  
                  // Handler tanımlamaları
                  controller.addJavaScriptHandler(
                    handlerName: 'goBackToIndex',
                    callback: (args) async => await _goBack(),
                  );

                  controller.addJavaScriptHandler(
                    handlerName: 'readPdfFile',
                    callback: (args) async {
                      return await _pdfService.readPdfFile(args[0]);
                    },
                  );

                  controller.addJavaScriptHandler(
                    handlerName: 'getPdfPath',
                    callback: (args) async {
                      return await _pdfService.getPdfPath(args[0], args.length > 1 ? args[1] : null);
                    },
                  );
                },
                onLoadStart: (controller, url) {
                  if (mounted) setState(() => _isLoading = true);
                },
                onLoadStop: (controller, url) async {
                  await controller.evaluateJavascript(source: """
                    if (typeof viewerPdfManager !== 'undefined') {
                      viewerPdfManager.init().then(() => {
                        if (typeof loadPdfIntoViewer === 'function') loadPdfIntoViewer();
                      });
                    }
                  """);
                  if (mounted) setState(() => _isLoading = false);
                },
                onProgressChanged: (controller, progress) {
                  if (mounted && progress < 100) {
                    setState(() => _loadingMessage = 'Yükleniyor... %$progress');
                  }
                },
              ),
              if (_isLoading) _buildLoadingIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
