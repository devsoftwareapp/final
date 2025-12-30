import 'dart:convert';
import 'dart:io';
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
      // İzin kontrolü
      PermissionStatus status;
      if (Platform.isAndroid && await Permission.manageExternalStorage.isGranted) {
        status = PermissionStatus.granted;
      } else {
        status = await Permission.storage.status;
      }

      if (!status.isGranted) {
        return "PERMISSION_DENIED";
      }

      final List<File> pdfFiles = [];
      final List<String> pdfPaths = [];

      // Tarama yapılacak dizinler (Android)
      final List<String> scanPaths = [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Documents',
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0',
      ];

      for (final scanPath in scanPaths) {
        try {
          final directory = Directory(scanPath);
          if (await directory.exists()) {
            await _scanDirectoryRecursive(directory, pdfFiles);
          }
        } catch (e) {
          debugPrint("Directory scan error for $scanPath: $e");
        }
      }

      // PDF dosyalarını path listesine çevir
      for (final file in pdfFiles) {
        pdfPaths.add(file.path);
      }

      // Listeyi string olarak döndür (|| ile ayrılmış)
      return pdfPaths.join('||');
    } catch (e) {
      debugPrint("PDF scan error: $e");
      return "ERROR";
    }
  }

  // Rekürsif olarak dizin tara
  Future<void> _scanDirectoryRecursive(Directory dir, List<File> pdfFiles) async {
    try {
      final List<FileSystemEntity> entities = await dir.list().toList();
      
      for (final entity in entities) {
        if (entity is File) {
          // Sadece PDF dosyalarını ekle
          if (entity.path.toLowerCase().endsWith('.pdf')) {
            pdfFiles.add(entity);
          }
        } else if (entity is Directory) {
          // Bazı sistem dizinlerini atla
          final dirName = path.basename(entity.path).toLowerCase();
          if (!dirName.startsWith('.') && 
              !['android', 'sys', 'proc', 'dev'].contains(dirName)) {
            try {
              await _scanDirectoryRecursive(entity, pdfFiles);
            } catch (e) {
              // Alt dizin okuma hatasını görmezden gel
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Directory list error for ${dir.path}: $e");
    }
  }

  // Dosya boyutunu formatla
  String _formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  // Dosya tarihini formatla
  String _formatFileDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.'
           '${date.month.toString().padLeft(2, '0')}.'
           '${date.year}';
  }

  // WebView için Android fonksiyonlarını enjekte et
  Future<void> _injectAndroidFunctions() async {
    if (webViewController == null) return;

    // PDF listeleme fonksiyonu
    await webViewController!.evaluateJavascript(source: """
      // Global Android object'i oluştur
      window.Android = window.Android || {};
      
      // PDF listeleme fonksiyonu
      Android.listPDFs = function() {
        return new Promise((resolve) => {
          try {
            window.flutter_inappwebview.callHandler('listPDFs').then(function(result) {
              resolve(result);
            }).catch(function(error) {
              console.log('PDF listeleme hatası:', error);
              resolve('PERMISSION_DENIED');
            });
          } catch (e) {
            console.log('listPDFs error:', e);
            resolve('ERROR');
          }
        });
      };
      
      // İzin kontrol fonksiyonu
      Android.checkPermission = function() {
        return new Promise((resolve) => {
          try {
            window.flutter_inappwebview.callHandler('checkPermission').then(function(result) {
              resolve(result === 'true');
            }).catch(function(error) {
              console.log('İzin kontrol hatası:', error);
              resolve(false);
            });
          } catch (e) {
            console.log('checkPermission error:', e);
            resolve(false);
          }
        });
      };
      
      // Ayarları açma fonksiyonu
      Android.openSettings = function() {
        try {
          window.flutter_inappwebview.callHandler('openSettings');
        } catch (e) {
          console.log('openSettings error:', e);
        }
      };
      
      // Dosyayı base64 olarak alma
      Android.getFileAsBase64 = function(filePath) {
        return new Promise((resolve) => {
          try {
            window.flutter_inappwebview.callHandler('getFileAsBase64', filePath)
              .then(function(base64Data) {
                resolve(base64Data);
              })
              .catch(function(error) {
                console.log('Dosya okuma hatası:', error);
                resolve(null);
              });
          } catch (e) {
            console.log('getFileAsBase64 error:', e);
            resolve(null);
          }
        });
      };
      
      console.log('Android fonksiyonları enjekte edildi');
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
              // Index.html'ye geri dön
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
            now.difference(_lastBackPressTime!) > Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Çıkmak için tekrar basın'),
              duration: Duration(seconds: 2),
            ),
          );
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
            onWebViewCreated: (controller) {
              webViewController = controller;

              // Android fonksiyonlarını ekle
              _injectAndroidFunctions();

              // PDF listeleme handler
              controller.addJavaScriptHandler(
                handlerName: 'listPDFs',
                callback: (args) async {
                  try {
                    final result = await _scanDeviceForPDFs();
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
                      // Android 11+ için MANAGE_EXTERNAL_STORAGE kontrolü
                      if (await Permission.manageExternalStorage.isGranted) {
                        return "true";
                      }
                      status = await Permission.storage.status;
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
                    await openAppSettings();
                  } catch (e) {
                    debugPrint("openSettings error: $e");
                  }
                },
              );

              // Dosyayı base64 olarak okuma handler
              controller.addJavaScriptHandler(
                handlerName: 'getFileAsBase64',
                callback: (args) async {
                  try {
                    final filePath = args[0] as String;
                    final file = File(filePath);
                    
                    if (await file.exists()) {
                      final bytes = await file.readAsBytes();
                      final base64 = base64Encode(bytes);
                      return "data:application/pdf;base64,$base64";
                    }
                    return null;
                  } catch (e) {
                    debugPrint("getFileAsBase64 error: $e");
                    return null;
                  }
                },
              );

              // Diğer mevcut handler'lar...
              controller.addJavaScriptHandler(
                handlerName: 'openPdfViewer',
                callback: (args) {
                  final String base64Data = args[0];
                  final String pdfName = args[1];
                  
                  setState(() {
                    _isViewerOpen = true;
                    _currentViewerPdfName = pdfName;
                  });
                  
                  controller.evaluateJavascript(source: """
                    sessionStorage.setItem('currentPdfData', '$base64Data');
                    sessionStorage.setItem('currentPdfName', '$pdfName');
                    window.location.href = 'viewer.html';
                  """);
                },
              );

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
                    debugPrint("Paylaşma Hatası: $e");
                  }
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'printPdf',
                callback: (args) async {
                  try {
                    final String base64Data = args[0];
                    final String fileName = args[1];
                    final bytes = _decodeBase64(base64Data);
                    await Printing.layoutPdf(onLayout: (format) async => bytes, name: fileName);
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
                    final String originalName = args[1];
                    
                    // İzin kontrolü
                    PermissionStatus status;
                    if (Platform.isAndroid && await Permission.manageExternalStorage.isGranted) {
                      status = PermissionStatus.granted;
                    } else {
                      status = await Permission.storage.status;
                    }
                    
                    if (!status.isGranted) {
                      // İzin yoksa, izin iste
                      if (await Permission.storage.request().isGranted ||
                          await Permission.manageExternalStorage.request().isGranted) {
                        // İzin verildi, kaydet
                        final bytes = _decodeBase64(base64Data);
                        final directory = Directory('/storage/emulated/0/Download/PDF Reader');
                        if (!await directory.exists()) {
                          await directory.create(recursive: true);
                        }
                        
                        String finalFileName = originalName;
                        File file = File('${directory.path}/$finalFileName');
                        
                        int counter = 0;
                        while (await file.exists()) {
                          counter++;
                          finalFileName = "${originalName.replaceAll('.pdf', '')}($counter).pdf";
                          file = File('${directory.path}/$finalFileName');
                        }
                        
                        await file.writeAsBytes(bytes);
                        
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Kaydedildi: $finalFileName"),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    } else {
                      // İzin var, direkt kaydet
                      final bytes = _decodeBase64(base64Data);
                      final directory = Directory('/storage/emulated/0/Download/PDF Reader');
                      if (!await directory.exists()) {
                        await directory.create(recursive: true);
                      }
                      
                      String finalFileName = originalName;
                      File file = File('${directory.path}/$finalFileName');
                      
                      int counter = 0;
                      while (await file.exists()) {
                        counter++;
                        finalFileName = "${originalName.replaceAll('.pdf', '')}($counter).pdf";
                        file = File('${directory.path}/$finalFileName');
                      }
                      
                      await file.writeAsBytes(bytes);
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Kaydedildi: $finalFileName"),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  } catch (e) {
                    debugPrint("Kaydetme Hatası: $e");
                  }
                },
              );
            },
            onLoadStart: (controller, url) async {
              // URL değişikliklerini takip et
              final urlString = url?.toString() ?? '';
              
              setState(() {
                _isViewerOpen = urlString.contains('viewer.html');
                
                if (!_isViewerOpen) {
                  _currentViewerPdfName = null;
                }
              });
            },
            onLoadStop: (controller, url) async {
              // Sayfa yüklendiğinde Android fonksiyonlarını tekrar enjekte et
              await _injectAndroidFunctions();
              
              // Cihaz sekmesi açıldığında izin kontrolü yap
              final urlString = url?.toString() ?? '';
              if (urlString.contains('index.html')) {
                await controller.evaluateJavascript(source: """
                  // Sayfa yüklendiğinde izin durumunu kontrol et
                  setTimeout(function() {
                    if (typeof Android !== 'undefined' && typeof Android.checkPermission === 'function') {
                      Android.checkPermission().then(function(hasPermission) {
                        if (hasPermission) {
                          // İzin varsa cihaz PDF'lerini tara
                          if (typeof scanDeviceForPDFs === 'function') {
                            scanDeviceForPDFs();
                          }
                        }
                      });
                    }
                  }, 1000);
                """);
              }
            },
            onReceivedError: (controller, request, error) {
              debugPrint("WebView Error: $error");
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
