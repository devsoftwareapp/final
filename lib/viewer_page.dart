import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ViewerPage extends StatefulWidget {
  final String pdfData;
  final String pdfName;

  const ViewerPage({
    super.key,
    required this.pdfData,
    required this.pdfName,
  });

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  InAppWebViewController? _webViewController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Viewer sayfasında FULL IMMERSIVE MODE
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
  }

  @override
  void dispose() {
    // Sayfadan çıkınca system UI'ı normale döndür
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Safe area değerlerini al (HTML'ye göndermek için)
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return PopScope(
      // Android geri tuşu için
      canPop: true,
      onPopInvoked: (didPop) {
        if (!didPop) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        // CRITICAL: AppBar YOK, SafeArea YOK
        // viewer.html FULL SCREEN olacak
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(
                    "file:///android_asset/flutter_assets/assets/web/viewer.html"),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                allowFileAccess: true,
                allowContentAccess: true,
                allowFileAccessFromFileURLs: true,
                allowUniversalAccessFromFileURLs: true,
                domStorageEnabled: true,
                useHybridComposition: true,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                transparentBackground: true,
                // FULL SCREEN için
                disableVerticalScroll: true,
                disableHorizontalScroll: true,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onLoadStop: (controller, url) async {
                // viewer.html yüklendikten sonra
                await Future.delayed(const Duration(milliseconds: 500));

                // SAFE AREA değerlerini HTML'ye gönder
                final jsCode = '''
                  // Safe area değerlerini CSS'e aktar
                  document.documentElement.style.setProperty('--safe-top', '${safeTop}px');
                  document.documentElement.style.setProperty('--safe-bottom', '${safeBottom}px');
                  document.documentElement.style.setProperty('--safe-left', '0px');
                  document.documentElement.style.setProperty('--safe-right', '0px');
                  
                  // PDF verisini sessionStorage'a yaz
                  try {
                    sessionStorage.setItem('currentPdfData', '${widget.pdfData.replaceAll("'", "\\'")}');
                    sessionStorage.setItem('currentPdfName', '${widget.pdfName.replaceAll("'", "\\'")}');
                    
                    // PDF'yi yükle
                    if (typeof loadPdfIntoViewer === 'function') {
                      loadPdfIntoViewer();
                    } else {
                      setTimeout(() => {
                        if (typeof loadPdfIntoViewer === 'function') {
                          loadPdfIntoViewer();
                        }
                      }, 1000);
                    }
                  } catch(e) {
                    console.error('Error:', e);
                  }
                ''';

                try {
                  await controller.evaluateJavascript(source: jsCode);
                } catch (e) {
                  print('JavaScript error: $e');
                }

                setState(() {
                  _isLoading = false;
                });
              },
            ),

            // Loading indicator
            if (_isLoading)
              Container(
                color: Colors.black,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'PDF yükleniyor...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
