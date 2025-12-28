import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  late final Map<String, dynamic> _args;
  InAppWebViewController? _webViewController;
  bool _isLoading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    final pdfData = _args['pdfData'] as String;
    final pdfName = _args['pdfName'] as String;

    return Scaffold(
      appBar: AppBar(
        title: Text(pdfName),
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
            onLoadStop: (controller, url) async {
              // viewer.html yüklendikten sonra PDF verisini gönder
              await Future.delayed(const Duration(milliseconds: 500));
              
              // PDF verisini sessionStorage'a yazdıran JavaScript kodu
              final jsCode = """
                try {
                  sessionStorage.setItem('currentPdfData', '$pdfData');
                  sessionStorage.setItem('currentPdfName', '$pdfName');
                  console.log('PDF data set in sessionStorage');
                  
                  // PDF'yi yükle
                  if (window.loadPdfIntoViewer) {
                    window.loadPdfIntoViewer();
                  }
                } catch(e) {
                  console.error('Error setting PDF data:', e);
                }
              """;
              
              await controller.evaluateJavascript(source: jsCode);
              setState(() => _isLoading = false);
            },
          ),
          
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
