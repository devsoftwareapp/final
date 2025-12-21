import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

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

class _WebViewPageState extends State<WebViewPage> with WidgetsBindingObserver {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;

  @override
  void initState() {
    super.initState();
    // Observer'ı ekleyin
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // Observer'ı kaldırın
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Uygulama yaşam döngüsü değiştiğinde
    if (state == AppLifecycleState.resumed) {
      // Uygulama tekrar açıldığında WebView'e mesaj gönder
      webViewController?.evaluateJavascript(source: '''
        if (typeof onAndroidResume === 'function') {
          onAndroidResume();
        }
      ''');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: InAppWebView(
          key: webViewKey,
          initialFile: "assets/web/index.html",
          initialOptions: InAppWebViewGroupOptions(
            crossPlatform: InAppWebViewOptions(
              javaScriptEnabled: true,
              useShouldOverrideUrlLoading: true,
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
            ),
            android: AndroidInAppWebViewOptions(
              useHybridComposition: true,
              allowContentAccess: true,
              allowFileAccess: true,
            ),
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;
            
            // JavaScript handler'larını ekle
            controller.addJavaScriptHandler(
              handlerName: 'openSettings',
              callback: (args) {
                _openAndroidSettings();
              },
            );
            
            controller.addJavaScriptHandler(
              handlerName: 'androidBackPressed',
              callback: (args) {
                return _handleAndroidBack();
              },
            );
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final uri = navigationAction.request.url;
            
            if (uri != null) {
              // "settings://all_files" özel URL'sini yakala
              if (uri.toString() == 'settings://all_files') {
                _openAndroidSettings();
                return NavigationActionPolicy.CANCEL;
              }
              
              // Diğer URL'leri normal şekilde işle
              if (uri.scheme == 'http' || uri.scheme == 'https') {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                return NavigationActionPolicy.CANCEL;
              }
            }
            
            return NavigationActionPolicy.ALLOW;
          },
          onLoadStop: (controller, url) async {
            // Sayfa yüklendiğinde JavaScript'e mesaj gönder
            controller.evaluateJavascript(source: '''
              if (typeof window.flutterReady === 'function') {
                window.flutterReady();
              }
            ''');
          },
        ),
      ),
    );
  }

  // Android ayarlarını aç
  Future<void> _openAndroidSettings() async {
    try {
      // Android 11+ için MANAGE_EXTERNAL_STORAGE ayarlarını aç
      if (Platform.isAndroid) {
        // Önce uygulama ayarlarını açmayı dene
        const appSettings = 'package:${'your.package.name'}'; // PAKET ADINI GÜNCELLE
        
        // Android 11+ için özel izin sayfası
        final uri = Uri.parse('android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION');
        
        // Önce genel ayarları açmayı dene
        if (await canLaunchUrl(Uri.parse(appSettings))) {
          await launchUrl(Uri.parse(appSettings), mode: LaunchMode.externalApplication);
        } else if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          // En son çare olarak genel ayarlar
          const settingsUri = 'app-settings:';
          if (await canLaunchUrl(Uri.parse(settingsUri))) {
            await launchUrl(Uri.parse(settingsUri), mode: LaunchMode.externalApplication);
          } else {
            // Hiçbiri çalışmazsa toast göster
            _showSnackBar('Ayarlar açılamadı. Manuel olarak Ayarlar > Uygulamalar > [Uygulama Adı] > İzinler bölümünden izin verin.');
          }
        }
      }
    } catch (e) {
      print('Error opening settings: $e');
      _showSnackBar('Ayarlar açılırken hata oluştu: $e');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Android geri tuşu işleme
  dynamic _handleAndroidBack() {
    webViewController?.evaluateJavascript(source: '''
      if (typeof androidBackPressed === 'function') {
        var result = androidBackPressed();
        result;
      } else {
        false;
      }
    ''').then((value) {
      if (value == 'exit_check') {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Çıkış'),
              content: const Text('Uygulamadan çıkmak istediğinize emin misiniz?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                TextButton(
                  onPressed: () => exit(0),
                  child: const Text('Çık'),
                ),
              ],
            ),
          );
        }
      }
    });
    
    return null;
  }
}
