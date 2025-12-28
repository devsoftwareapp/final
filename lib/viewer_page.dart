import 'package:flutter/material.dart';
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

  // PDF verisini güvenli hale getir
  String _encodePdfData() {
    return widget.pdfData
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final encodedPdfData = _encodePdfData();
    final encodedPdfName = widget.pdfName
        .replaceAll("'", r"\'")
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ');

    return Scaffold(
      // AppBar YOK - viewer.html kendi toolbar'ını kullanacak
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
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
            },
            onLoadStop: (controller, url) async {
              // viewer.html yüklendikten sonra PDF verisini gönder
              await Future.delayed(const Duration(milliseconds: 300));

              // PDF verisini sessionStorage'a yazdıran JavaScript kodu
              final jsCode = '''
                try {
                  // Önce mevcut datayı temizle
                  sessionStorage.removeItem('currentPdfData');
                  sessionStorage.removeItem('currentPdfName');
                  
                  // Yeni datayı ekle (güvenli string)
                  sessionStorage.setItem('currentPdfData', '$encodedPdfData');
                  sessionStorage.setItem('currentPdfName', '$encodedPdfName');
                  
                  console.log('PDF data set in sessionStorage');
                  
                  // PDF'yi yüklemeyi dene
                  if (typeof loadPdfIntoViewer === 'function') {
                    loadPdfIntoViewer();
                  } else {
                    console.warn('loadPdfIntoViewer function not found, waiting...');
                    // 1 saniye bekle ve tekrar dene
                    setTimeout(function() {
                      if (typeof loadPdfIntoViewer === 'function') {
                        loadPdfIntoViewer();
                      } else {
                        console.error('loadPdfIntoViewer still not found');
                        // Alternatif: direkt PDFViewerApplication kullan
                        if (typeof PDFViewerApplication !== 'undefined' && PDFViewerApplication.open) {
                          PDFViewerApplication.open({ 
                            url: sessionStorage.getItem('currentPdfData'),
                            originalUrl: sessionStorage.getItem('currentPdfName')
                          });
                        }
                      }
                    }, 1000);
                  }
                } catch(e) {
                  console.error('Error setting PDF data:', e);
                  // Hata durumunda fallback
                  try {
                    if (typeof PDFViewerApplication !== 'undefined' && PDFViewerApplication.open) {
                      PDFViewerApplication.open({ 
                        url: '$encodedPdfData',
                        originalUrl: '$encodedPdfName'
                      });
                    }
                  } catch(e2) {
                    console.error('Fallback also failed:', e2);
                  }
                }
              ''';

              try {
                await controller.evaluateJavascript(source: jsCode);
              } catch (e) {
                print('JavaScript evaluation error: $e');
              }

              // Yükleme tamamlandı
              setState(() {
                _isLoading = false;
              });
            },
            onLoadError: (controller, url, code, message) {
              print('WebView load error: $message');
              setState(() {
                _isLoading = false;
              });
            },
          ),

          // Sadece yükleme göstergesi
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.7),
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
    );
  }
}
