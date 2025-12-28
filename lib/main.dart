import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // BU SATIRI EKLEYİN
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'viewer_page.dart';

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
      title: 'MindArt',
      // CRITICAL: SystemChrome'u sıfırla
      builder: (context, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.edgeToEdge,
            overlays: SystemUiOverlay.values,
          );
        });
        return child!;
      },
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  InAppWebViewController? webViewController;

  @override
  void initState() {
    super.initState();
    // Ana sayfada system UI tam gösterilsin
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // CRITICAL: Ana sayfada SafeArea YOK
      // HTML kendi status bar alanını yönetecek
      body: InAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(
              "file:///android_asset/flutter_assets/assets/web/index.html"),
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
          // CRITICAL: Transparent background
          transparentBackground: true,
        ),
        onWebViewCreated: (controller) {
          webViewController = controller;
        },
        onLoadStop: (controller, url) {
          // JavaScript Channel ekle - PDF açma mesajını dinle
          controller.addJavaScriptHandler(
            handlerName: 'openPdfViewer',
            callback: (args) {
              if (args.length >= 2) {
                final pdfData = args[0] as String;
                final pdfName = args[1] as String;
                
                if (pdfData.isNotEmpty && pdfName.isNotEmpty) {
                  // Viewer sayfasına geç - HER ZAMAN YENİ
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ViewerPage(
                        pdfData: pdfData,
                        pdfName: pdfName,
                      ),
                    ),
                  ).then((_) {
                    // Viewer'dan dönünce WebView'i yenile
                    if (webViewController != null) {
                      webViewController!.reload();
                    }
                  });
                }
              }
            },
          );
        },
      ),
    );
  }
}
