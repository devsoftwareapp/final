import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class PDFViewerScreen extends StatefulWidget {
  final String? pdfBase64;
  final String? pdfName;
  
  const PDFViewerScreen({
    super.key,
    required this.pdfBase64,
    this.pdfName = 'PDF',
  });

  @override
  State<PDFViewerScreen> createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends State<PDFViewerScreen> {
  late InAppWebViewController _webViewController;
  double _progress = 0;
  bool _isLoading = true;
  bool _hasError = false;
  bool _pdfLoaded = false;
  String? _tempPdfPath;

  final InAppWebViewGroupOptions options = InAppWebViewGroupOptions(
    crossPlatform: InAppWebViewOptions(
      useShouldOverrideUrlLoading: true,
      mediaPlaybackRequiresUserGesture: false,
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: true,
      clearCache: false,
      cacheEnabled: true,
      transparentBackground: true,
      supportZoom: true,
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
    
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    
    _createTempPDFFile();
  }

  @override
  void dispose() {
    // Temizlik
    _cleanupTempFile();
    
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    super.dispose();
  }

  Future<void> _createTempPDFFile() async {
    if (widget.pdfBase64 == null) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
      return;
    }

    try {
      // Base64'i temizle
      String cleanBase64 = widget.pdfBase64!;
      if (cleanBase64.startsWith('data:application/pdf;base64,')) {
        cleanBase64 = cleanBase64.substring('data:application/pdf;base64,'.length);
      }

      // Base64'i decode et
      final bytes = base64.decode(cleanBase64);
      
      // Geçici dosya oluştur
      final tempDir = await getTemporaryDirectory();
      final fileName = 'temp_${DateTime.now().millisecondsSinceEpoch}.pdf';
      _tempPdfPath = '${tempDir.path}/$fileName';
      
      final file = File(_tempPdfPath!);
      await file.writeAsBytes(bytes);
      
      print('Temp PDF created: $_tempPdfPath, size: ${bytes.length} bytes');
      
    } catch (e) {
      print('Error creating temp PDF: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _cleanupTempFile() async {
    if (_tempPdfPath != null) {
      try {
        final file = File(_tempPdfPath!);
        if (await file.exists()) {
          await file.delete();
          print('Temp PDF deleted: $_tempPdfPath');
        }
      } catch (e) {
        print('Error deleting temp file: $e');
      }
      _tempPdfPath = null;
    }
  }

  Future<void> _setupJavaScriptHandlers() async {
    // PDF yüklendiğinde
    _webViewController.addJavaScriptHandler(
      handlerName: 'onPDFReady',
      callback: (args) async {
        final pdfName = args.isNotEmpty ? args[0] : 'PDF';
        print('PDF is ready: $pdfName');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _pdfLoaded = true;
          });
        }
        return null;
      },
    );

    // Hata durumunda
    _webViewController.addJavaScriptHandler(
      handlerName: 'onPDFError',
      callback: (args) async {
        final error = args.isNotEmpty ? args[0] : 'Unknown error';
        print('PDF error: $error');
        if (mounted) {
          setState(() {
            _hasError = true;
            _isLoading = false;
          });
        }
        return null;
      },
    );
  }

  Future<void> _loadPDF() async {
    if (_tempPdfPath == null) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final assetPath = 'assets/web/viewer.html';
      await _webViewController.loadFile(assetFilePath: assetPath);
    } catch (e) {
      print('Load viewer error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _injectPDFData() async {
    if (_tempPdfPath == null) return;

    try {
      // file:// URL oluştur
      final fileUrl = Uri.file(_tempPdfPath!).toString();
      
      // PDF.js'ye file URL'sini gönder
      await _webViewController.evaluateJavascript(source: '''
        console.log('Injecting PDF file URL:', "$fileUrl");
        
        // PDFViewerApplication hazır olduğunda aç
        const waitForPDFViewer = setInterval(() => {
          if (window.PDFViewerApplication && PDFViewerApplication.initialized) {
            clearInterval(waitForPDFViewer);
            console.log('PDFViewerApplication ready, opening PDF...');
            
            PDFViewerApplication.open({ url: "$fileUrl" });
            
            // PDF yüklendiğinde Flutter'a haber ver
            PDFViewerApplication.eventBus.on("pagesloaded", () => {
              console.log('PDF pages loaded successfully');
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('onPDFReady', "${widget.pdfName?.replaceAll('"', '\\"') ?? 'PDF'}");
              }
            });
            
            // Hata durumunda
            PDFViewerApplication.eventBus.on("error", (error) => {
              console.error('PDF error:', error);
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('onPDFError', error.toString());
              }
            });
          }
        }, 100);
        
        // Timeout
        setTimeout(() => {
          clearInterval(waitForPDFViewer);
          console.warn('PDFViewerApplication initialization timeout');
        }, 10000);
      ''');
      
      print('PDF file URL injected: $fileUrl');
      
    } catch (e) {
      print('Error injecting PDF data: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
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
              'PDF yüklenemedi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.pdfBase64 == null ? 'PDF verisi bulunamadı' : 'PDF verisi bozuk',
              style: const TextStyle(fontSize: 14),
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

  Widget _buildLoadingScreen() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'PDF yükleniyor...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            if (widget.pdfName != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  widget.pdfName!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildErrorPage();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.black,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Stack(
            children: [
              // Ana WebView
              InAppWebView(
                initialOptions: options,
                initialUrlRequest: URLRequest(
                  url: WebUri('about:blank'),
                ),
                onWebViewCreated: (controller) async {
                  _webViewController = controller;
                  await _setupJavaScriptHandlers();
                  await _loadPDF();
                },
                onLoadStart: (controller, url) {
                  if (mounted) {
                    setState(() {
                      _isLoading = true;
                      _pdfLoaded = false;
                    });
                  }
                },
                onLoadStop: (controller, url) async {
                  print('Viewer loaded, injecting PDF data...');
                  await _injectPDFData();
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
                  // Harici linkleri engelle
                  return NavigationActionPolicy.CANCEL;
                },
                onConsoleMessage: (controller, consoleMessage) {
                  print('Console: ${consoleMessage.message}');
                },
              ),

              // Loading Overlay
              if (_isLoading && !_pdfLoaded)
                _buildLoadingScreen(),

              // Geri butonu
              if (!_isLoading || _pdfLoaded)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 8,
                  child: GestureDetector(
                    onTap: () {
                      if (mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),

              // PDF başlığı
              if (_pdfLoaded && widget.pdfName != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 60,
                  right: 60,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.pdfName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

              // Progress Bar
              if (_isLoading && _progress < 1.0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.blue,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
