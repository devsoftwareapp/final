import 'package:flutter/material.dart';
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: InAppWebView(
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
                    // Viewer sayfasına geç
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ViewerPage(
                          pdfData: pdfData,
                          pdfName: pdfName,
                        ),
                      ),
                    );
                  }
                }
              },
            );
            
            // Android'den döndüğünde tarama mesajı
            controller.addJavaScriptHandler(
              handlerName: 'onAndroidResume',
              callback: (args) {
                // Android'den dönüşte tarama yap
                controller.evaluateJavascript(source: '''
                  if (typeof onAndroidResume === 'function') {
                    onAndroidResume();
                  }
                ''');
              },
            );
          },
        ),
      ),
    );
  }
}
