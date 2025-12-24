import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert'; // Bu satır eklenmeli
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';  // PDF paylaşım için
import 'package:printing/printing.dart';      // PDF yazdırma için
import 'package:open_file/open_file.dart';    // Dosya açma için

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
      supportMultipleWindows: true,
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
    print('Setting up JavaScript handlers...');
    
    // 🔗 PDF paylaşımı handler'ı
    _webViewController.addJavaScriptHandler(
      handlerName: 'sharePDF',
      callback: (args) async {
        if (args.isNotEmpty) {
          try {
            final data = args[0] as Map<String, dynamic>;
            final base64 = data['base64'] as String;
            final fileName = data['fileName'] as String;
            
            print('Sharing PDF: $fileName, base64 length: ${base64.length}');
            
            // Base64 verisini decode et
            final dataPart = base64.contains(',') 
                ? base64.split(',').last 
                : base64;
            final bytes = base64.decode(dataPart);
            
            // Geçici dosya oluştur
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/$fileName');
            await tempFile.writeAsBytes(bytes);
            
            // Paylaş
            await Share.shareXFiles(
              [XFile(tempFile.path, mimeType: 'application/pdf')],
              subject: fileName,
              text: 'PDF dosyası',
            );
            
            _showFlutterToast('PDF paylaşılıyor...');
            
            // Temizlik
            Future.delayed(const Duration(seconds: 5), () {
              tempFile.delete();
            });
            
          } catch (e) {
            print('Share PDF error: $e');
            _showFlutterToast('Paylaşım başarısız: $e');
          }
        }
        return {'success': true};
      },
    );

    // 🖨️ PDF yazdırma handler'ı
    _webViewController.addJavaScriptHandler(
      handlerName: 'printPDF',
      callback: (args) async {
        if (args.isNotEmpty) {
          try {
            final data = args[0] as Map<String, dynamic>;
            final base64 = data['base64'] as String;
            final fileName = data['fileName'] as String;
            
            print('Printing PDF: $fileName');
            
            // Base64 verisini decode et
            final dataPart = base64.contains(',') 
                ? base64.split(',').last 
                : base64;
            final bytes = base64.decode(dataPart);
            
            // Yazdırma işlemi
            await Printing.layoutPdf(
              onLayout: (format) => bytes,
              name: fileName,
            );
            
            _showFlutterToast('PDF yazdırılıyor...');
            
          } catch (e) {
            print('Print PDF error: $e');
            _showFlutterToast('Yazdırma başarısız: $e');
          }
        }
        return {'success': true};
      },
    );

    // 💾 PDF kaydetme handler'ı
    _webViewController.addJavaScriptHandler(
      handlerName: 'savePDF',
      callback: (args) async {
        if (args.isNotEmpty) {
          try {
            final data = args[0] as Map<String, dynamic>;
            final base64 = data['base64'] as String;
            final fileName = data['fileName'] as String;
            
            print('Saving PDF: $fileName');
            
            // Base64 verisini decode et
            final dataPart = base64.contains(',') 
                ? base64.split(',').last 
                : base64;
            final bytes = base64.decode(dataPart);
            
            // Dosya yolu
            final dir = await getExternalStorageDirectory();
            if (dir != null) {
              final downloadsDir = Directory('${dir.path}/Download');
              if (!downloadsDir.existsSync()) {
                downloadsDir.createSync(recursive: true);
              }
              
              final filePath = '${downloadsDir.path}/$fileName';
              final file = File(filePath);
              await file.writeAsBytes(bytes);
              
              _showFlutterToast('PDF kaydedildi: $fileName');
              
              // Kullanıcıya bildir
              if (await file.exists()) {
                await OpenFile.open(filePath);
              }
            } else {
              _showFlutterToast('Dosya kaydedilemedi: Depolama bulunamadı');
            }
            
          } catch (e) {
            print('Save PDF error: $e');
            _showFlutterToast('Kaydetme başarısız: $e');
          }
        }
        return {'success': true};
      },
    );

    // 📱 Genel mesaj handler'ı
    _webViewController.addJavaScriptHandler(
      handlerName: 'webMessage',
      callback: (args) async {
        if (args.isNotEmpty) {
          try {
            final data = args[0] as Map<String, dynamic>;
            final messageType = data['type'] as String;
            final messageData = data['data'] as Map<String, dynamic>?;
            
            print('Received message from web: $messageType');
            
            switch (messageType) {
              case 'APP_READY':
                print('Web app is ready! PDF count: ${messageData?['pdfCount']}');
                _showFlutterToast('PDF Reader hazır');
                break;
                
              case 'PAGE_CHANGED':
                print('Page changed to: ${messageData?['pageId']}');
                break;
                
              case 'TAB_CHANGED':
                print('Tab changed to: ${messageData?['tabIndex']}');
                break;
                
              case 'PDF_ADDED':
                final fileName = messageData?['fileName'];
                final fileSize = messageData?['fileSize'];
                print('PDF added: $fileName ($fileSize)');
                _showFlutterToast('$fileName eklendi');
                break;
                
              case 'THEME_CHANGED':
                print('Theme changed to: ${messageData?['theme']}');
                break;
                
              case 'MENU_ITEM_CLICKED':
                print('Menu item clicked: ${messageData?['itemId']}');
                break;
            }
            
          } catch (e) {
            print('Web message error: $e');
          }
        }
        return {'success': true};
      },
    );

    // 📄 Dosya seçici handler'ı
    _webViewController.addJavaScriptHandler(
      handlerName: 'openFilePicker',
      callback: (args) async {
        await _openFilePicker();
        return {'success': true};
      },
    );

    // 🌐 Harici URL açma handler'ı
    _webViewController.addJavaScriptHandler(
      handlerName: 'openExternalUrl',
      callback: (args) async {
        if (args.isNotEmpty) {
          final url = args[0] as String;
          if (await canLaunchUrl(Uri.parse(url))) {
            await launchUrl(Uri.parse(url));
          }
        }
        return {'success': true};
      },
    );

    // 📍 Storage yolu handler'ı
    _webViewController.addJavaScriptHandler(
      handlerName: 'getStoragePath',
      callback: (args) async {
        final dir = await getApplicationDocumentsDirectory();
        return dir.path;
      },
    );

    // ⬅️ Geri butonu handler'ı
    _webViewController.addJavaScriptHandler(
      handlerName: 'goBack',
      callback: (args) async {
        if (await _webViewController.canGoBack()) {
          await _webViewController.goBack();
        }
        return {'success': true};
      },
    );

    // 💬 Toast mesajı handler'ı
    _webViewController.addJavaScriptHandler(
      handlerName: 'showToast',
      callback: (args) async {
        if (args.isNotEmpty) {
          final message = args[0] as String;
          _showFlutterToast(message);
        }
        return {'success': true};
      },
    );

    // 🧹 Temizlik için ek handler'lar
    _webViewController.addJavaScriptHandler(
      handlerName: 'clearCache',
      callback: (args) async {
        await _webViewController.clearCache();
        return {'success': true};
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
        final base64 = base64Encode(bytes);
        
        print('File picked: ${file.name}, size: ${file.size} bytes');
        
        // JavaScript'e dosya verisini gönder
        await _webViewController.evaluateJavascript(source: '''
          // Web sayfasına dosya verisini gönder
          if (window.postMessage) {
            const fileData = {
              type: 'FROM_FLUTTER',
              action: 'ADD_PDF',
              data: {
                fileName: '${file.name.replaceAll("'", "\\'")}',
                base64: '$base64',
                fileSize: ${file.size}
              }
            };
            window.postMessage(fileData, '*');
          }
        ''');
        
        _showFlutterToast('${file.name} yüklendi');
      }
    } catch (e) {
      print('File picker error: $e');
      _showFlutterToast('Dosya seçilemedi: $e');
    }
  }

  void _showFlutterToast(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.grey[800],
        behavior: SnackBarBehavior.floating,
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
      print('Loading web view from: $assetPath');
      
      await _webViewController.loadFile(assetFilePath: assetPath);
      
      // JavaScript ortamını başlat
      await Future.delayed(const Duration(seconds: 1));
      
      await _webViewController.evaluateJavascript(source: '''
        // Flutter bridge'ı tanıt
        if (!window.flutter_inappwebview) {
          window.flutter_inappwebview = {
            callHandler: function(handlerName, ...args) {
              console.log('Calling Flutter handler:', handlerName, args);
              // Flutter handler çağrılacak
              return new Promise((resolve) => {
                resolve({success: true});
              });
            }
          };
        }
        
        // Web sayfasına Flutter'ın hazır olduğunu bildir
        window.postMessage({
          type: 'FROM_FLUTTER',
          action: 'APP_READY',
          data: { platform: 'flutter' }
        }, '*');
      ''');
      
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
          
          // WebView'da geri gidilemiyorsa çıkış sorma
          final shouldExit = await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Çıkış'),
              content: const Text('Uygulamadan çıkmak istediğinize emin misiniz?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('HAYIR'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('EVET'),
                ),
              ],
            ),
          );
          
          return shouldExit ?? false;
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
                      print('WebView created');
                      
                      // Handler'ları kur
                      await Future.delayed(const Duration(milliseconds: 500));
                      await _setupJavaScriptHandlers();
                      
                      // Web sayfasını yükle
                      await _loadWebView();
                    },
                    onLoadStart: (controller, url) {
                      setState(() {
                        _isLoading = true;
                      });
                      print('Load started: $url');
                    },
                    onLoadStop: (controller, url) async {
                      setState(() {
                        _isLoading = false;
                      });
                      print('Load stopped: $url');
                      
                      // JavaScript ortamını hazırla
                      await Future.delayed(const Duration(milliseconds: 100));
                      
                      await controller.evaluateJavascript(source: '''
                        // Safe area için CSS ayarları
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
                          .pdf-viewer-modal {
                            padding-top: env(safe-area-inset-top, var(--safe-area-top));
                          }
                        \`;
                        document.head.appendChild(style);
                        
                        // Flutter handler'larını globalleştir
                        if (!window.flutter_inappwebview) {
                          window.flutter_inappwebview = {
                            callHandler: function(handlerName, ...args) {
                              console.log('Flutter handler called:', handlerName, args);
                              
                              // Gerçek Flutter handler'ını çağır
                              if (window.flutter_inappwebview && 
                                  window.flutter_inappwebview.callHandler) {
                                return window.flutter_inappwebview.callHandler(handlerName, ...args);
                              }
                              
                              return Promise.resolve({success: false});
                            }
                          };
                        }
                        
                        // Flutter'dan mesajları dinle
                        window.addEventListener('message', function(event) {
                          if (event.data && event.data.type === 'FROM_FLUTTER') {
                            console.log('Message from Flutter:', event.data);
                            
                            // Web sayfasının kendi mesaj handler'ını çağır
                            if (window.handleFlutterMessage) {
                              window.handleFlutterMessage(event.data);
                            }
                          }
                        });
                        
                        console.log('Flutter environment ready');
                      ''');
                    },
                    onProgressChanged: (controller, progress) {
                      setState(() {
                        _progress = progress / 100;
                      });
                      if (progress == 100) {
                        print('WebView loaded completely');
                      }
                    },
                    onLoadError: (controller, url, code, message) {
                      print('Load error: $code - $message for URL: $url');
                      setState(() {
                        _hasError = true;
                        _isLoading = false;
                      });
                    },
                    shouldOverrideUrlLoading: (controller, navigationAction) async {
                      final uri = navigationAction.request.url;
                      
                      if (uri == null) return NavigationActionPolicy.ALLOW;
                      
                      print('URL loading: ${uri.toString()}');
                      
                      // PDF dosyalarını handle et
                      if (uri.toString().toLowerCase().endsWith('.pdf')) {
                        // PDF dosyasını aç
                        try {
                          await controller.loadUrl(urlRequest: URLRequest(url: uri));
                          return NavigationActionPolicy.ALLOW;
                        } catch (e) {
                          print('Error loading PDF: $e');
                        }
                        return NavigationActionPolicy.CANCEL;
                      }
                      
                      // Harici URL'leri varsayılan tarayıcıda aç
                      if (uri.toString().startsWith('http') || 
                          uri.toString().startsWith('https')) {
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                          return NavigationActionPolicy.CANCEL;
                        }
                      }
                      
                      return NavigationActionPolicy.ALLOW;
                    },
                    onConsoleMessage: (controller, consoleMessage) {
                      print('Web Console [${consoleMessage.messageLevel}]: ${consoleMessage.message}');
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
