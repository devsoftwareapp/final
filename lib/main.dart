import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  // WebView ve diğer pluginlerin düzgün çalışması için gerekli
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PDF Reader',
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
      ),
      home: const WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  InAppWebViewController? webViewController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // SafeArea: Çentik ve alt bar çakışmalarını önler
      body: SafeArea(
        child: InAppWebView(
          // Yerel index.html yolun
          initialUrlRequest: URLRequest(
            url: WebUri("file:///android_asset/flutter_assets/assets/web/index.html"),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,          // JS çalıştırabilme
            allowFileAccess: true,             // Yerel dosyalara erişim
            allowFileAccessFromFileURLs: true, // Dosya içinden dosya çağırma
            allowUniversalAccessFromFileURLs: true, // Cross-origin izinleri (PDF.js için kritik)
            useHybridComposition: true,        // Android performansı için
            domStorageEnabled: true,           // sessionStorage kullanımı için gerekli
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;

            // --- KRİTİK NOKTA BURASI ---
            // index.html'deki window.flutter_inappwebview.callHandler('openPdfViewer', ...) 
            // çağrısını burada yakalıyoruz.
            controller.addJavaScriptHandler(
              handlerName: 'openPdfViewer',
              callback: (args) {
                // args[0] -> base64 string
                // args[1] -> pdf dosya adı
                final String base64Data = args[0];
                final String pdfName = args[1];

                print("PDF Açılıyor: $pdfName");

                // JavaScript tarafında veriyi set edip viewer.html'e yönlendiriyoruz
                controller.evaluateJavascript(source: """
                  sessionStorage.setItem('currentPdfData', '$base64Data');
                  sessionStorage.setItem('currentPdfName', '$pdfName');
                  window.location.href = 'viewer.html';
                """);
              },
            );
          },
          onConsoleMessage: (controller, consoleMessage) {
            // Tarayıcıdaki (index.html/viewer.html) hataları Flutter konsolunda görmek için
            print("WebView Console: ${consoleMessage.message}");
          },
          onLoadError: (controller, url, code, message) {
            print("Yükleme Hatası: $url - $message");
          },
        ),
      ),
    );
  }
}
