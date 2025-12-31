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
  final Map<String, List<int>> _fileChunks = {};
  final Map<String, int> _fileSizes = {};

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
    debugPrint("🔒 İzin durumu: $hasPermission");
    
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
      final android13Permissions = await Future.wait([
        Permission.photos.status,
        Permission.videos.status,
        Permission.audio.status,
      ]);
      
      if (android13Permissions.any((status) => status.isGranted)) {
        return true;
      }
      
      // Android 11-12 için manageExternalStorage
      final manageStorageStatus = await Permission.manageExternalStorage.status;
      if (manageStorageStatus.isGranted) {
        return true;
      }
      
      // Android 10 ve altı için storage
      final storageStatus = await Permission.storage.status;
      if (storageStatus.isGranted) {
        return true;
      }
      
      return false;
    }
    return true;
  }

  // Cihazdan PDF dosyalarını listele (Gelişmiş versiyon)
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
          '/storage/emulated/0/Downloads',
          '/storage/emulated/0',
          '/sdcard/Download',
          '/sdcard/Documents',
        ];

        int totalFound = 0;
        
        for (String path in searchPaths) {
          try {
            final directory = Directory(path);
            if (await directory.exists()) {
              await _scanDirectoryRecursive(directory, pdfFiles);
              totalFound = pdfFiles.length;
            }
          } catch (e) {
            debugPrint("⚠️ Dizin tarama hatası: $path - $e");
            continue;
          }
        }
        
        debugPrint("✅ Toplam $totalFound PDF dosyası bulundu");
        
        // Dosyaları boyuta göre sırala
        pdfFiles.sort((a, b) => b['size'].compareTo(a['size']));
      }
    } catch (e) {
      debugPrint("❌ PDF listeleme hatası: $e");
    }
    
    return pdfFiles;
  }

  // Dizini recursive olarak tara
  Future<void> _scanDirectoryRecursive(
    Directory directory, 
    List<Map<String, dynamic>> pdfFiles
  ) async {
    try {
      final contents = directory.list(recursive: false);
      
      await for (var entity in contents) {
        if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
          try {
            final stat = await entity.stat();
            final sizeInMB = stat.size / (1024 * 1024);
            
            // Çok büyük dosyaları atla (500MB+)
            if (sizeInMB > 500) {
              debugPrint("⚠️ Çok büyük dosya atlandı: ${entity.path} (${sizeInMB.toStringAsFixed(2)} MB)");
              continue;
            }
            
            pdfFiles.add({
              'path': entity.path,
              'name': entity.path.split('/').last,
              'size': stat.size,
              'modified': stat.modified.toIso8601String(),
              'sizeMB': sizeInMB,
            });
            
          } catch (e) {
            debugPrint("⚠️ Dosya bilgisi alınamadı: ${entity.path}");
          }
        } else if (entity is Directory) {
          // Alt dizinleri tara (belirli derinlikte)
          final dirName = entity.path.split('/').last.toLowerCase();
          // Sistem dizinlerini atla
          if (!dirName.startsWith('.') && 
              dirName != 'android' && 
              dirName != 'lost+found' &&
              !dirName.contains('cache')) {
            await _scanDirectoryRecursive(entity, pdfFiles);
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Dizin tarama hatası (${directory.path}): $e");
    }
  }

  // Dosya boyutunu formatla
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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
        
        if (!await directory.exists()) {
          directory = Directory('/storage/emulated/0/Downloads');
        }
        
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory != null && await directory.exists()) {
        final file = File('${directory.path}/$fileName');
        int counter = 1;
        String finalName = fileName;
        String nameWithoutExt = fileName.replaceAll('.pdf', '');
        
        while (await file.exists()) {
          finalName = '$nameWithoutExt ($counter).pdf';
          counter++;
        }
        
        final finalFile = File('${directory.path}/$finalName');
        await finalFile.writeAsBytes(bytes, flush: true);

        debugPrint("✅ PDF kaydedildi: ${finalFile.path}");

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Kaydedildi: $finalName'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        debugPrint("❌ Dizin bulunamadı");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Dizin bulunamadı'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Dosya kaydetme hatası: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnakcBar(
          SnackBar(
            content: Text('❌ Dosya kaydedilemedi: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Büyük dosyaları chunk'lara ayırarak oku
  Future<Uint8List> _readFileInChunks(File file, int chunkSize) async {
    final fileSize = await file.length();
    final totalChunks = (fileSize / chunkSize).ceil();
    final bytes = BytesBuilder();
    
    debugPrint("📦 Dosya chunk'lara ayrılıyor: $totalChunks chunk");
    
    for (int i = 0; i < totalChunks; i++) {
      final start = i * chunkSize;
      final end = (i + 1) * chunkSize;
      final chunk = await file.openRead(start, end > fileSize ? fileSize : end).first;
      bytes.add(chunk);
      
      // Her 10 chunk'ta bir progress göster
      if (i % 10 == 0) {
        final progress = ((i + 1) / totalChunks * 100).toInt();
        debugPrint("📊 Okuma progress: $progress%");
      }
    }
    
    return bytes.toBytes();
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
              // ✅ Performans optimizasyonları
              supportZoom: false,
              disableVerticalScroll: false,
              disableHorizontalScroll: false,
              // ✅ WebGL ve canvas desteği
              hardwareAcceleration: true,
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
                      },
                      getFileChunk: function(path, offset, chunkSize) {
                        return "";
                      }
                    };
                  }
                  
                  // OPFS desteği kontrolü
                  if (typeof navigator.storage !== 'undefined' && navigator.storage.getDirectory) {
                    console.log("✅ OPFS destekleniyor");
                  } else {
                    console.log("⚠️ OPFS desteklenmiyor, fallback mekanizmaları kullanılacak");
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
                  try {
                    final pdfFiles = await _listPdfFiles();
                    final jsonResult = jsonEncode(pdfFiles);
                    debugPrint("✅ PDF listesi hazır: ${pdfFiles.length} dosya");
                    return jsonResult;
                  } catch (e) {
                    debugPrint("❌ PDF listeleme hatası: $e");
                    return "[]";
                  }
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
                      
                      // Büyük dosyalar için chunk okuma
                      Uint8List bytes;
                      if (sizeInMB > 50) {
                        debugPrint("⚠️ Büyük dosya tespit edildi, chunk okuma yapılıyor...");
                        bytes = await _readFileInChunks(file, 5 * 1024 * 1024); // 5MB chunks
                      } else {
                        bytes = await file.readAsBytes();
                      }
                      
                      final base64 = 'data:application/pdf;base64,${base64Encode(bytes)}';
                      
                      debugPrint("✅ Dosya base64'e dönüştürüldü");
                      return base64;
                    } else {
                      debugPrint("❌ Dosya bulunamadı: $filePath");
                      return null;
                    }
                  } catch (e) {
                    debugPrint("❌ Dosya okuma hatası: $e");
                    return null;
                  }
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
                    
                    debugPrint("📦 Chunk okunuyor: $filePath (offset: $offset, size: $chunkSize)");
                    
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
                        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
                      );
                      await intent.launch();
                      debugPrint("✅ Ayarlar açıldı");
                    } catch (e) {
                      debugPrint("❌ Özel ayar intent hatası: $e");
                      
                      // Fallback intent
                      try {
                        final intent = AndroidIntent(
                          action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
                          data: 'package:$packageName',
                          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
                        );
                        await intent.launch();
                      } catch (e2) {
                        debugPrint("❌ Fallback intent hatası: $e2");
                        await openAppSettings();
                      }
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
                    final tempFile = File('${tempDir.path}/$fileName');
                    await tempFile.writeAsBytes(bytes, flush: true);
                    
                    await Share.shareXFiles([XFile(tempFile.path)], text: fileName);
                    
                    // Temp dosyayı sil
                    await Future.delayed(const Duration(seconds: 5), () async {
                      try {
                        await tempFile.delete();
                        debugPrint("🗑️ Temp dosya silindi");
                      } catch (e) {
                        debugPrint("⚠️ Temp dosya silinemedi: $e");
                      }
                    });
                    
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
                    
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ Yazdırma hatası: ${e.toString()}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
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
                  debugPrint("✅ OPFS desteği kontrol edildi");
                  return true;
                },
              );
              
              // --- HANDLER: UYGULAMA DURUMU ---
              controller.addJavaScriptHandler(
                handlerName: 'getAppStatus',
                callback: (args) async {
                  return jsonEncode({
                    'platform': Platform.operatingSystem,
                    'version': Platform.operatingSystemVersion,
                    'storageAvailable': await _checkStoragePermission(),
                    'tempDir': (await getTemporaryDirectory()).path,
                    'appDir': (await getApplicationDocumentsDirectory()).path,
                  });
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
              
              // OPFS desteğini kontrol et
              await controller.evaluateJavascript(source: """
                if (typeof navigator.storage !== 'undefined' && navigator.storage.getDirectory) {
                  console.log("✅ OPFS aktif");
                  if (typeof pdfManager !== 'undefined' && pdfManager.init) {
                    pdfManager.init().then(function(success) {
                      console.log("📦 OPFS Manager: " + (success ? "Başarılı" : "Başarısız"));
                    });
                  }
                }
              """);
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
              } else if (level == ConsoleMessageLevel.DEBUG) {
                prefix = "🐛 JS DEBUG";
              }
              
              debugPrint("$prefix: $message");
            },
            onLoadError: (controller, url, code, message) {
              debugPrint("❌ Yükleme hatası: $message (code: $code)");
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ Yükleme hatası: $message'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
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
            onProgressChanged: (controller, progress) {
              if (progress == 100) {
                debugPrint("✅ Sayfa yükleme tamamlandı");
              }
            },
          ),
        ),
      ),
    );
  }
}
