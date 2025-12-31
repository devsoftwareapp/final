import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  
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
        primarySwatch: Colors.red,
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

class _WebViewPageState extends State<WebViewPage> with WidgetsBindingObserver {
  InAppWebViewController? webViewController;
  bool _isViewerOpen = false;
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint("🚀 PDF Reader başlatıldı");
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("📱 Uygulama ayarlardan geri döndü");
      _checkAndUpdatePermissionStatus();
    }
  }

  // İzin durumunu kontrol et ve JS'e bildir
  Future<void> _checkAndUpdatePermissionStatus() async {
    if (webViewController == null) return;
    
    final hasPermission = await _checkStoragePermission();
    debugPrint("✅ İzin durumu: $hasPermission");
    
    // JS tarafına izin durumunu bildir ve yeniden tarama tetikle
    await webViewController!.evaluateJavascript(source: """
      (function() {
        console.log("📱 Android resume - izin durumu güncelleniyor");
        if (typeof onAndroidResume === 'function') {
          onAndroidResume();
        }
        if (typeof scanDeviceForPDFs === 'function') {
          setTimeout(function() {
            scanDeviceForPDFs();
          }, 500);
        }
      })();
    """);
  }

  // Storage izin kontrolü
  Future<bool> _checkStoragePermission() async {
    if (Platform.isAndroid) {
      // Android 13+ için
      if (await Permission.photos.isGranted || 
          await Permission.videos.isGranted ||
          await Permission.audio.isGranted) {
        return true;
      }
      
      // Android 11-12 için manageExternalStorage
      if (await Permission.manageExternalStorage.isGranted) {
        return true;
      }
      
      // Android 10 ve altı için storage
      if (await Permission.storage.isGranted) {
        return true;
      }
      
      return false;
    }
    return true;
  }

  // Cihazdan PDF dosyalarını listele
  Future<List<Map<String, dynamic>>> _listPdfFiles() async {
    List<Map<String, dynamic>> pdfFiles = [];
    
    try {
      if (Platform.isAndroid) {
        debugPrint("📂 PDF dosyaları taranıyor...");
        
        // Yaygın PDF dizinlerini tara
        List<String> searchPaths = [
          '/storage/emulated/0/Download',
          '/storage/emulated/0/Documents',
          '/storage/emulated/0/DCIM',
        ];

        int totalFound = 0;
        for (String path in searchPaths) {
          try {
            final directory = Directory(path);
            if (await directory.exists()) {
              await for (var entity in directory.list(recursive: true, followLinks: false)) {
                if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
                  try {
                    final stat = await entity.stat();
                    pdfFiles.add({
                      'path': entity.path,
                      'name': entity.path.split('/').last,
                      'size': stat.size,
                      'modified': stat.modified.toIso8601String(),
                    });
                    totalFound++;
                  } catch (e) {
                    debugPrint("⚠️ Dosya bilgisi alınamadı: ${entity.path}");
                  }
                }
              }
            }
          } catch (e) {
            debugPrint("❌ Dizin tarama hatası: $path - $e");
          }
        }
        
        debugPrint("✅ Toplam $totalFound PDF dosyası bulundu");
      }
    } catch (e) {
      debugPrint("❌ PDF listeleme hatası: $e");
    }
    
    return pdfFiles;
  }

  // Dosya boyutunu formatla
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // Base64 temizleme ve decode işlemi
  Uint8List _decodeBase64(String base64String) {
    String cleanBase64 = base64String;
    if (base64String.contains(',')) {
      cleanBase64 = base64String.split(',').last;
    }
    cleanBase64 = cleanBase64.replaceAll('\n', '').replaceAll('\r', '').trim();
    return base64Decode(cleanBase64);
  }

  // Dosyayı İndirme/Kaydetme Fonksiyonu
  Future<void> _savePdfToFile(String base64Data, String fileName) async {
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
        if (!status.isGranted) {
          debugPrint("❌ Depolama izni reddedildi");
          return;
        }
      }
    }

    try {
      debugPrint("💾 PDF kaydediliyor: $fileName");
      
      final bytes = _decodeBase64(base64Data);
      final sizeInMB = bytes.length / (1024 * 1024);
      debugPrint("📦 Dosya boyutu: ${sizeInMB.toStringAsFixed(2)} MB");
      
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (!await directory.exists()) {
        directory = await getExternalStorageDirectory();
      }

      if (directory != null) {
        final file = File('${directory.path}/$fileName');
        int counter = 1;
        String finalName = fileName;
        String nameWithoutExt = fileName.replaceAll('.pdf', '');
        
        while (await file.exists()) {
          finalName = '$nameWithoutExt ($counter).pdf';
          counter++;
        }
        
        final finalFile = File('${directory.path}/$finalName');
        await finalFile.writeAsBytes(bytes);

        debugPrint("✅ PDF kaydedildi: ${finalFile.path}");

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Kaydedildi: $finalName'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Dosya kaydetme hatası: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Dosya kaydedilemedi'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (webViewController != null) {
          if (_isViewerOpen) {
            final result = await webViewController!.evaluateJavascript(
              source: "window.viewerBackPressed ? window.viewerBackPressed() : false;"
            );
            if (result == 'exit_viewer') {
              return false;
            }
            return false;
          } else {
            final result = await webViewController!.evaluateJavascript(
              source: "window.androidBackPressed ? window.androidBackPressed() : false;"
            );
            
            if (result == 'exit_check') {
              return true;
            }
            return false;
          }
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
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
              displayZoomControls: false,
              builtInZoomControls: false,
              safeBrowsingEnabled: false,
              // ✅ OPFS desteği için gerekli
              sharedCookiesEnabled: true,
              thirdPartyCookiesEnabled: true,
              // ✅ Büyük dosyalar için cache artırımı
              cacheEnabled: true,
              clearCache: false,
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: """
                  if (typeof Android === 'undefined') {
                    window.Android = {
                      openSettings: function() {
                        window.flutter_inappwebview.callHandler('openSettingsForPermission');
                      },
                      checkPermission: function() {
                        return false;
                      },
                      listPDFs: function() {
                        return "";
                      },
                      getFileAsBase64: function(path) {
                        return "";
                      },
                      shareFile: function(base64, name) {
                        window.flutter_inappwebview.callHandler('sharePdf', base64, name);
                      },
                      shareFileByPath: function(path) {
                        window.flutter_inappwebview.callHandler('sharePdfByPath', path);
                      },
                      printFile: function(base64) {
                        window.flutter_inappwebview.callHandler('printPdf', base64, 'belge.pdf');
                      }
                    };
                  }
                """,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            onWebViewCreated: (controller) {
              webViewController = controller;
              debugPrint("🌐 WebView oluşturuldu");

              // --- HANDLER: İZİN DURUMU KONTROL ET ---
              controller.addJavaScriptHandler(
                handlerName: 'checkStoragePermission',
                callback: (args) async {
                  final hasPermission = await _checkStoragePermission();
                  debugPrint("🔒 İzin kontrolü: $hasPermission");
                  return hasPermission;
                },
              );

              // --- HANDLER: PDF DOSYALARINI LİSTELE ---
              controller.addJavaScriptHandler(
                handlerName: 'listPdfFiles',
                callback: (args) async {
                  debugPrint("📋 PDF listesi istendi");
                  final pdfFiles = await _listPdfFiles();
                  return jsonEncode(pdfFiles);
                },
              );

              // --- HANDLER: DOSYA İÇERİĞİNİ BASE64 OLARAK AL ---
              controller.addJavaScriptHandler(
                handlerName: 'getFileAsBase64',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    debugPrint("📄 Dosya okunuyor: $filePath");
                    
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      final stat = await file.stat();
                      final sizeInMB = stat.size / (1024 * 1024);
                      debugPrint("📦 Dosya boyutu: ${sizeInMB.toStringAsFixed(2)} MB");
                      
                      // Büyük dosyalar için chunk okuma (10MB+)
                      if (sizeInMB > 10) {
                        debugPrint("⚠️ Büyük dosya tespit edildi, chunk okuma yapılacak");
                      }
                      
                      final bytes = await file.readAsBytes();
                      final base64 = 'data:application/pdf;base64,${base64Encode(bytes)}';
                      
                      debugPrint("✅ Dosya base64'e dönüştürüldü");
                      return base64;
                    } else {
                      debugPrint("❌ Dosya bulunamadı: $filePath");
                    }
                  } catch (e) {
                    debugPrint("❌ Dosya okuma hatası: $e");
                  }
                  return null;
                },
              );

              // --- HANDLER: DOSYA BOYUTU AL ---
              controller.addJavaScriptHandler(
                handlerName: 'getFileSize',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      final stat = await file.stat();
                      debugPrint("📏 Dosya boyutu: ${_formatFileSize(stat.size)}");
                      return stat.size;
                    }
                  } catch (e) {
                    debugPrint("❌ Dosya boyutu alma hatası: $e");
                  }
                  return 0;
                },
              );

              // --- HANDLER: DOSYA CHUNK OKUMA (BÜYÜK DOSYALAR İÇİN) ---
              controller.addJavaScriptHandler(
                handlerName: 'getFileChunk',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    int offset = args[1];
                    int chunkSize = args[2];
                    
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      final randomAccessFile = await file.open();
                      await randomAccessFile.setPosition(offset);
                      
                      final bytes = await randomAccessFile.read(chunkSize);
                      await randomAccessFile.close();
                      
                      if (bytes.isNotEmpty) {
                        final chunkMB = bytes.length / (1024 * 1024);
                        debugPrint("📦 Chunk okundu: ${chunkMB.toStringAsFixed(2)} MB (offset: $offset)");
                        return base64Encode(bytes);
                      }
                    }
                  } catch (e) {
                    debugPrint("❌ Chunk okuma hatası: $e");
                  }
                  return '';
                },
              );

              // --- HANDLER: AYARLARI AÇ ---
              controller.addJavaScriptHandler(
                handlerName: 'openSettingsForPermission',
                callback: (args) async {
                  debugPrint("⚙️ Ayarlar açılıyor...");
                  if (Platform.isAndroid) {
                    try {
                      final packageInfo = await PackageInfo.fromPlatform();
                      final packageName = packageInfo.packageName;

                      final intent = AndroidIntent(
                        action: 'android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION',
                        data: 'package:$packageName',
                      );
                      await intent.launch();
                      debugPrint("✅ Ayarlar açıldı");
                    } catch (e) {
                      debugPrint("❌ Özel ayar intent hatası: $e");
                      await openAppSettings();
                    }
                  } else {
                    await openAppSettings();
                  }
                },
              );

              // --- HANDLER: PAYLAŞ ---
              controller.addJavaScriptHandler(
                handlerName: 'sharePdf',
                callback: (args) async {
                  try {
                    String base64Data = args[0];
                    String fileName = args.length > 1 ? args[1] : 'document.pdf';
                    
                    debugPrint("📤 PDF paylaşılıyor: $fileName");
                    
                    final bytes = _decodeBase64(base64Data);
                    final sizeInMB = bytes.length / (1024 * 1024);
                    debugPrint("📦 Paylaşım boyutu: ${sizeInMB.toStringAsFixed(2)} MB");
                    
                    final tempDir = await getTemporaryDirectory();
                    final file = File('${tempDir.path}/$fileName');
                    await file.writeAsBytes(bytes);
                    
                    await Share.shareXFiles([XFile(file.path)], text: fileName);
                    debugPrint("✅ PDF paylaşıldı");
                  } catch (e) {
                    debugPrint("❌ Paylaşma Hatası: $e");
                  }
                },
              );

              // --- HANDLER: PATH İLE PAYLAŞ ---
              controller.addJavaScriptHandler(
                handlerName: 'sharePdfByPath',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    debugPrint("📤 Dosya yolu ile paylaşılıyor: $filePath");
                    
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      await Share.shareXFiles([XFile(file.path)]);
                      debugPrint("✅ PDF paylaşıldı");
                    } else {
                      debugPrint("❌ Dosya bulunamadı: $filePath");
                    }
                  } catch (e) {
                    debugPrint("❌ Path ile paylaşma hatası: $e");
                  }
                },
              );

              // --- HANDLER: YAZDIR ---
              controller.addJavaScriptHandler(
                handlerName: 'printPdf',
                callback: (args) async {
                  try {
                    String base64Data = args[0];
                    String fileName = args.length > 1 ? args[1] : 'document.pdf';
                    
                    debugPrint("🖨️ PDF yazdırılıyor: $fileName");
                    
                    final bytes = _decodeBase64(base64Data);
                    
                    await Printing.layoutPdf(
                      onLayout: (format) async => bytes,
                      name: fileName,
                    );
                    
                    debugPrint("✅ Yazdırma tamamlandı");
                  } catch (e) {
                    debugPrint("❌ Yazdırma Hatası: $e");
                  }
                },
              );

              // --- HANDLER: PATH İLE YAZDIR ---
              controller.addJavaScriptHandler(
                handlerName: 'printPdfByPath',
                callback: (args) async {
                  try {
                    String filePath = args[0];
                    debugPrint("🖨️ Dosya yolu ile yazdırılıyor: $filePath");
                    
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      final bytes = await file.readAsBytes();
                      await Printing.layoutPdf(
                        onLayout: (format) async => bytes,
                        name: file.path.split('/').last,
                      );
                      debugPrint("✅ Yazdırma tamamlandı");
                    } else {
                      debugPrint("❌ Dosya bulunamadı: $filePath");
                    }
                  } catch (e) {
                    debugPrint("❌ Path ile yazdırma hatası: $e");
                  }
                },
              );

              // --- HANDLER: İNDİR ---
              controller.addJavaScriptHandler(
                handlerName: 'downloadPdf',
                callback: (args) async {
                  try {
                    String base64Data = args[0];
                    String fileName = args.length > 1 ? args[1] : 'document.pdf';
                    await _savePdfToFile(base64Data, fileName);
                  } catch (e) {
                    debugPrint("❌ İndirme Hatası: $e");
                  }
                },
              );

              // --- HANDLER: OPFS DESTEK KONTROLÜ ---
              controller.addJavaScriptHandler(
                handlerName: 'checkOPFSSupport',
                callback: (args) async {
                  debugPrint("✅ OPFS desteği aktif");
                  return true;
                },
              );
            },
            onLoadStart: (controller, url) {
              final urlString = url.toString();
              debugPrint("🌐 Sayfa yükleniyor: $urlString");
              setState(() {
                _isViewerOpen = urlString.contains("viewer.html");
              });
            },
            onLoadStop: (controller, url) async {
              final urlString = url.toString();
              debugPrint("✅ Sayfa yüklendi: $urlString");
              
              setState(() {
                _isViewerOpen = urlString.contains("viewer.html");
              });
              
              // Sayfa yüklendikten sonra izin durumunu kontrol et
              await _checkAndUpdatePermissionStatus();
            },
            onConsoleMessage: (controller, consoleMessage) {
              // JS Console mesajlarını Flutter console'a yaz
              final message = consoleMessage.message;
              final level = consoleMessage.messageLevel;
              
              String prefix = "📱 JS";
              if (level == ConsoleMessageLevel.ERROR) {
                prefix = "❌ JS ERROR";
              } else if (level == ConsoleMessageLevel.WARNING) {
                prefix = "⚠️ JS WARN";
              }
              
              debugPrint("$prefix: $message");
            },
            onLoadError: (controller, url, code, message) {
              debugPrint("❌ Yükleme hatası: $message (code: $code)");
            },
            onLoadHttpError: (controller, url, statusCode, description) {
              debugPrint("❌ HTTP hatası: $description (status: $statusCode)");
            },
            // ✅ OPFS için gerekli - Storage erişim hatalarını önle
            onPermissionRequest: (controller, permissionRequest) async {
              debugPrint("🔒 İzin isteği: ${permissionRequest.resources}");
              return PermissionResponse(
                resources: permissionRequest.resources,
                action: PermissionResponseAction.GRANT,
              );
            },
          ),
        ),
      ),
    );
  }
}


