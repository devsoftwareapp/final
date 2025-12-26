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
  InAppWebViewController? webViewController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: InAppWebView(
          initialFile: 'assets/index.html',

          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            allowFileAccess: true,
            allowContentAccess: true,
            useShouldOverrideUrlLoading: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
          ),

          onWebViewCreated: (controller) {
            webViewController = controller;
          },

          onConsoleMessage: (controller, consoleMessage) {
            debugPrint(
              'WEB: ${consoleMessage.message}',
            );
          },
        ),
      ),
    );
  }
}
