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
  double progress = 0;
  String loadingStatus = "Yükleniyor...";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            if (progress < 1.0)
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey,
                color: Colors.blue,
              ),
            
            // Status text
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                loadingStatus,
                style: const TextStyle(fontSize: 14, color: Colors.blue),
              ),
            ),
            
            // WebView
            Expanded(
              child: InAppWebView(
                // V6.1.5'te BU şekilde asset yükle
                initialUrlRequest: URLRequest(
                  url: WebUri(
                    "file:///android_asset/flutter_assets/assets/web/index.html"
                  ),
                ),
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
                  print("✅ WebView oluşturuldu");
                },
                onLoadStart: (controller, url) {
                  print("🔄 Yükleniyor: $url");
                  setState(() {
                    loadingStatus = "Sayfa yükleniyor...";
                  });
                },
                onLoadStop: (controller, url) {
                  print("✅ Yüklendi: $url");
                  setState(() {
                    loadingStatus = "Sayfa hazır!";
                  });
                },
                onLoadError: (controller, url, code, message) {
                  print("❌ Hata: $message");
                  print("📁 URL: $url");
                  setState(() {
                    loadingStatus = "Hata: $message";
                  });
                },
                onProgressChanged: (controller, progress) {
                  setState(() {
                    this.progress = progress / 100;
                  });
                },
                onConsoleMessage: (controller, consoleMessage) {
                  // JavaScript console mesajlarını gör
                  print("📝 Console: ${consoleMessage.message}");
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
