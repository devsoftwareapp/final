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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MindArt',
      initialRoute: '/',
      routes: {
        '/': (context) => const HomePage(),
        '/viewer': (context) => const ViewerPage(),
      },
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
          onLoadStop: (controller, url) async {
            // JavaScript Channel ekle
            await controller.addJavaScriptHandler(
              handlerName: 'openPdfViewer',
              callback: (args) {
                // PDF verisi geldi, viewer sayfasına git
                final pdfData = args[0] as String?;
                final pdfName = args[1] as String?;
                
                if (pdfData != null && pdfName != null) {
                  Navigator.pushNamed(
                    context,
                    '/viewer',
                    arguments: {
                      'pdfData': pdfData,
                      'pdfName': pdfName,
                    },
                  );
                }
              },
            );
          },
        ),
      ),
    );
  }
}
