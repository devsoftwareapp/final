import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PdfWebView(),
    );
  }
}

class PdfWebView extends StatefulWidget {
  const PdfWebView({super.key});

  @override
  State<PdfWebView> createState() => _PdfWebViewState();
}

class _PdfWebViewState extends State<PdfWebView> {
  late InAppWebViewController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri("http://localhost/index.html"),
          ),

          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            allowFileAccess: true,
            allowContentAccess: true,
            allowUniversalAccessFromFileURLs: true,
            allowFileAccessFromFileURLs: true,
            mediaPlaybackRequiresUserGesture: false,
            useWideViewPort: true,
            loadWithOverviewMode: true,
            supportZoom: true,
          ),

          initialAssetLoader: InAppWebViewAssetLoader(
            domain: "localhost",
            pathHandlers: [
              InAppWebViewAssetLoaderAssetsPathHandler(
                path: "/",
              ),
            ],
          ),

          onWebViewCreated: (c) {
            controller = c;
          },

          onConsoleMessage: (c, msg) {
            debugPrint("WEB: ${msg.message}");
          },
        ),
      ),
    );
  }
}
