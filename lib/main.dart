import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'pdfviewer.dart';

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
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
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

  final InAppWebViewGroupOptions options = InAppWebViewGroupOptions(
    crossPlatform: InAppWebViewOptions(
      useShouldOverrideUrlLoading: true,
      mediaPlaybackRequiresUserGesture: false,
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: true,
      clearCache: false,
      cacheEnabled: true,
      transparentBackground: false,
      supportZoom: false,
      disableVerticalScroll: false,
      disableHorizontalScroll: false,
    ),
    android: AndroidInAppWebViewOptions(
      useHybridComposition: true,
      thirdPartyCookiesEnabled: true,
      allowFileAccess: true,
      allowContentAccess: true,
      databaseEnabled: true,
      domStorageEnabled: true,
    ),
  );

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
  }

  @override
  void dispose() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    final storageStatus = await Permission.storage.status;
    if (!storageStatus.isGranted) {
      await Permission.storage.request();
    }
    
    final manageExternalStorageStatus = await Permission.manageExternalStorage.status;
    if (!manageExternalStorageStatus.isGranted) {
      await Permission.manageExternalStorage.request();
    }
  }

  Future<void> _setupJavaScriptHandlers() async {
    // PDF açma handler'ı
    _webViewController.addJavaScriptHandler(
      handlerName: 'openPDF',
      callback: (args) async {
        if (args.length >= 2 && mounted) {
          final pdfBase64 = args[0];
          final pdfName = args[1];
          
          print('Opening PDF: $pdfName, base64 length: ${pdfBase64.length}');
          
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PDFViewerScreen(
                pdfBase64: pdfBase64,
                pdfName: pdfName,
              ),
            ),
          );
        }
        return null;
      },
    );

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

    // Geri butonu için handler
    _webViewController.addJavaScriptHandler(
      handlerName: 'goBack',
      callback: (args) async {
        if (await _webViewController.canGoBack()) {
          await _webViewController.goBack();
        }
        return null;
      },
    );

    // Toast gösterimi için handler
    _webViewController.addJavaScriptHandler(
      handlerName: 'showToast',
      callback: (args) async {
        if (args.isNotEmpty) {
          final message = args[0];
          _showFlutterToast(message);
        }
        return null;
      },
    );
  }

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

  Future<void> _saveFile(String fileName, String base64Data) async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        final downloadsDir = Directory('${dir.path}/Download');
        if (!downloadsDir.existsSync()) {
          downloadsDir.createSync(recursive: true);
        }

        final filePath = '${downloadsDir.path}/$fileName';
        
        final dataPart = base64Data.contains(',') 
            ? base64Data.split(',').last 
            : base64Data;
        final bytes = base64.decode(dataPart);
        
        await File(filePath).writeAsBytes(bytes);

        _showFlutterToast('Dosya kaydedildi: $fileName');
      }
    } catch (e) {
      print('Save file error: $e');
      _showFlutterToast('Dosya kaydedilemedi');
    }
  }

  Future<void> _shareFile(String fileName, String base64Data) async {
    try {
      final dir = await getTemporaryDirectory();
      final tempPath = '${dir.path}/$fileName';
      
      final dataPart = base64Data.contains(',') 
          ? base64Data.split(',').last 
          : base64Data;
      final bytes = base64.decode(dataPart);
      
      final file = await File(tempPath).writeAsBytes(bytes);

      await _launchFileShareIntent(file.path);
      
      _showFlutterToast('Dosya paylaşılıyor...');
    } catch (e) {
      print('Share file error: $e');
      _showFlutterToast('Dosya paylaşılamadı');
    }
  }

  Future<void> _launchFileShareIntent(String filePath) async {
    final uri = Uri.parse('file://$filePath');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showFlutterToast('Paylaşım uygulaması bulunamadı');
    }
  }

  void _showFlutterToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.grey[800],
      ),
    );
  }

  Widget _buildErrorPage() {
    return Scaffold(
      backgroundColor: Colors.white,
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
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                SystemNavigator.pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[300],
                foregroundColor: Colors.black,
              ),
              child: const Text('Uygulamadan Çık'),
            ),
          ],
        ),
      ),
    );
  }

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
      backgroundColor: Colors.white,
      body: WillPopScope(
        onWillPop: () async {
          if (await _webViewController.canGoBack()) {
            await _webViewController.goBack();
            return false;
          }
          return true;
        },
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.white,
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarColor: Colors.white,
            systemNavigationBarIconBrightness: Brightness.dark,
            systemNavigationBarDividerColor: Colors.transparent,
          ),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top,
                    bottom: MediaQuery.of(context).padding.bottom,
                  ),
                  child: InAppWebView(
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
                      
                      await controller.evaluateJavascript(source: '''
                        // Status bar ve navigation bar için CSS ayarları
                        const style = document.createElement('style');
                        style.textContent = \`
                          :root {
                            --safe-area-top: ${MediaQuery.of(context).padding.top}px;
                            --safe-area-bottom: ${MediaQuery.of(context).padding.bottom}px;
                          }
                          body {
                            padding-top: env(safe-area-inset-top, var(--safe-area-top));
                            padding-bottom: env(safe-area-inset-bottom, var(--safe-area-bottom));
                            background-color: #ffffff;
                          }
                          .top-bar {
                            padding-top: env(safe-area-inset-top, var(--safe-area-top));
                          }
                          .bottom-bar {
                            padding-bottom: env(safe-area-inset-bottom, var(--safe-area-bottom));
                          }
                          .fab-container {
                            bottom: calc(80px + env(safe-area-inset-bottom, var(--safe-area-bottom)));
                          }
                        \`;
                        document.head.appendChild(style);
                        
                        // Flutter ile iletişim için global fonksiyonlar
                        window.flutterHandler = {
                          openPDF: function(pdfBase64, pdfName) {
                            console.log('Opening PDF via Flutter:', pdfName);
                            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                              window.flutter_inappwebview.callHandler('openPDF', pdfBase64, pdfName);
                            } else {
                              console.error('Flutter handler not available');
                            }
                          },
                          openFilePicker: function() {
                            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                              window.flutter_inappwebview.callHandler('openFilePicker');
                            }
                          },
                          saveFile: function(fileName, base64Data) {
                            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                              window.flutter_inappwebview.callHandler('saveFile', fileName, base64Data);
                            }
                          },
                          shareFile: function(fileName, base64Data) {
                            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                              window.flutter_inappwebview.callHandler('shareFile', fileName, base64Data);
                            }
                          },
                          goBack: function() {
                            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                              window.flutter_inappwebview.callHandler('goBack');
                            }
                          },
                          showToast: function(message) {
                            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                              window.flutter_inappwebview.callHandler('showToast', message);
                            }
                          }
                        };
                        
                        // PDF açma fonksiyonunu güncelle
                        window.openPDF = function(pdfBase64, pdfName) {
                          window.flutterHandler.openPDF(pdfBase64, pdfName);
                        };
                        
                        // localStorage desteği için
                        if (typeof window.localStorage === 'undefined') {
                          window.localStorage = {
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
                      
                      // PDF dosyalarını handle et
                      if (uri.toString().endsWith('.pdf')) {
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
                ),

                // Loading Progress Bar
                if (_isLoading)
                  Positioned(
                    top: MediaQuery.of(context).padding.top,
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
          ),
        ),
      ),
    );
  }
}
