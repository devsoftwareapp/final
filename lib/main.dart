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
      home: WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late InAppWebViewController webViewController;
  double progress = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (progress < 1.0)
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey,
                color: Colors.blue,
              ),
            Expanded(
              child: InAppWebView(
                initialFile: "assets/web/index.html",
                initialOptions: InAppWebViewGroupOptions(
                  crossPlatform: InAppWebViewOptions(
                    javaScriptEnabled: true,
                    useShouldOverrideUrlLoading: true,
                  ),
                  android: AndroidInAppWebViewOptions(
                    useHybridComposition: true,
                  ),
                ),
                onWebViewCreated: (controller) {
                  webViewController = controller;
                  print("✅ WebView created");
                },
                onLoadStart: (controller, url) {
                  print("🔄 Loading started: $url");
                },
                onLoadStop: (controller, url) async {
                  print("✅ Loading stopped: $url");
                },
                onLoadError: (controller, url, code, message) {
                  print("❌ Load error: $message");
                  print("📁 Check if assets/web/index.html exists");
                },
                onProgressChanged: (controller, progress) {
                  setState(() {
                    this.progress = progress / 100;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
