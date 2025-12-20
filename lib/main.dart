import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:io';
import 'package:path/path.dart';

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
                initialUrlRequest: URLRequest(
                  url: WebUri.uri(Uri.parse(
                    "file:///android_asset/flutter_assets/assets/web/index.html"
                  )),
                ),
                initialOptions: InAppWebViewGroupOptions(
                  crossPlatform: InAppWebViewOptions(
                    javaScriptEnabled: true,
                    useShouldOverrideUrlLoading: true,
                    clearCache: false,
                  ),
                  android: AndroidInAppWebViewOptions(
                    useHybridComposition: true,
                    allowFileAccess: true,
                    allowFileAccessFromFileURLs: true,
                    allowUniversalAccessFromFileURLs: true,
                  ),
                ),
                onWebViewCreated: (controller) {
                  webViewController = controller;
                  print("WebView created");
                },
                onLoadStart: (controller, url) {
                  print("Loading started: $url");
                },
                onLoadStop: (controller, url) async {
                  print("Loading stopped: $url");
                  // HTML içeriğini kontrol et
                  String? html = await controller.getHtml();
                  print("HTML length: ${html?.length ?? 0}");
                },
                onLoadError: (controller, url, code, message) {
                  print("Load error: $message");
                  print("URL: $url");
                  print("Code: $code");
                },
                onProgressChanged: (controller, progress) {
                  setState(() {
                    this.progress = progress / 100;
                  });
                },
                androidOnPermissionRequest: (controller, origin, resources) async {
                  return PermissionRequestResponse(
                    resources: resources,
                    action: PermissionRequestResponseAction.GRANT,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
