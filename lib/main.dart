import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'viewer_page.dart'; // Viewer sayfasını import ediyoruz

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
      theme: ThemeData(useMaterial3: true, primarySwatch: Colors.blue),
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
            domStorageEnabled: true,
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;

            controller.addJavaScriptHandler(
              handlerName: 'openPdfViewer',
              callback: (args) {
                final String base64Data = args[0];
                final String pdfName = args[1];

                // NAVIGATION: Verileri alıp ViewerPage'e gidiyoruz
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ViewerPage(
                      pdfBase64: base64Data,
                      pdfName: pdfName,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
