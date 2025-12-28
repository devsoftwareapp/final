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
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    // URL encode yap (özel karakterler için)
    _encodePdfData();
  }

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
      appBar: AppBar(
        title: Text(
          widget.pdfName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
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
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
            },
            onLoadStart: (controller, url) {
              setState(() {
                _isLoading = true;
                _progress = 0;
              });
            },
            onProgressChanged: (controller, progress) {
              setState(() {
                _progress = progress / 100;
              });
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
                  
                  console.log('PDF data set in sessionStorage for: $encodedPdfName');
                  
                  // PDF'yi yüklemeyi dene
                  if (typeof loadPdfIntoViewer === 'function') {
                    console.log('Calling loadPdfIntoViewer()');
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
              await Future.delayed(const Duration(milliseconds: 500));
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
          
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _progress,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'PDF yükleniyor...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                    if (_progress > 0)
                      Text(
                        '%${(_progress * 100).toInt()}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
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
