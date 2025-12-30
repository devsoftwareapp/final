import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, primarySwatch: Colors.blue),
      home: const WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});
  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> with WidgetsBindingObserver {
  InAppWebViewController? webViewController;
  bool _isViewerOpen = false;

  @override
  void initState() {
    super.initState();
    // Uygulama ayarlardan geri dönüldüğünde izni kontrol etmek için observer ekliyoruz
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Kullanıcı ayarlara gidip geri döndüğünde tetiklenir
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissionAndRefreshJS();
    }
  }

  // İzin durumuna göre JS tarafını güncelleyen yardımcı fonksiyon
  Future<void> _checkPermissionAndRefreshJS() async {
    if (webViewController == null) return;

    PermissionStatus status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) status = await Permission.storage.status;

    if (status.isGranted) {
      // İzin verildiyse: Ayar sekmesini (permissionContainer) gizle, listeyi tara ve göster
      await webViewController!.evaluateJavascript(source: """
        if(typeof scanDeviceForPDFs === 'function') {
          scanDeviceForPDFs(); 
        }
        if(document.getElementById('permissionContainer')) {
          document.getElementById('permissionContainer').style.display = 'none';
          document.getElementById('deviceList').style.display = 'grid';
        }
      """);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isViewerOpen) {
          await webViewController?.evaluateJavascript(source: "window.viewerBackPressed ? window.viewerBackPressed() : window.history.back();");
          return false;
        }
        return true;
      },
      child: Scaffold(
        body: SafeArea(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri("file:///android_asset/flutter_assets/assets/web/index.html")),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              allowFileAccess: true,
              domStorageEnabled: true,
              useHybridComposition: true,
              allowUniversalAccessFromFileURLs: true,
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;

              // OPFS ve Android Köprüsü için JS injection
              controller.addUserScript(userScript: UserScript(
                source: "window.Android = { openSettings: () => window.flutter_inappwebview.callHandler('openSettings') };",
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START
              ));

              // Ayarlara gitme handler'ı
              controller.addJavaScriptHandler(handlerName: 'openSettings', callback: (args) async {
                await openAppSettings();
              });

              // İzin kontrolü handler'ı (index.html yüklendiğinde çağrılır)
              controller.addJavaScriptHandler(handlerName: 'checkDevicePermission', callback: (args) async {
                PermissionStatus status = await Permission.manageExternalStorage.status;
                if (!status.isGranted) status = await Permission.storage.status;
                return status.isGranted;
              });

              // PDF Görüntüleme ve OPFS Kayıt (Senin sisteminle uyumlu)
              controller.addJavaScriptHandler(handlerName: 'openPdfViewer', callback: (args) {
                final String base64Data = args[0];
                final String pdfName = args[1];
                controller.evaluateJavascript(source: """
                  (async function() {
                    const root = await navigator.storage.getDirectory();
                    const pdfDir = await root.getDirectoryHandle('pdfs', { create: true });
                    const b64 = '$base64Data'.includes(',') ? '$base64Data'.split(',')[1] : '$base64Data';
                    const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
                    
                    const fileHandle = await pdfDir.getFileHandle('$pdfName', { create: true });
                    const writable = await fileHandle.createWritable();
                    await writable.write(bytes);
                    await writable.close();

                    const currentHandle = await pdfDir.getFileHandle('current.pdf', { create: true });
                    const cWritable = await currentHandle.createWritable();
                    await cWritable.write(bytes);
                    await cWritable.close();

                    sessionStorage.setItem('currentPdfName', '$pdfName');
                    sessionStorage.setItem('usingOPFS', 'true');
                    window.location.href = 'viewer.html';
                  })();
                """);
              });
            },
            onLoadStop: (controller, url) async {
              if (url.toString().contains("index.html")) {
                _isViewerOpen = false;
                _checkPermissionAndRefreshJS(); // Sayfa yüklenince izni kontrol et
              } else if (url.toString().contains("viewer.html")) {
                _isViewerOpen = true;
              }
            },
          ),
        ),
      ),
    );
  }
}
