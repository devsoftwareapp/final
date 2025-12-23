import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert'; // base64Decode için eklendi
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart'; // SystemNavigator için eklendi

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Reader',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late InAppWebViewController _webViewController;
  double _progress = 0;
  bool _isLoading = true;
  bool _hasError = false;

  // WebView için ayarlar - GÜNCEL VERSİYON
  final InAppWebViewGroupOptions options = InAppWebViewGroupOptions(
    crossPlatform: InAppWebViewOptions(
      useShouldOverrideUrlLoading: true,
      mediaPlaybackRequiresUserGesture: false,
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: true,
      clearCache: false,
      cacheEnabled: true,
      transparentBackground: true,
      supportZoom: false,
      disableVerticalScroll: false,
      disableHorizontalScroll: false,
    ),
    android: AndroidInAppWebViewOptions(
      useHybridComposition: true,
      thirdPartyCookiesEnabled: true,
      allowFileAccess: true,
      allowContentAccess: true,
      // NOT: allowFileAccessFromFileURLs ve allowUniversalAccessFromFileURLs 
      // yeni versiyonda desteklenmiyor, kaldırıldı
      databaseEnabled: true,
      domStorageEnabled: true,
    ),
  );

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    // Android için gerekli izinleri kontrol et
    final storageStatus = await Permission.storage.status;
    if (!storageStatus.isGranted) {
      await Permission.storage.request();
    }
    
    final manageExternalStorageStatus = await Permission.manageExternalStorage.status;
    if (!manageExternalStorageStatus.isGranted) {
      await Permission.manageExternalStorage.request();
    }
  }

  // JavaScript handler'ları - DÜZELTİLDİ: await kaldırıldı
  Future<void> _setupJavaScriptHandlers() async {
    // JavaScript ile iletişim için handler ekle
    _webViewController.addJavaScriptHandler(
      handlerName: 'openFilePicker',
      callback: (args) async {
        await _openFilePicker();
        return null;
      },
    );

    _webViewController.addJavaScriptHandler(
      handlerName: 'openExternalUrl',
      callback: (args) async {
        if (args.isNotEmpty) {
          final url = args[0];
          if (await canLaunchUrl(Uri.parse(url))) {
            await launchUrl(Uri.parse(url));
          }
        }
        return null;
      },
    );

    _webViewController.addJavaScriptHandler(
      handlerName: 'getStoragePath',
      callback: (args) async {
        final dir = await getApplicationDocumentsDirectory();
        return dir.path;
      },
    );

    _webViewController.addJavaScriptHandler(
      handlerName: 'saveFile',
      callback: (args) async {
        if (args.length >= 2) {
          final fileName = args[0];
          final base64Data = args[1];
          await _saveFile(fileName, base64Data);
        }
        return null;
      },
    );

    _webViewController.addJavaScriptHandler(
      handlerName: 'shareFile',
      callback: (args) async {
        if (args.length >= 2) {
          final fileName = args[0];
          final base64Data = args[1];
          await _shareFile(fileName, base64Data);
        }
        return null;
      },
    );
  }

  // Dosya seçici aç
  Future<void> _openFilePicker() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = await File(file.path!).readAsBytes();
        final base64 = UriData.fromBytes(bytes).toString();
        
        // JavaScript'e dosya verisini gönder
        await _webViewController.evaluateJavascript(source: '''
          if (window.handleFileSelect) {
            const fileData = {
              name: '${file.name.replaceAll("'", "\\'")}',
              size: ${file.size},
              data: '${base64.replaceAll("'", "\\'")}'
            };
            window.handleFileSelect(fileData);
          }
        ''');
      }
    } catch (e) {
      print('File picker error: $e');
      await _webViewController.evaluateJavascript(source: '''
        if (window.showToast) {
          window.showToast('Dosya seçilemedi: $e');
        }
      ''');
    }
  }

  // Dosya kaydet - DÜZELTİLDİ: base64Decode eklendi
  Future<void> _saveFile(String fileName, String base64Data) async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        final downloadsDir = Directory('${dir.path}/Download');
        if (!downloadsDir.existsSync()) {
          downloadsDir.createSync(recursive: true);
        }

        final filePath = '${downloadsDir.path}/$fileName';
        
        // Base64 verisini decode et
        final dataPart = base64Data.contains(',') 
            ? base64Data.split(',').last 
            : base64Data;
        final bytes = base64.decode(dataPart);
        
        await File(filePath).writeAsBytes(bytes);

        // JavaScript'e başarı mesajı gönder
        await _webViewController.evaluateJavascript(source: '''
          if (window.showToast) {
            window.showToast('Dosya kaydedildi: $fileName');
          }
        ''');
      }
    } catch (e) {
      print('Save file error: $e');
      await _webViewController.evaluateJavascript(source: '''
        if (window.showToast) {
          window.showToast('Dosya kaydedilemedi: $e');
        }
      ''');
    }
  }

  // Dosya paylaş - DÜZELTİLDİ: base64Decode eklendi
  Future<void> _shareFile(String fileName, String base64Data) async {
    try {
      final dir = await getTemporaryDirectory();
      final tempPath = '${dir.path}/$fileName';
      
      // Base64 verisini decode et
      final dataPart = base64Data.contains(',') 
          ? base64Data.split(',').last 
          : base64Data;
      final bytes = base64.decode(dataPart);
      
      final file = await File(tempPath).writeAsBytes(bytes);

      // Intent ile paylaş
      await _launchFileShareIntent(file.path);
    } catch (e) {
      print('Share file error: $e');
      await _webViewController.evaluateJavascript(source: '''
        if (window.showToast) {
          window.showToast('Dosya paylaşılamadı: $e');
        }
      ''');
    }
  }

  // Android Intent ile dosya paylaş
  Future<void> _launchFileShareIntent(String filePath) async {
    final uri = Uri.parse('file://$filePath');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await _webViewController.evaluateJavascript(source: '''
        if (window.showToast) {
          window.showToast('Dosya paylaşılamadı: Uygulama bulunamadı');
        }
      ''');
    }
  }

  // Hata sayfası
  Widget _buildErrorPage() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            const Text(
              'Sayfa yüklenemedi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'İnternet bağlantınızı kontrol edin',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _isLoading = true;
                });
                _loadWebView();
              },
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }

  // WebView yükle
  Future<void> _loadWebView() async {
    try {
      final assetPath = 'assets/web/index.html';
      await _webViewController.loadFile(assetFilePath: assetPath);
    } catch (e) {
      print('Load webview error: $e');
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildErrorPage();
    }

    return Scaffold(
      body: Stack(
        children: [
          // WebView
          InAppWebView(
            initialOptions: options,
            initialUrlRequest: URLRequest(
              url: WebUri('about:blank'),
            ),
            onWebViewCreated: (controller) async {
              _webViewController = controller;
              await _setupJavaScriptHandlers();
              await _loadWebView();
            },
            onLoadStart: (controller, url) {
              setState(() {
                _isLoading = true;
              });
            },
            onLoadStop: (controller, url) async {
              setState(() {
                _isLoading = false;
              });
              
              // LocalStorage desteği için JavaScript enjekte et
              await controller.evaluateJavascript(source: '''
                // LocalStorage desteği
                if (typeof window.localStorage === 'undefined') {
                  window.localStorage = {
                    _data: {},
                    setItem: function(key, value) {
                      this._data[key] = value;
                      try {
                        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                          window.flutter_inappwebview.callHandler('saveToStorage', 'localStorage_' + key, value);
                        }
                      } catch(e) {
                        console.log('Storage save error:', e);
                      }
                    },
                    getItem: function(key) {
                      try {
                        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                          return window.flutter_inappwebview.callHandler('getFromStorage', 'localStorage_' + key) || this._data[key] || null;
                        }
                      } catch(e) {
                        console.log('Storage get error:', e);
                        return this._data[key] || null;
                      }
                    },
                    removeItem: function(key) {
                      delete this._data[key];
                      try {
                        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                          window.flutter_inappwebview.callHandler('removeFromStorage', 'localStorage_' + key);
                        }
                      } catch(e) {
                        console.log('Storage remove error:', e);
                      }
                    },
                    clear: function() {
                      this._data = {};
                    }
                  };
                }
                
                // SessionStorage desteği
                if (typeof window.sessionStorage === 'undefined') {
                  window.sessionStorage = {
                    _data: {},
                    setItem: function(key, value) {
                      this._data[key] = value;
                    },
                    getItem: function(key) {
                      return this._data[key] || null;
                    },
                    removeItem: function(key) {
                      delete this._data[key];
                    },
                    clear: function() {
                      this._data = {};
                    }
                  };
                }
                
                // PDF açma fonksiyonu
                window.openPDF = function(pdfId) {
                  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                    window.flutter_inappwebview.callHandler('openPDF', pdfId);
                  }
                };
              ''');
            },
            onProgressChanged: (controller, progress) {
              setState(() {
                _progress = progress / 100;
              });
            },
            onLoadError: (controller, url, code, message) {
              print('Load error: $code - $message');
              setState(() {
                _hasError = true;
                _isLoading = false;
              });
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              
              if (uri == null) return NavigationActionPolicy.ALLOW;
              
              // PDF dosyalarını doğrudan aç
              if (uri.toString().endsWith('.pdf')) {
                // PDF Viewer'e yönlendir
                if (mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => PDFViewerScreen(pdfUrl: uri.toString()),
                    ),
                  );
                }
                return NavigationActionPolicy.CANCEL;
              }
              
              // Harici URL'leri varsayılan tarayıcıda aç
              if (uri.toString().startsWith('http')) {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                  return NavigationActionPolicy.CANCEL;
                }
              }
              
              return NavigationActionPolicy.ALLOW;
            },
            onConsoleMessage: (controller, consoleMessage) {
              print('Console: ${consoleMessage.message}');
            },
          ),

          // Loading Progress Bar
          if (_isLoading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).primaryColor,
                ),
              ),
            ),

          // Loading Overlay
          if (_isLoading && _progress < 1.0)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Yükleniyor...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      
      // Back Button için geri tuşu kontrolü
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          if (await _webViewController.canGoBack()) {
            await _webViewController.goBack();
          } else {
            // Eğer geri gidilemiyorsa uygulamadan çık
            if (mounted) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Çıkış'),
                  content: const Text('Uygulamadan çıkmak istiyor musunuz?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('İptal'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        // DÜZELTİLDİ: SystemNavigator import edildi
                        SystemNavigator.pop();
                      },
                      child: const Text('Çıkış'),
                    ),
                  ],
                ),
              );
            }
          }
        },
        child: const Icon(Icons.arrow_back),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }
}

// PDF Görüntüleyici Ekranı
class PDFViewerScreen extends StatelessWidget {
  final String pdfUrl;
  
  const PDFViewerScreen({super.key, required this.pdfUrl});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Görüntüleyici'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: InAppWebView(
        initialOptions: InAppWebViewGroupOptions(
          crossPlatform: InAppWebViewOptions(
            javaScriptEnabled: true,
          ),
          android: AndroidInAppWebViewOptions(
            useHybridComposition: true,
          ),
        ),
        initialUrlRequest: URLRequest(url: WebUri(pdfUrl)),
      ),
    );
  }
}
