import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/services.dart' show rootBundle;

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
  bool isLoading = true;

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
                // v6.1.5'te bu şekilde asset dosyası yükleyebilirsin
                initialUrlRequest: URLRequest(
                  url: WebUri.uri(
                    Uri.parse("file:///android_asset/flutter_assets/assets/web/index.html")
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
                },
                onLoadStop: (controller, url) {
                  print("✅ Yüklendi: $url");
                },
                onLoadError: (controller, url, code, message) {
                  print("❌ Hata: $message - $url");
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
