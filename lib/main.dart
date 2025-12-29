import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'viewer_page.dart'; // Viewer sayfasının doğru import edildiğinden emin olun

void main() {
  // WebView ve Flutter bağlamını başlatıyoruz
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PDF Reader',
      theme: ThemeData(
        useMaterial3: true, 
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const WebViewPage(),
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
      // SafeArea kullanarak içeriğin çentik veya alt bar altında kalmasını önlüyoruz
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri("file:///android_asset/flutter_assets/assets/web/index.html"),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            allowFileAccess: true,
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,
            domStorageEnabled: true,
            // Ana sayfa için cache açık kalabilir ancak PDF viewer için kapatılacak
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;

            // HTML tarafındaki 'openPdfViewer' çağrısını yakalayan handler
            controller.addJavaScriptHandler(
              handlerName: 'openPdfViewer',
              callback: (args) {
                if (args.isNotEmpty) {
                  final String base64Data = args[0];
                  final String pdfName = args.length > 1 ? args[1] : "dokuman.pdf";

                  // KESİN ÇÖZÜM: UniqueKey() ekleyerek her seferinde 
                  // ViewerPage'in yeni bir kimlikle (ID) oluşturulmasını sağlıyoruz.
                  // Bu sayede WebView eski cache verilerini temizleyip yeni PDF'i açar.
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ViewerPage(
                        key: UniqueKey(), // Bu satır ikinci kez açılmama sorununu çözer
                        pdfBase64: base64Data,
                        pdfName: pdfName,
                      ),
                    ),
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
