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
          /// 🚀 SADECE asset üzerinden aç
          initialFile: 'assets/index.html',

          /// 🔥 TÜM ERİŞİMLER AÇIK
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,

            allowFileAccess: true,
            allowContentAccess: true,

            /// 🔑 ES MODULE + PDF.js için ZORUNLU
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,

            /// 🌐 TÜM HTTP/HTTPS İÇERİKLER
            mixedContentMode:
                MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,

            /// 🌍 iframe + dış kaynaklar
            useShouldOverrideUrlLoading: true,
            allowsInlineMediaPlayback: true,
            mediaPlaybackRequiresUserGesture: false,

            /// 🔓 Google Fonts / Material Icons
            loadsImagesAutomatically: true,
            blockNetworkImage: false,
            blockNetworkLoads: false,

            /// 🔍 UX & stabilite
            supportZoom: true,
            transparentBackground: false,

            /// ⚠️ Debug için (istersen kapatılır)
            clearCache: false,
            cacheEnabled: true,
          ),

          onWebViewCreated: (controller) {
            webViewController = controller;
          },

          /// 🔍 JS console → Flutter log
          onConsoleMessage: (controller, consoleMessage) {
            debugPrint('WEB: ${consoleMessage.message}');
          },

          /// 🔍 Yükleme hataları
          onLoadError: (controller, url, code, message) {
            debugPrint('LOAD ERROR: $code $message');
          },

          onLoadHttpError: (controller, url, statusCode, description) {
            debugPrint('HTTP ERROR: $statusCode $description');
          },
        ),
      ),
    );
  }
}
