import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'iframe_page.dart'; // Yeni dosyayı import ediyoruz

void main() {
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
      // Sayfa geçişleri için route tanımlayabilirsin
      home: const WebViewPage(),
      routes: {
        '/iframe': (context) => const IframePage(),
      },
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
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri("file:///android_asset/flutter_assets/assets/web/index.html"),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            allowFileAccess: true,
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,
            useHybridComposition: true,
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;

            // ÖNEMLİ: index.html'den bir PDF tıklandığında 
            // IframePage'e gitmesi için bir handler ekleyebilirsin:
            controller.addJavaScriptHandler(handlerName: 'openIframe', callback: (args) {
              Navigator.pushNamed(context, '/iframe');
            });
          },
        ),
      ),
    );
  }
}
