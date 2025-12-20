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

class WebViewPage extends StatelessWidget {
  const WebViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ❌ AppBar kaldırıldı
      body: SafeArea(
        // ✅ Status bar ve navigation bar korunur
        child: InAppWebView(
          initialFile: "assets/web/index.html",
          initialOptions: InAppWebViewGroupOptions(
            crossPlatform: InAppWebViewOptions(
              javaScriptEnabled: true,
            ),
            android: AndroidInAppWebViewOptions(
              useHybridComposition: true,
            ),
          ),
        ),
      ),
    );
  }
}
