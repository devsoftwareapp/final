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
  String status = "Başlatılıyor...";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("PDF Reader Test"),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // Progress bar
          if (progress < 1.0)
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey,
              color: Colors.blue,
            ),
          
          // Status
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              status,
              style: TextStyle(
                color: status.contains("Hata") ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          // WebView
          Expanded(
            child: InAppWebView(
              // ASSET DOSYASINI YÜKLE
              initialUrlRequest: URLRequest(
                url: WebUri(
                  "file:///android_asset/flutter_assets/assets/index.html"
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
                print("✅ WebView created");
                setState(() {
                  status = "WebView hazır";
                });
              },
              onLoadStart: (controller, url) {
                print("🔄 Loading: $url");
                setState(() {
                  status = "Yükleniyor...";
                });
              },
              onLoadStop: (controller, url) {
                print("✅ Loaded: $url");
                setState(() {
                  status = "Yüklendi!";
                });
              },
              onLoadError: (controller, url, code, message) {
                print("❌ Error: $message (Code: $code)");
                print("🔍 Trying alternative paths...");
                setState(() {
                  status = "Hata: $message - Alternatif deneniyor...";
                });
                
                // Alternatif yol dene
                Future.delayed(const Duration(seconds: 2), () {
                  controller.loadUrl(
                    urlRequest: URLRequest(
                      url: WebUri(
                        "https://raw.githubusercontent.com/your-repo/test/main/assets/index.html"
                      ),
                    ),
                  );
                });
              },
              onProgressChanged: (controller, progress) {
                setState(() {
                  this.progress = progress / 100;
                });
              },
              onConsoleMessage: (controller, consoleMessage) {
                print("📝 JS Console: ${consoleMessage.message}");
              },
            ),
          ),
          
          // Refresh button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  status = "Yeniden yükleniyor...";
                  progress = 0;
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text("Yenile"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
