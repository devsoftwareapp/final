import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'iframe_page.dart';

void main() {
  // WebView ve Flutter bağlamını başlatmak için gerekli
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PDF Kitaplığı',
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
      ),
      // Ana sayfa (Kütüphane)
      home: const WebViewPage(),
      // Rotalar
      routes: {
        '/iframe': (context) => const IframePage(),
      },
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  InAppWebViewController? webViewController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("PDF Kitaplığı"),
        centerTitle: true,
      ),
      body: SafeArea(
        child: InAppWebView(
          // Android için en kesin çözüm olan dosya yolu:
          initialUrlRequest: URLRequest(
            url: WebUri("file:///android_asset/flutter_assets/assets/index.html"),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true, // JS çalışmalı
            allowFileAccess: true, // Yerel dosyalara erişim
            allowFileAccessFromFileURLs: true, 
            allowUniversalAccessFromFileURLs: true,
            useHybridComposition: true, // Performans için
            domStorageEnabled: true, // Veri saklama (index.html tarafı için)
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;

            // index.html içindeki JavaScript 'openIframe' handler'ını dinliyoruz
            controller.addJavaScriptHandler(
              handlerName: 'openIframe',
              callback: (args) {
                // index.html'den gelen PDF verisini al ve iframe sayfasına git
                if (args.isNotEmpty) {
                  Navigator.pushNamed(
                    context, 
                    '/iframe', 
                    arguments: args[0], // PDF Base64 verisi burada iletilir
                  );
                }
              },
            );
          },
          onLoadError: (controller, url, code, message) {
            debugPrint("Yükleme Hatası: $message (Kod: $code)");
            // Eğer hala hata verirse kullanıcıya görsel bir feedback verelim
            if (code == -10) { // ERR_UNKNOWN_URL_SCHEME veya dosya bulunamadı hatası
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Dosya yolu hatası! Lütfen assets klasörünü kontrol edin.")),
              );
            }
          },
        ),
      ),
    );
  }
}
