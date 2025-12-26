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
  InAppWebViewController? controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: InAppWebView(
          initialFile: "assets/index.html",

          initialSettings: InAppWebViewSettings(
            // 🔥 ZORUNLU
            javaScriptEnabled: true,
            domStorageEnabled: true,

            // 🔥 FILE:// + PDF.JS
            allowFileAccess: true,
            allowContentAccess: true,
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,

            // 🔥 iframe + ES module
            supportMultipleWindows: true,
            useShouldOverrideUrlLoading: true,

            // 🔥 Google Fonts / Material Icons
            mixedContentMode:
                MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,

            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
          ),

          onWebViewCreated: (c) => controller = c,

          onConsoleMessage: (controller, msg) {
            debugPrint("WEB >> ${msg.message}");
          },
        ),
      ),
    );
  }
}
