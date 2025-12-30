import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;

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
  DateTime? _lastBackPressTime;
  bool _isViewerOpen = false;
  String? _currentViewerPdfName;

  Uint8List _decodeBase64(String base64String) {
    if (base64String.contains(',')) {
      base64String = base64String.split(',').last;
    }
    return base64Decode(base64String);
  }

  // Cihazdaki PDF dosyalarını tara
  Future<String> _scanDeviceForPDFs() async {
    try {
      debugPrint("PDF tarama başlatılıyor...");
      
      // İzin kontrolü
      PermissionStatus status;
      if (Platform.isAndroid) {
        // Önce storage iznini kontrol et
        status = await Permission.storage.status;
        if (!status.isGranted) {
          return "PERMISSION_DENIED";
        }
      } else {
        status = await Permission.storage.status;
        if (!status.isGranted) {
          return "PERMISSION_DENIED";
        }
      }

      final List<String> pdfPaths = [];

      // Öncelikli olarak sık kullanılan dizinleri tara
      final List<String> commonPaths = [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Documents',
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Telegram',
        '/storage/emulated/0/WhatsApp/Media',
      ];

      debugPrint("Dizinler taranıyor...");

      for (final scanPath in commonPaths) {
        try {
          final directory = Directory(scanPath);
          if (await directory.exists()) {
            debugPrint("Dizin taranıyor: $scanPath");
            final files = await _findPdfFilesInDirectory(directory);
            pdfPaths.addAll(files);
            debugPrint("$scanPath dizininde ${files.length} PDF bulundu");
          }
        } catch (e) {
          debugPrint("Dizin tarama hatası ($scanPath): $e");
        }
      }

      // Root dizini de tara (daha yüzeysel)
      try {
        final rootDir = Directory('/storage/emulated/0');
        final rootFiles = await _findPdfFilesInDirectory(rootDir, maxDepth: 1);
        pdfPaths.addAll(rootFiles);
        debugPrint("Root dizinde ${rootFiles.length} PDF bulundu");
      } catch (e) {
        debugPrint("Root tarama hatası: $e");
      }

      // Tekilleştir ve sırala
      final uniquePaths = pdfPaths.toSet().toList();
      uniquePaths.sort();

      debugPrint("Toplam ${uniquePaths.length} PDF dosyası bulundu");

      // Listeyi string olarak döndür (|| ile ayrılmış)
      return uniquePaths.join('||');
    } catch (e) {
      debugPrint("PDF tarama hatası: $e");
      return "ERROR";
    }
  }

  // Dizindeki PDF dosyalarını bul
  Future<List<String>> _findPdfFilesInDirectory(Directory dir, {int maxDepth = 3, int currentDepth = 0}) async {
    final List<String> pdfPaths = [];
    
    try {
      if (currentDepth >= maxDepth) {
        return pdfPaths;
      }

      final List<FileSystemEntity> entities;
      try {
        entities = await dir.list().toList();
      } catch (e) {
        // Dizin okuma hatası
        return pdfPaths;
      }

      for (final entity in entities) {
        try {
          if (entity is File) {
            // Sadece PDF dosyalarını ekle
            if (entity.path.toLowerCase().endsWith('.pdf')) {
              pdfPaths.add(entity.path);
            }
          } else if (entity is Directory) {
            // Bazı sistem dizinlerini atla
            final dirName = path.basename(entity.path).toLowerCase();
            final skipDirs = {
              'android', 'sys', 'proc', 'dev', 'data', 'system', 'cache',
              'lost+found', 'recovery', 'vendor', 'product', 'oem',
              'preload', 'apex', 'firmware', 'odm', 'postinstall'
            };
            
            if (!dirName.startsWith('.') && !skipDirs.contains(dirName)) {
              try {
                final subPdfs = await _findPdfFilesInDirectory(
                  entity,
                  maxDepth: maxDepth,
                  currentDepth: currentDepth + 1
                );
                pdfPaths.addAll(subPdfs);
              } catch (e) {
                // Alt dizin hatasını görmezden gel
              }
            }
          }
        } catch (e) {
          // Entity işleme hatası
        }
      }
    } catch (e) {
      debugPrint("Dizin tarama hatası (${dir.path}): $e");
    }
    
    return pdfPaths;
  }

  // WebView için Android fonksiyonlarını enjekte et
  Future<void> _injectAndroidFunctions() async {
    if (webViewController == null) return;

    await webViewController!.evaluateJavascript(source: """
      // Global Android object'i oluştur veya güncelle
      if (typeof window.Android === 'undefined') {
        window.Android = {};
      }
      
      // PDF listeleme fonksiyonu
      Android.listPDFs = function() {
        return new Promise((resolve, reject) => {
          try {
            window.flutter_inappwebview.callHandler('listPDFs').then(function(result) {
              resolve(result || '');
            }).catch(function(error) {
              console.error('PDF listeleme hatası:', error);
              reject(error);
            });
          } catch (e) {
            console.error('listPDFs error:', e);
            reject(e);
          }
        });
      };
      
      // İzin kontrol fonksiyonu
      Android.checkPermission = function() {
        return new Promise((resolve, reject) => {
          try {
            window.flutter_inappwebview.callHandler('checkPermission').then(function(result) {
              resolve(result === 'true' || result === true);
            }).catch(function(error) {
              console.error('İzin kontrol hatası:', error);
              resolve(false);
            });
          } catch (e) {
            console.error('checkPermission error:', e);
            resolve(false);
          }
        });
      };
      
      // Ayarları açma fonksiyonu
      Android.openSettings = function() {
        return new Promise((resolve) => {
          try {
            window.flutter_inappwebview.callHandler('openSettings').then(function() {
              resolve(true);
            }).catch(function(error) {
              console.error('Ayarlar açma hatası:', error);
              resolve(false);
            });
          } catch (e) {
            console.error('openSettings error:', e);
            resolve(false);
          }
        });
      };
      
      // Dosyayı base64 olarak alma
      Android.getFileAsBase64 = function(filePath) {
        return new Promise((resolve, reject) => {
          try {
            window.flutter_inappwebview.callHandler('getFileAsBase64', filePath)
              .then(function(base64Data) {
                resolve(base64Data);
              })
              .catch(function(error) {
                console.error('Dosya okuma hatası:', error);
                reject(error);
              });
          } catch (e) {
            console.error('getFileAsBase64 error:', e);
            reject(e);
          }
        });
      };
      
      // Dosya paylaşma fonksiyonları
      Android.shareFile = function(base64Data, fileName) {
        return new Promise((resolve) => {
          try {
            window.flutter_inappwebview.callHandler('sharePdf', base64Data, fileName)
              .then(function() {
                resolve(true);
              })
              .catch(function(error) {
                console.error('Dosya paylaşma hatası:', error);
                resolve(false);
              });
          } catch (e) {
            console.error('shareFile error:', e);
            resolve(false);
          }
        });
      };
      
      Android.shareFiles = function(fileData) {
        return new Promise((resolve) => {
          try {
            const files = fileData.split('||').filter(f => f);
            if (files.length > 0) {
              // İlk dosyayı paylaş
              window.flutter_inappwebview.callHandler('sharePdf', files[0], 'shared_file.pdf')
                .then(function() {
                  resolve(true);
                })
                .catch(function(error) {
                  console.error('Dosya paylaşma hatası:', error);
                  resolve(false);
                });
            } else {
              resolve(false);
            }
          } catch (e) {
            console.error('shareFiles error:', e);
            resolve(false);
          }
        });
      };
      
      Android.printFile = function(base64Data) {
        return new Promise((resolve) => {
          try {
            window.flutter_inappwebview.callHandler('printPdf', base64Data, 'document.pdf')
              .then(function() {
                resolve(true);
              })
              .catch(function(error) {
                console.error('Dosya yazdırma hatası:', error);
                resolve(false);
              });
          } catch (e) {
            console.error('printFile error:', e);
            resolve(false);
          }
        });
      };
      
      console.log('Android fonksiyonları enjekte edildi/güncellendi');
    """);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Viewer'dan çıkma kontrolü
        if (_isViewerOpen && webViewController != null) {
          await webViewController!.evaluateJavascript(source: """
            try {
              window.location.href = 'index.html';
            } catch (e) {
              console.log('Back navigation error:', e);
            }
          """);
          setState(() {
            _isViewerOpen = false;
            _currentViewerPdfName = null;
          });
          return false;
        }

        // Çift tıklama ile çıkış
        final now = DateTime.now();
        if (_lastBackPressTime == null || 
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Çıkmak için tekrar basın'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return false;
        }
        return true;
      },
      child: Scaffold(
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
              cacheEnabled: true,
              transparentBackground: true,
              javaScriptCanOpenWindowsAutomatically: true,
              verticalScrollBarEnabled: true,
              horizontalScrollBarEnabled: true,
              supportZoom: false,
              mediaPlaybackRequiresUserGesture: false,
            ),
            onWebViewCreated: (controller) async {
              webViewController = controller;
              
              // Android fonksiyonlarını enjekte et
              await _injectAndroidFunctions();

              // PDF listeleme handler
              controller.addJavaScriptHandler(
                handlerName: 'listPDFs',
                callback: (args) async {
                  try {
                    debugPrint("listPDFs handler çağrıldı");
                    final result = await _scanDeviceForPDFs();
                    debugPrint("listPDFs sonucu: ${result.length} karakter");
                    return result;
                  } catch (e) {
                    debugPrint("listPDFs error: $e");
                    return "ERROR";
                  }
                },
              );

              // İzin kontrol handler
              controller.addJavaScriptHandler(
                handlerName: 'checkPermission',
                callback: (args) async {
                  try {
                    PermissionStatus status;
                    if (Platform.isAndroid) {
                      // Android için storage iznini kontrol et
                      status = await Permission.storage.status;
                      debugPrint("Storage izni durumu: ${status.isGranted}");
                    } else {
                      status = await Permission.storage.status;
                    }
                    return status.isGranted ? "true" : "false";
                  } catch (e) {
                    debugPrint("checkPermission error: $e");
                    return "false";
                  }
                },
              );

              // Ayarları açma handler
              controller.addJavaScriptHandler(
                handlerName: 'openSettings',
                callback: (args) async {
                  try {
                    debugPrint("Ayarlar açılıyor...");
                    await openAppSettings();
                    return true;
                  } catch (e) {
                    debugPrint("openSettings error: $e");
                    return false;
                  }
                },
              );

              // Dosyayı base64 olarak okuma handler
              controller.addJavaScriptHandler(
                handlerName: 'getFileAsBase64',
                callback: (args) async {
                  try {
                    final filePath = args[0] as String;
                    debugPrint("Base64 için dosya okunuyor: $filePath");
                    
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      final bytes = await file.readAsBytes();
                      final base64 = base64Encode(bytes);
                      final result = "data:application/pdf;base64,$base64";
                      debugPrint("Base64 veri hazır (${result.length} karakter)");
                      return result;
                    } else {
                      debugPrint("Dosya bulunamadı: $filePath");
                      return null;
                    }
                  } catch (e) {
                    debugPrint("getFileAsBase64 error: $e");
                    return null;
                  }
                },
              );

              // Mevcut handler'lar (orijinal fonksiyonları koru)
              controller.addJavaScriptHandler(
                handlerName: 'openPdfViewer',
                callback: (args) {
                  try {
                    final String base64Data = args[0];
                    final String pdfName = args[1];
                    
                    debugPrint("PDF Viewer açılıyor: $pdfName");
                    
                    setState(() {
                      _isViewerOpen = true;
                      _currentViewerPdfName = pdfName;
                    });
                    
                    controller.evaluateJavascript(source: """
                      try {
                        sessionStorage.setItem('currentPdfData', '$base64Data');
                        sessionStorage.setItem('currentPdfName', '$pdfName');
                        window.location.href = 'viewer.html';
                      } catch (e) {
                        console.error('Viewer açma hatası:', e);
                      }
                    """);
                  } catch (e) {
                    debugPrint("openPdfViewer error: $e");
                  }
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'sharePdf',
                callback: (args) async {
                  try {
                    final String base64Data = args[0];
                    final String fileName = args.length > 1 ? args[1] as String : 'document.pdf';
                    
                    debugPrint("PDF paylaşılıyor: $fileName");
                    
                    final bytes = _decodeBase64(base64Data);
                    final tempDir = await getTemporaryDirectory();
                    final file = File('${tempDir.path}/$fileName');
                    await file.writeAsBytes(bytes);
                    
                    await Share.shareXFiles([XFile(file.path)], text: fileName);
                    debugPrint("PDF başarıyla paylaşıldı");
                  } catch (e) {
                    debugPrint("Paylaşma Hatası: $e");
                  }
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'printPdf',
                callback: (args) async {
                  try {
                    final String base64Data = args[0];
                    final String fileName = args.length > 1 ? args[1] as String : 'document.pdf';
                    
                    debugPrint("PDF yazdırılıyor: $fileName");
                    
                    final bytes = _decodeBase64(base64Data);
                    await Printing.layoutPdf(
                      onLayout: (format) async => bytes,
                      name: fileName
                    );
                    
                    debugPrint("PDF başarıyla yazdırma diyaloğu açıldı");
                  } catch (e) {
                    debugPrint("Yazdırma Hatası: $e");
                  }
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'downloadPdf',
                callback: (args) async {
                  try {
                    final String base64Data = args[0];
                    final String originalName = args.length > 1 ? args[1] as String : 'document.pdf';
                    
                    debugPrint("PDF indiriliyor: $originalName");
                    
                    // İzin kontrolü
                    PermissionStatus status;
                    if (Platform.isAndroid) {
                      status = await Permission.storage.status;
                    } else {
                      status = await Permission.storage.status;
                    }
                    
                    if (!status.isGranted) {
                      debugPrint("İzin gerekli, izin isteniyor...");
                      final requested = await Permission.storage.request();
                      if (!requested.isGranted) {
                        debugPrint("İzin reddedildi");
                        return;
                      }
                    }
                    
                    // İzin verildi, kaydet
                    final bytes = _decodeBase64(base64Data);
                    final directory = Directory('/storage/emulated/0/Download/PDF Reader');
                    if (!await directory.exists()) {
                      await directory.create(recursive: true);
                      debugPrint("Dizin oluşturuldu: ${directory.path}");
                    }
                    
                    String finalFileName = originalName;
                    File file = File('${directory.path}/$finalFileName');
                    
                    int counter = 0;
                    while (await file.exists()) {
                      counter++;
                      final fileNameWithoutExt = originalName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
                      finalFileName = "$fileNameWithoutExt($counter).pdf";
                      file = File('${directory.path}/$finalFileName');
                    }
                    
                    await file.writeAsBytes(bytes);
                    debugPrint("PDF kaydedildi: ${file.path}");
                    
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Kaydedildi: $finalFileName"),
                          backgroundColor: Colors.green,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  } catch (e) {
                    debugPrint("Kaydetme Hatası: $e");
                  }
                },
              );

              // Android back button handler
              controller.addJavaScriptHandler(
                handlerName: 'androidBackPressed',
                callback: (args) async {
                  try {
                    debugPrint("Android back button pressed");
                    
                    // Mevcut URL'yi kontrol et
                    final currentUrl = await controller.getUrl();
                    final urlString = currentUrl?.toString() ?? '';
                    
                    if (urlString.contains('viewer.html')) {
                      // Viewer sayfasındaysak, index'e dön
                      await controller.evaluateJavascript(source: """
                        try {
                          window.location.href = 'index.html';
                        } catch (e) {
                          console.log('Back navigation error:', e);
                        }
                      """);
                      
                      setState(() {
                        _isViewerOpen = false;
                        _currentViewerPdfName = null;
                      });
                      
                      return true;
                    }
                    
                    // Diğer durumlarda false döndür (Flutter handle edecek)
                    return false;
                  } catch (e) {
                    debugPrint("Back button handler error: $e");
                    return false;
                  }
                },
              );

              debugPrint("Tüm JavaScript handler'ları eklendi");
            },
            onLoadStart: (controller, url) async {
              final urlString = url?.toString() ?? '';
              
              setState(() {
                _isViewerOpen = urlString.contains('viewer.html');
                
                if (!_isViewerOpen) {
                  _currentViewerPdfName = null;
                }
              });
              
              debugPrint("Sayfa yükleniyor: $urlString");
              debugPrint("Viewer durumu: $_isViewerOpen");
            },
            onLoadStop: (controller, url) async {
              // Android fonksiyonlarını tekrar enjekte et
              await _injectAndroidFunctions();
              
              final urlString = url?.toString() ?? '';
              debugPrint("Sayfa yüklendi: $urlString");
              
              if (urlString.contains('index.html')) {
                // Cihaz sekmesi için izin kontrolü yap
                await controller.evaluateJavascript(source: """
                  // Sayfa yüklendiğinde izin durumunu kontrol et
                  setTimeout(function() {
                    if (typeof Android !== 'undefined' && typeof Android.checkPermission === 'function') {
                      console.log('İzin kontrolü yapılıyor...');
                      Android.checkPermission().then(function(hasPermission) {
                        console.log('İzin durumu:', hasPermission);
                        if (hasPermission) {
                          // İzin varsa cihaz PDF'lerini tara
                          if (typeof scanDeviceForPDFs === 'function') {
                            console.log('Cihaz PDF taraması başlatılıyor...');
                            scanDeviceForPDFs();
                          }
                        } else {
                          console.log('İzin gerekli, permission banner gösterilecek');
                        }
                      });
                    }
                  }, 500);
                """);
              }
            },
            onReceivedError: (controller, request, error) {
              debugPrint("WebView Error: ${error.description}");
            },
            onConsoleMessage: (controller, consoleMessage) {
              debugPrint("WebView Console: ${consoleMessage.message}");
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    webViewController?.dispose();
    super.dispose();
  }
}
