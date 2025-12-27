import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class IframePage extends StatefulWidget {
  const IframePage({super.key});

  @override
  State<IframePage> createState() => _IframePageState();
}

class _IframePageState extends State<IframePage> {
  InAppWebViewController? _controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(
              "file:///android_asset/flutter_assets/assets/iframe.html",
            ),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,

            // LOCAL FILE + FONT + PDF.JS için ZORUNLU
            allowFileAccess: true,
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,

            // sessionStorage için
            domStorageEnabled: true,

            // Android rendering stabilitesi
            useHybridComposition: true,

            // UX
            supportZoom: true,
            mediaPlaybackRequiresUserGesture: false,
          ),
          onWebViewCreated: (controller) {
            _controller = controller;
          },
        ),
      ),
    );
  }
}
