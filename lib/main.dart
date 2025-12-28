import 'dart:convert'; // Base64 çözmek için
import 'dart:io'; // Dosya işlemleri için
import 'dart:typed_data'; // Byte verileri için

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// Paketlerin pubspec.yaml'da olduğundan emin olun
import 'package:path_provider/path_provider.dart'; 
import 'package:share_plus/share_plus.dart'; 
import 'package:printing/printing.dart'; 

void main() {
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
            useHybridComposition: true,
            domStorageEnabled: true,
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;

            // 1. PDF GÖRÜNTÜLEYİCİ AÇMA
            controller.addJavaScriptHandler(
              handlerName: 'openPdfViewer',
              callback: (args) {
                final String base64Data = args[0];
                final String pdfName = args[1];
                controller.evaluateJavascript(source: """
                  sessionStorage.setItem('currentPdfData', '$base64Data');
                  sessionStorage.setItem('currentPdfName', '$pdfName');
                  window.location.href = 'viewer.html';
                """);
              },
            );

            // 2. PAYLAŞMA
            controller.addJavaScriptHandler(
              handlerName: 'sharePdf',
              callback: (args) async {
                try {
                  final String base64Data = args[0];
                  final String fileName = args[1];
                  final bytes = _decodeBase64(base64Data);
                  final tempDir = await getTemporaryDirectory();
                  final file = File('${tempDir.path}/$fileName');
                  await file.writeAsBytes(bytes);
                  await Share.shareXFiles([XFile(file.path)], text: fileName);
                } catch (e) {
                  print("Paylaşma Hatası: $e");
                }
              },
            );

            // 3. YAZDIRMA
            controller.addJavaScriptHandler(
              handlerName: 'printPdf',
              callback: (args) async {
                try {
                  final String base64Data = args[0];
                  final String fileName = args[1];
                  final bytes = _decodeBase64(base64Data);
                  await Printing.layoutPdf(onLayout: (format) async => bytes, name: fileName);
                } catch (e) {
                  print("Yazdırma Hatası: $e");
                }
              },
            );

            // 4. KRİTİK GÜNCELLEME: ÖZEL KAYDETME (Diyalog + Klasör + İsim Güncelleme)
            controller.addJavaScriptHandler(
              handlerName: 'downloadPdf',
              callback: (args) async {
                final String base64Data = args[0];
                final String originalName = args[1];

                // İsim güncelleme: "dosya.pdf" -> "dosya+update.pdf"
                String newFileName;
                if (originalName.contains('.')) {
                  int lastDot = originalName.lastIndexOf('.');
                  newFileName = "${originalName.substring(0, lastDot)}+update${originalName.substring(lastDot)}";
                } else {
                  newFileName = "${originalName}+update";
                }

                // Kullanıcıya Onay Diyaloğu Göster
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Dosyayı Kaydet"),
                    content: Text("Dosya 'Download/PDF Reader' klasörüne kaydedilsin mi?\n\nYeni isim: $newFileName"),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("İptal"),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          try {
                            // Klasör yolunu ayarla (Android)
                            final directory = Directory('/storage/emulated/0/Download/PDF Reader');
                            
                            // Klasör yoksa oluştur
                            if (!await directory.exists()) {
                              await directory.create(recursive: true);
                            }

                            final bytes = _decodeBase64(base64Data);
                            final file = File('${directory.path}/$newFileName');
                            await file.writeAsBytes(bytes);

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Kaydedildi: Download/PDF Reader/$newFileName"),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            print("Kaydetme Hatası: $e");
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Kaydetme başarısız! İzinleri kontrol edin.")),
                              );
                            }
                          }
                        },
                        child: const Text("Kaydet"),
                      ),
                    ],
                  ),
                );
              },
            );
          },
          onConsoleMessage: (controller, consoleMessage) {
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
