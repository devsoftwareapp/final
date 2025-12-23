import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

class PDFViewerScreen extends StatefulWidget {
  final String? pdfBase64;
  final String? pdfName;
  
  const PDFViewerScreen({
    super.key,
    this.pdfBase64,
    this.pdfName,
  });

  @override
  State<PDFViewerScreen> createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends State<PDFViewerScreen> {
  late InAppWebViewController _webViewController;
  double _progress = 0;
  bool _isLoading = true;
  bool _hasError = false;
  String _currentPdfName = 'PDF';

  // WebView için ayarlar
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
    _currentPdfName = widget.pdfName ?? 'PDF';
    
    // Status bar ve navigation bar ayarları
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
  }

  @override
  void dispose() {
    // Sistem UI'yı varsayılana sıfırla
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    super.dispose();
  }

  // JavaScript handler'ları kur
  Future<void> _setupJavaScriptHandlers() async {
    // Geri butonu için handler
    _webViewController.addJavaScriptHandler(
      handlerName: 'goBack',
      callback: (args) async {
        if (mounted) {
          Navigator.of(context).pop();
        }
        return null;
      },
    );

    // PDF verisi için handler
    _webViewController.addJavaScriptHandler(
      handlerName: 'getPdfData',
      callback: (args) async {
        return widget.pdfBase64;
      },
    );

    // PDF ismi için handler
    _webViewController.addJavaScriptHandler(
      handlerName: 'getPdfName',
      callback: (args) async {
        return _currentPdfName;
      },
    );

    // Dosya kaydetme için handler
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

    // Dosya paylaşma için handler
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

    // Toast mesajı için handler
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

  // Dosya kaydet
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

        // JavaScript'e başarı mesajı gönder
        await _webViewController.evaluateJavascript(source: '''
          if (window.showToast) {
            window.showToast('Dosya kaydedildi: $fileName');
          }
        ''');
        
        // Flutter toast göster
        _showFlutterToast('Dosya kaydedildi: $fileName');
      }
    } catch (e) {
      print('Save file error: $e');
      await _webViewController.evaluateJavascript(source: '''
        if (window.showToast) {
          window.showToast('Dosya kaydedilemedi: $e');
        }
      ''');
      _showFlutterToast('Dosya kaydedilemedi');
    }
  }

  // Dosya paylaş
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

  // Android Intent ile dosya paylaş
  Future<void> _launchFileShareIntent(String filePath) async {
    final uri = Uri.parse('file://$filePath');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showFlutterToast('Paylaşım uygulaması bulunamadı');
    }
  }

  // Flutter toast mesajı göster
  void _showFlutterToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.grey[800],
      ),
    );
  }

  // Hata sayfası
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
              'PDF yüklenemedi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'PDF verisi bulunamadı veya bozuk',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                if (mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Geri Dön'),
            ),
          ],
        ),
      ),
    );
  }

  // WebView yükle
  Future<void> _loadWebView() async {
    try {
      final assetPath = 'assets/web/pdfviewer.html';
      await _webViewController.loadFile(assetFilePath: assetPath);
    } catch (e) {
      print('Load webview error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildErrorPage();
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
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
              // Status bar ve navigation bar padding'i
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
                    if (mounted) {
                      setState(() {
                        _isLoading = true;
                      });
                    }
                  },
                  onLoadStop: (controller, url) async {
                    if (mounted) {
                      setState(() {
                        _isLoading = false;
                      });
                    }
                    
                    // PDF verisini JavaScript'e gönder
                    if (widget.pdfBase64 != null) {
                      await controller.evaluateJavascript(source: '''
                        // PDF verisini localStorage'a kaydet
                        if (window.localStorage) {
                          localStorage.setItem('pdfData', '${widget.pdfBase64?.replaceAll("'", "\\'")}');
                          localStorage.setItem('pdfName', '${_currentPdfName.replaceAll("'", "\\'")}');
                        }
                        
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
                            background-color: #000;
                          }
                          #topbar {
                            padding-top: env(safe-area-inset-top, var(--safe-area-top));
                            height: calc(56px + env(safe-area-inset-top, var(--safe-area-top)));
                          }
                          iframe {
                            height: calc(100vh - 56px - env(safe-area-inset-top, var(--safe-area-top)) - env(safe-area-inset-bottom, var(--safe-area-bottom)));
                          }
                          @media (max-width: 480px) {
                            #topbar {
                              height: calc(48px + env(safe-area-inset-top, var(--safe-area-top)));
                            }
                            iframe {
                              height: calc(100vh - 48px - env(safe-area-inset-top, var(--safe-area-top)) - env(safe-area-inset-bottom, var(--safe-area-bottom)));
                            }
                          }
                        \`;
                        document.head.appendChild(style);
                        
                        // Flutter ile iletişim için global fonksiyonlar
                        window.flutterHandler = {
                          goBack: function() {
                            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                              window.flutter_inappwebview.callHandler('goBack');
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
                          showToast: function(message) {
                            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                              window.flutter_inappwebview.callHandler('showToast', message);
                            }
                          }
                        };
                      ''');
                    }
                  },
                  onProgressChanged: (controller, progress) {
                    if (mounted) {
                      setState(() {
                        _progress = progress / 100;
                      });
                    }
                  },
                  onLoadError: (controller, url, code, message) {
                    print('Load error: $code - $message');
                    if (mounted) {
                      setState(() {
                        _hasError = true;
                        _isLoading = false;
                      });
                    }
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final uri = navigationAction.request.url;
                    
                    if (uri == null) return NavigationActionPolicy.ALLOW;
                    
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
                          'PDF yükleniyor...',
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
      
      // FAB (Geri Butonu)
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16),
        child: FloatingActionButton(
          onPressed: () {
            if (mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Icon(Icons.arrow_back),
          backgroundColor: Theme.of(context).primaryColor,
        ),
      ),
    );
  }
}
