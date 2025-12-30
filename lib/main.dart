import 'dart:async';
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
  bool _isProcessingAction = false;
  
  // OPFS ile ilgili durumlar
  String? _opfsPdfData;
  String? _opfsPdfName;
  bool _isOpfsMode = false;
  
  // OPFS için zamanlayıcı (büyük dosyalar için)
  Timer? _opfsSyncTimer;

  Uint8List _decodeBase64(String base64String) {
    if (base64String.contains(',')) {
      base64String = base64String.split(',').last;
    }
    return base64Decode(base64String);
  }

  // OPFS'den veri almak için JavaScript kodu
  String _getOpfsRetrievalScript(String pdfName) {
    return """
      (async function() {
        try {
          console.log('OPFS\'den PDF alınıyor: $pdfName');
          
          // OPFS kullanılıyor mu kontrol et
          const usingOPFS = sessionStorage.getItem('usingOPFS') === 'true';
          
          if (!usingOPFS) {
            console.log('OPFS kullanılmıyor, sessionStorage\'dan alınıyor');
            const pdfData = sessionStorage.getItem('currentPdfData');
            if (pdfData) {
              return { 
                success: true, 
                data: pdfData,
                isOpfs: false 
              };
            }
            return { success: false, error: 'PDF verisi bulunamadı' };
          }
          
          // OPFS'den dosyayı oku
          const root = await navigator.storage.getDirectory();
          const pdfDir = await root.getDirectoryHandle('pdfs', { create: false });
          
          let fileHandle;
          try {
            // Önce belirtilen isimle dene
            fileHandle = await pdfDir.getFileHandle('$pdfName');
          } catch {
            // Fallback: current.pdf
            fileHandle = await pdfDir.getFileHandle('current.pdf');
          }
          
          const file = await fileHandle.getFile();
          const arrayBuffer = await file.arrayBuffer();
          
          // ArrayBuffer'ı base64'e çevir
          const bytes = new Uint8Array(arrayBuffer);
          let binary = '';
          for (let i = 0; i < bytes.byteLength; i++) {
            binary += String.fromCharCode(bytes[i]);
          }
          const base64 = btoa(binary);
          const base64Data = 'data:application/pdf;base64,' + base64;
          
          console.log('OPFS\'den PDF başarıyla alındı: $pdfName');
          
          return { 
            success: true, 
            data: base64Data,
            isOpfs: true 
          };
          
        } catch (error) {
          console.error('OPFS\'den alma hatası:', error);
          
          // Fallback: sessionStorage
          const pdfData = sessionStorage.getItem('currentPdfData');
          if (pdfData) {
            return { 
              success: true, 
              data: pdfData,
              isOpfs: false 
            };
          }
          
          return { 
            success: false, 
            error: error.toString(),
            isOpfs: false 
          };
        }
      })();
    """;
  }

  // OPFS'den PDF verisi al
  Future<void> _retrievePdfFromOpfs(String pdfName) async {
    try {
      // JavaScript ile OPFS'den veri al
      final result = await webViewController!.evaluateJavascript(
        source: _getOpfsRetrievalScript(pdfName)
      );
      
      if (result != null) {
        final Map<String, dynamic> resultMap = jsonDecode(result);
        
        if (resultMap['success'] == true) {
          setState(() {
            _opfsPdfData = resultMap['data'];
            _opfsPdfName = pdfName;
            _isOpfsMode = resultMap['isOpfs'] == true;
          });
          
          debugPrint('OPFS PDF alındı: $pdfName (OPFS: $_isOpfsMode)');
        } else {
          debugPrint('OPFS\'den alma başarısız: ${resultMap['error']}');
        }
      }
    } catch (e) {
      debugPrint('OPFS alma hatası: $e');
    }
  }

  // GÖRSELDEKİ İZİN TASARIMINI GÖSTEREN FONKSİYON
  void _showPermissionDialog(String base64Data, String originalName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Kırmızı ikon alanı (Görseldeki gibi)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_open_rounded, size: 48, color: Colors.redAccent),
            ),
            const SizedBox(height: 24),
            const Text(
              "Dosya Erişimi Gerekli",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 12),
            const Text(
              "Cihazınızdaki dosyaları görmek, düzenlemek ve güncellemek için lütfen gerekli izni verin.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Şimdi Değil", style: TextStyle(color: Colors.grey)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      Navigator.pop(context);
                      // Görseldeki "Tüm dosyalara erişim" sayfasına yönlendirir
                      if (await Permission.manageExternalStorage.request().isPermanentlyDenied) {
                        openAppSettings();
                      }
                    },
                    child: const Text("Ayarlara Gidin"),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  // Dosyayı diske yazan ana fonksiyon (OPFS uyumlu)
  Future<void> _savePdfToFile(String base64Data, String originalName) async {
    if (_isProcessingAction) return;
    
    setState(() {
      _isProcessingAction = true;
    });

    try {
      // 1. İzinleri Kontrol Et
      PermissionStatus status;
      if (Platform.isAndroid) {
        status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.storage.status;
        }
      } else {
        status = await Permission.storage.status;
      }

      // Eğer izin yoksa görsel diyaloğu göster
      if (!status.isGranted) {
        _showPermissionDialog(base64Data, originalName);
        return;
      }

      // 2. İsimlendirme Mantığı
      String baseFileName;
      String extension;
      if (originalName.contains('.')) {
        int lastDot = originalName.lastIndexOf('.');
        baseFileName = "${originalName.substring(0, lastDot)}_update";
        extension = originalName.substring(lastDot);
      } else {
        baseFileName = "${originalName}_update";
        extension = ".pdf";
      }

      // 3. Klasör Hazırlığı
      final directory = Directory('/storage/emulated/0/Download/PDF Reader');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // 4. Dosya Çakışma Kontrolü
      int counter = 0;
      String finalFileName = "$baseFileName$extension";
      File file = File('${directory.path}/$finalFileName');

      while (await file.exists()) {
        counter++;
        finalFileName = "$baseFileName($counter)$extension";
        file = File('${directory.path}/$finalFileName');
      }

      // 5. Yazma İşlemi
      final bytes = _decodeBase64(base64Data);
      await file.writeAsBytes(bytes);

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
    } finally {
      setState(() {
        _isProcessingAction = false;
      });
    }
  }

  // OPFS'den indirme (büyük dosyalar için)
  Future<void> _downloadPdfFromOpfs(String pdfName) async {
    if (_isProcessingAction || _opfsPdfData == null) return;
    
    setState(() {
      _isProcessingAction = true;
    });

    try {
      await _savePdfToFile(_opfsPdfData!, pdfName);
    } catch (e) {
      debugPrint("OPFS indirme hatası: $e");
    } finally {
      setState(() {
        _isProcessingAction = false;
      });
    }
  }

  // Viewer'dan index'e geri dönme fonksiyonu (OPFS uyumlu)
  Future<bool> _goBackFromViewer() async {
    if (_isViewerOpen && webViewController != null) {
      try {
        // Viewer'ı temizlemek için JavaScript çalıştır
        await webViewController!.evaluateJavascript(source: """
          try {
            // Blob URL'leri temizle
            const blobUrl = sessionStorage.getItem('currentPdfBlobUrl');
            if (blobUrl) {
              URL.revokeObjectURL(blobUrl);
              sessionStorage.removeItem('currentPdfBlobUrl');
            }
            
            // PDF viewer'ı kapat
            if (window.PDFViewerApplication) {
              try {
                PDFViewerApplication.close();
              } catch (e) {
                console.log("PDF viewer kapatılamadı:", e);
              }
            }
            
            // OPFS temizleme
            if (sessionStorage.getItem('usingOPFS') === 'true') {
              console.log("OPFS modunda viewer kapatılıyor...");
            }
            
            console.log("Viewer temizlendi, index.html'ye yönlendiriliyor...");
          } catch (error) {
            console.error("Viewer temizleme hatası:", error);
          }
        """);
        
        // OPFS verilerini temizle
        setState(() {
          _opfsPdfData = null;
          _opfsPdfName = null;
          _isOpfsMode = false;
        });
        
        // Index.html'ye yönlendir
        await webViewController!.loadUrl(
          urlRequest: URLRequest(
            url: WebUri("file:///android_asset/flutter_assets/assets/web/index.html"),
          ),
        );
        
        setState(() {
          _isViewerOpen = false;
          _currentViewerPdfName = null;
        });
        
        return true;
      } catch (e) {
        debugPrint("Viewer'dan çıkış hatası: $e");
      }
    }
    return false;
  }

  // Çift tıklama ile uygulamadan çıkma
  Future<bool> _exitApp() async {
    final now = DateTime.now();
    final isDoubleTap = _lastBackPressTime != null && 
        now.difference(_lastBackPressTime!) < const Duration(seconds: 2);
    
    if (isDoubleTap) {
      // OPFS zamanlayıcısını temizle
      _opfsSyncTimer?.cancel();
      return true;
    } else {
      _lastBackPressTime = now;
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Çıkmak için tekrar basın"),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  // Handler'ları kurmak için JavaScript kodu
  String _getHandlerSetupScript() {
    return """
      // Global değişkenler
      window.flutterHandlers = {
        isInitialized: false,
        isProcessing: false,
        pendingActions: []
      };
      
      // Debounce fonksiyonu
      function createDebouncedHandler(handlerName, wait = 500) {
        let timeout;
        let lastCall = 0;
        
        return function(...args) {
          const now = Date.now();
          
          // Çift tıklamayı önle
          if (now - lastCall < wait) {
            console.log('Çift tıklama önlendi:', handlerName);
            return;
          }
          
          lastCall = now;
          
          clearTimeout(timeout);
          timeout = setTimeout(() => {
            try {
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler(handlerName, ...args);
              }
            } catch (error) {
              console.error('Handler çağrı hatası:', handlerName, error);
            }
          }, wait);
        };
      }
      
      // PDF açma fonksiyonu (OPFS optimize edilmiş)
      window.openPdfFromFlutter = createDebouncedHandler('openPdfViewer');
      
      // Diğer işlemler için handler'lar
      window.sharePdfFromFlutter = createDebouncedHandler('sharePdf');
      window.printPdfFromFlutter = createDebouncedHandler('printPdf');
      window.downloadPdfFromFlutter = createDebouncedHandler('downloadPdf');
      
      // OPFS kontrolü
      window.checkOpfsSupport = async function() {
        try {
          return !!(navigator.storage && navigator.storage.getDirectory);
        } catch {
          return false;
        }
      };
      
      // OPFS'ye kaydetme (büyük dosyalar için)
      window.saveToOpfs = async function(base64Data, fileName) {
        try {
          const hasOpfs = await window.checkOpfsSupport();
          
          if (!hasOpfs) {
            sessionStorage.setItem('usingOPFS', 'false');
            return { success: true, method: 'sessionStorage' };
          }
          
          // OPFS'ye kaydet
          const root = await navigator.storage.getDirectory();
          const pdfDir = await root.getDirectoryHandle('pdfs', { create: true });
          
          // Base64'ten ArrayBuffer'a çevir
          const base64 = base64Data.split(',')[1];
          const binaryString = atob(base64);
          const bytes = new Uint8Array(binaryString.length);
          for (let i = 0; i < binaryString.length; i++) {
            bytes[i] = binaryString.charCodeAt(i);
          }
          
          // Dosyayı kaydet
          const fileHandle = await pdfDir.getFileHandle(fileName, { create: true });
          const writable = await fileHandle.createWritable();
          await writable.write(bytes);
          await writable.close();
          
          // current.pdf olarak da kaydet
          const currentHandle = await pdfDir.getFileHandle('current.pdf', { create: true });
          const currentWritable = await currentHandle.createWritable();
          await currentWritable.write(bytes);
          await currentWritable.close();
          
          sessionStorage.setItem('usingOPFS', 'true');
          return { success: true, method: 'opfs' };
          
        } catch (error) {
          console.error('OPFS kaydetme hatası:', error);
          sessionStorage.setItem('usingOPFS', 'false');
          return { success: false, error: error.toString() };
        }
      };
      
      // Büyük dosya import için OPFS kullanımı
      window.handleLargeFileImport = async function(file, callback) {
        try {
          const hasOpfs = await window.checkOpfsSupport();
          const maxSessionSize = 10 * 1024 * 1024; // 10MB
          
          if (file.size > maxSessionSize && hasOpfs) {
            // Büyük dosya: OPFS kullan
            console.log('Büyük dosya OPFS\'ye kaydediliyor:', file.name, file.size);
            
            const reader = new FileReader();
            
            reader.onload = async function(e) {
              const base64Data = e.target.result;
              const result = await window.saveToOpfs(base64Data, file.name);
              
              if (result.success) {
                // Sadece dosya adını ve OPFS bilgisini gönder
                callback({
                  name: file.name,
                  size: file.size,
                  useOpfs: true,
                  data: null // Büyük veri göndermiyoruz
                });
              } else {
                // OPFS başarısız oldu, küçük parçalara böl
                console.log('OPFS başarısız, parçalara bölünüyor...');
                callback({
                  name: file.name,
                  size: file.size,
                  useOpfs: false,
                  data: base64Data
                });
              }
            };
            
            reader.readAsDataURL(file);
          } else {
            // Küçük dosya: normal base64
            const reader = new FileReader();
            
            reader.onload = function(e) {
              callback({
                name: file.name,
                size: file.size,
                useOpfs: false,
                data: e.target.result
              });
            };
            
            reader.readAsDataURL(file);
          }
        } catch (error) {
          console.error('Dosya import hatası:', error);
          callback({ error: error.toString() });
        }
      };
      
      console.log('Flutter handler\'lar kuruldu, OPFS destekli');
      window.flutterHandlers.isInitialized = true;
    """;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (await _goBackFromViewer()) {
          return false;
        }
        return await _exitApp();
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

              // Handler'ları sadece bir kez kur
              _setupHandlers(controller);
            },
            onLoadStart: (controller, url) async {
              final urlString = url?.toString() ?? '';
              
              setState(() {
                _isViewerOpen = urlString.contains('viewer.html');
                
                if (_isViewerOpen) {
                  // Viewer açıldığında OPFS verisini al
                  final currentName = _currentViewerPdfName ?? 'current.pdf';
                  _retrievePdfFromOpfs(currentName);
                  
                  // OPFS senkronizasyon zamanlayıcısını başlat
                  _startOpfsSyncTimer();
                } else {
                  _currentViewerPdfName = null;
                  _opfsSyncTimer?.cancel();
                }
              });
            },
            onLoadStop: (controller, url) async {
              final urlString = url?.toString() ?? '';
              
              setState(() {
                _isViewerOpen = urlString.contains('viewer.html');
              });
              
              if (urlString.contains('index.html')) {
                setState(() {
                  _isViewerOpen = false;
                  _currentViewerPdfName = null;
                  _opfsPdfData = null;
                  _opfsPdfName = null;
                  _isOpfsMode = false;
                });
                
                // Handler'ları yeniden kur
                controller.evaluateJavascript(source: _getHandlerSetupScript());
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

  // Handler'ları kurma fonksiyonu
  void _setupHandlers(InAppWebViewController controller) {
    // Handler'ları sadece bir kez kurmak için kontrol
    if (_isHandlerRegistered('openPdfViewer')) return;
    
    // JavaScript handler'larını kur
    controller.evaluateJavascript(source: _getHandlerSetupScript());
    
    // PDF açma handler'ı (OPFS uyumlu)
    controller.addJavaScriptHandler(
      handlerName: 'openPdfViewer',
      callback: (args) async {
        if (_isProcessingAction) return;
        
        setState(() {
          _isProcessingAction = true;
        });
        
        try {
          final String base64Data = args[0];
          final String pdfName = args[1];
          final bool useOpfs = args.length > 2 ? args[2] == true : false;
          
          setState(() {
            _currentViewerPdfName = pdfName;
            _isViewerOpen = true;
            
            // Eğer OPFS kullanılmıyorsa, veriyi sakla
            if (!useOpfs && base64Data.isNotEmpty) {
              _opfsPdfData = base64Data;
              _opfsPdfName = pdfName;
              _isOpfsMode = false;
            }
          });
          
          // WebView'de viewer.html'yi aç
          final viewerUrl = "file:///android_asset/flutter_assets/assets/web/viewer.html";
          
          await controller.loadUrl(
            urlRequest: URLRequest(url: WebUri(viewerUrl)),
          );
          
        } catch (e) {
          debugPrint("PDF açma hatası: $e");
        } finally {
          Future.delayed(const Duration(milliseconds: 300), () {
            setState(() {
              _isProcessingAction = false;
            });
          });
        }
      },
    );
    
    // PDF paylaşma handler'ı (OPFS uyumlu)
    controller.addJavaScriptHandler(
      handlerName: 'sharePdf',
      callback: (args) async {
        if (_isProcessingAction) return;
        
        setState(() {
          _isProcessingAction = true;
        });
        
        try {
          String base64Data = args[0];
          final String fileName = args[1];
          
          // Eğer OPFS modundaysak ve veri yoksa, OPFS'den al
          if (_isOpfsMode && base64Data.isEmpty && _opfsPdfData != null) {
            base64Data = _opfsPdfData!;
          }
          
          if (base64Data.isNotEmpty) {
            final bytes = _decodeBase64(base64Data);
            final tempDir = await getTemporaryDirectory();
            final file = File('${tempDir.path}/$fileName');
            await file.writeAsBytes(bytes);
            await Share.shareXFiles([XFile(file.path)], text: fileName);
          }
        } catch (e) {
          debugPrint("Paylaşma Hatası: $e");
        } finally {
          Future.delayed(const Duration(milliseconds: 300), () {
            setState(() {
              _isProcessingAction = false;
            });
          });
        }
      },
    );
    
    // PDF yazdırma handler'ı (OPFS uyumlu)
    controller.addJavaScriptHandler(
      handlerName: 'printPdf',
      callback: (args) async {
        if (_isProcessingAction) return;
        
        setState(() {
          _isProcessingAction = true;
        });
        
        try {
          String base64Data = args[0];
          final String fileName = args[1];
          
          // Eğer OPFS modundaysak ve veri yoksa, OPFS'den al
          if (_isOpfsMode && base64Data.isEmpty && _opfsPdfData != null) {
            base64Data = _opfsPdfData!;
          }
          
          if (base64Data.isNotEmpty) {
            final bytes = _decodeBase64(base64Data);
            await Printing.layoutPdf(onLayout: (format) async => bytes, name: fileName);
          }
        } catch (e) {
          debugPrint("Yazdırma Hatası: $e");
        } finally {
          Future.delayed(const Duration(milliseconds: 300), () {
            setState(() {
              _isProcessingAction = false;
            });
          });
        }
      },
    );
    
    // PDF indirme handler'ı (OPFS uyumlu)
    controller.addJavaScriptHandler(
      handlerName: 'downloadPdf',
      callback: (args) async {
        if (_isProcessingAction) return;
        
        setState(() {
          _isProcessingAction = true;
        });
        
        try {
          String base64Data = args[0];
          final String originalName = args[1];
          final bool useOpfs = args.length > 2 ? args[2] == true : false;
          
          if (useOpfs && _opfsPdfData != null) {
            // OPFS modundaysa kaydedilmiş veriyi kullan
            await _savePdfToFile(_opfsPdfData!, originalName);
          } else if (base64Data.isNotEmpty) {
            // Normal base64 verisi
            await _savePdfToFile(base64Data, originalName);
          }
        } catch (e) {
          debugPrint("İndirme Hatası: $e");
        } finally {
          Future.delayed(const Duration(milliseconds: 300), () {
            setState(() {
              _isProcessingAction = false;
            });
          });
        }
      },
    );
    
    // Büyük dosya import handler'ı
    controller.addJavaScriptHandler(
      handlerName: 'importLargeFile',
      callback: (args) async {
        try {
          final String fileName = args[0];
          final int fileSize = args[1];
          final bool useOpfs = args[2] == true;
          
          debugPrint('Büyük dosya import edildi: $fileName ($fileSize bytes), OPFS: $useOpfs');
          
          // OPFS kullanılıyorsa, dosya adını kaydet
          if (useOpfs) {
            setState(() {
              _opfsPdfName = fileName;
              _isOpfsMode = true;
            });
          }
          
          return {'success': true, 'message': 'Dosya alındı'};
        } catch (e) {
          return {'success': false, 'error': e.toString()};
        }
      },
    );
  }
  
  // OPFS senkronizasyon zamanlayıcısı
  void _startOpfsSyncTimer() {
    _opfsSyncTimer?.cancel();
    
    _opfsSyncTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isViewerOpen && _currentViewerPdfName != null) {
        // Viewer açıkken OPFS verisini periyodik olarak güncelle
        _retrievePdfFromOpfs(_currentViewerPdfName!);
      } else {
        timer.cancel();
      }
    });
  }
  
  // Handler'ın kayıtlı olup olmadığını kontrol et
  bool _isHandlerRegistered(String handlerName) {
    // Basit bir kontrol - gerçek uygulamada daha gelişmiş kontrol gerekir
    return false;
  }

  @override
  void dispose() {
    _opfsSyncTimer?.cancel();
    webViewController?.dispose();
    super.dispose();
  }
}
