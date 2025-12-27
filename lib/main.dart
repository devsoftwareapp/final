import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'iframe_page.dart';

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
      title: 'PDF Reader Pro',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
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
      appBar: AppBar(title: const Text("Kitaplık"), centerTitle: true),
      body: InAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri("asset:///assets/index.html"),
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

          // index.html'den gelen tıklama verisini yakalar
          controller.addJavaScriptHandler(handlerName: 'openIframe', callback: (args) {
            // args[0] -> Seçilen PDF'in Base64 verisi veya ID'si
            Navigator.pushNamed(context, '/iframe', arguments: args[0]);
          });
        },
      ),
    );
  }
}
