import 'dart:convert'; // Base64 çözmek için
import 'dart:io'; // Dosya işlemleri için
import 'dart:typed_data'; // Byte verileri için

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// Aşağıdaki paketlerin pubspec.yaml'da olduğundan emin olun:
import 'package:path_provider/path_provider.dart'; 
import 'package:share_plus/share_plus.dart'; 
import 'package:printing/printing.dart'; 

void main() {
  // WebView ve diğer pluginlerin düzgün çalışması için gerekli
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

  // Yardımcı Fonksiyon: Base64 string'i temizleyip byte'a çevirir
  Uint8List _decodeBase64(String base64String) {
    if (base64String.contains(',')) {
      base64String = base64String.split(',').last;
    }
    return base64Decode(base64String);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // SafeArea: Çentik ve alt bar çakışmalarını önler
      body: SafeArea(
        child: InAppWebView(
          // Yerel index.html yolun
          initialUrlRequest: URLRequest(
            url: WebUri("file:///android_asset/flutter_assets/assets/web/index.html"),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,          // JS çalıştırabilme
            allowFileAccess: true,             // Yerel dosyalara erişim
            allowFileAccessFromFileURLs: true, // Dosya içinden dosya çağırma
            allowUniversalAccessFromFileURLs: true, // Cross-origin izinleri (PDF.js için kritik)
            useHybridComposition: true,        // Android performansı için
            domStorageEnabled: true,           // sessionStorage kullanımı için gerekli
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;

            // ---------------------------------------------------------
            // 1. PDF GÖRÜNTÜLEYİCİ AÇMA HANDLER'I (Mevcut Olan)
            // ---------------------------------------------------------
            controller.addJavaScriptHandler(
              handlerName: 'openPdfViewer',
              callback: (args) {
                // args[0] -> base64 string
                // args[1] -> pdf dosya adı
                final String base64Data = args[0];
                final String pdfName = args[1];

                print("PDF Açılıyor: $pdfName");

                // JavaScript tarafında veriyi set edip viewer.html'e yönlendiriyoruz
                controller.evaluateJavascript(source: """
                  sessionStorage.setItem('currentPdfData', '$base64Data');
                  sessionStorage.setItem('currentPdfName', '$pdfName');
                  window.location.href = 'viewer.html';
                """);
              },
            );

            // ---------------------------------------------------------
            // 2. PAYLAŞMA HANDLER'I (YENİ)
            // ---------------------------------------------------------
            controller.addJavaScriptHandler(
              handlerName: 'sharePdf',
              callback: (args) async {
                try {
                  final String base64Data = args[0];
                  final String fileName = args[1];
                  
                  final bytes = _decodeBase64(base64Data);
                  
                  // Dosyayı geçici dizine yaz
                  final tempDir = await getTemporaryDirectory();
                  final file = File('${tempDir.path}/$fileName');
                  await file.writeAsBytes(bytes);

                  // Native paylaşım penceresini aç
                  await Share.shareXFiles([XFile(file.path)], text: fileName);
                } catch (e) {
                  print("Paylaşma Hatası: $e");
                }
              },
            );

            // ---------------------------------------------------------
            // 3. YAZDIRMA HANDLER'I (YENİ)
            // ---------------------------------------------------------
            controller.addJavaScriptHandler(
              handlerName: 'printPdf',
              callback: (args) async {
                try {
                  final String base64Data = args[0];
                  final String fileName = args[1];
                  
                  final bytes = _decodeBase64(base64Data);

                  // Printing paketi ile yazdır
                  await Printing.layoutPdf(
                    onLayout: (format) async => bytes,
                    name: fileName,
                  );
                } catch (e) {
                  print("Yazdırma Hatası: $e");
                }
              },
            );

            // ---------------------------------------------------------
            // 4. İNDİRME / KAYDETME HANDLER'I (YENİ)
            // ---------------------------------------------------------
            controller.addJavaScriptHandler(
              handlerName: 'downloadPdf',
              callback: (args) async {
                try {
                  final String base64Data = args[0];
                  final String fileName = args[1];
                  
                  final bytes = _decodeBase64(base64Data);

                  // Uygulama belgeler dizinine kaydet (Güvenli Alan)
                  final appDocDir = await getApplicationDocumentsDirectory();
                  final file = File('${appDocDir.path}/$fileName');
                  await file.writeAsBytes(bytes);

                  // Kullanıcıya bilgi ver
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Dosya kaydedildi: ${file.path}"),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (e) {
                  print("Kaydetme Hatası: $e");
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Dosya kaydedilemedi!")),
                    );
                  }
                }
              },
            );
          },
          onConsoleMessage: (controller, consoleMessage) {
            // Tarayıcıdaki (index.html/viewer.html) hataları Flutter konsolunda görmek için
            print("WebView Console: ${consoleMessage.message}");
          },
          onLoadError: (controller, url, code, message) {
            print("Yükleme Hatası: $url - $message");
          },
        ),
      ),
    );
  }
}
