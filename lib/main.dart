import 'dart:io'; // exit(0) için eklendi
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

class _WebViewPageState extends State<WebViewPage> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;

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
            ),
            android: AndroidInAppWebViewOptions(
              useHybridComposition: true,
            ),
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;
          },
          onConsoleMessage: (controller, consoleMessage) {
            print("Console Message: ${consoleMessage.message}");
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final uri = navigationAction.request.url;
            
            if (uri != null) {
              // "settings://all_files" özel URL'sini yakala
              if (uri.toString() == 'settings://all_files') {
                // Android ayarlarını aç
                _openAndroidSettings();
                return NavigationActionPolicy.CANCEL;
              }
              
              // Diğer URL'leri normal şekilde işle
              if (uri.scheme == 'http' || uri.scheme == 'https') {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
                return NavigationActionPolicy.CANCEL;
              }
            }
            
            return NavigationActionPolicy.ALLOW;
          },
          // Android geri tuşu desteği için
          onLoadStop: (controller, url) async {
            // JavaScript kanalı oluştur
            controller.addJavaScriptHandler(
              handlerName: 'openSettings',
              callback: (args) {
                _openAndroidSettings();
              },
            );
            
            // Android back button handler
            controller.addJavaScriptHandler(
              handlerName: 'androidBackPressed',
              callback: (args) {
                // Geri tuşu işlemi
                return _handleAndroidBack();
              },
            );
          },
        ),
      ),
    );
  }

  // Android ayarlarını aç
  Future<void> _openAndroidSettings() async {
    try {
      // Android'in dosya erişim izni ayarlarını aç
      const url = 'package:com.android.settings';
      final uri = Uri(scheme: 'android.settings', 
                     host: 'application_details', 
                     queryParameters: {'package': 'com.android.settings'});
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Alternatif olarak genel ayarları aç
        const settingsUri = 'app-settings:';
        if (await canLaunchUrl(Uri.parse(settingsUri))) {
          await launchUrl(Uri.parse(settingsUri), mode: LaunchMode.externalApplication);
        } else {
          // En son çare olarak uygulama ayarlarını aç
          const appSettings = 'package:${'your.package.name'}'; // Buraya gerçek paket adınızı ekleyin
          if (await canLaunchUrl(Uri.parse(appSettings))) {
            await launchUrl(Uri.parse(appSettings), mode: LaunchMode.externalApplication);
          }
        }
      }
    } catch (e) {
      print('Error opening settings: $e');
      // Hata durumunda kullanıcıya mesaj göster
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ayarlar açılamadı. Lütfen manuel olarak Ayarlar > Uygulamalar bölümünden izin verin.'),
          ),
        );
      }
    }
  }

  // Android geri tuşu işleme
  dynamic _handleAndroidBack() {
    // JavaScript'e geri tuşu durumunu kontrol et
    webViewController?.evaluateJavascript(source: '''
      if (typeof androidBackPressed === 'function') {
        var result = androidBackPressed();
        result;
      } else {
        false;
      }
    ''').then((value) {
      if (value == 'exit_check') {
        // Çıkış yap
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
