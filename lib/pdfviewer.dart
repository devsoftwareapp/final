import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:convert';

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
  bool _isLoading = true;
  bool _hasError = false;
  bool _pdfLoaded = false;

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
    ),
    ios: IOSInAppWebViewOptions(
      allowsInlineMediaPlayback: true,
      allowsBackForwardNavigationGestures: true,
      allowsLinkPreview: true,
    ),
  );

  @override
  void initState() {
    super.initState();
    _loadPDF();
  }

  void _loadPDF() {
    if (widget.pdfBase64 == null || widget.pdfBase64!.isEmpty) {
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
      return;
    }
  }

  String _getHTMLContent() {
    // Tam viewer.html içeriğini buraya gömüyorum
    return '''
<!doctype html>
<html dir="ltr" mozdisallowselectionprint>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
  <meta name="google" content="notranslate" />
  
  <link rel="resource" type="application/l10n" href="locale/locale.json" />
  
  <style>
    /* viewer.css'ten temel stiller */
    * {
      padding: 0;
      margin: 0;
    }
    
    html {
      height: 100%;
      width: 100%;
    }
    
    body {
      height: 100%;
      width: 100%;
      background-color: #525659;
      font-family: sans-serif;
    }
    
    #outerContainer {
      width: 100%;
      height: 100%;
      position: relative;
    }
    
    #mainContainer {
      position: absolute;
      top: 0;
      right: 0;
      bottom: 0;
      left: 0;
      min-width: 320px;
    }
    
    .toolbar {
      position: relative;
      left: 0;
      right: 0;
      z-index: 9999;
      cursor: default;
    }
    
    #toolbarContainer {
      width: 100%;
    }
    
    #toolbarViewer {
      height: 32px;
      background-color: #323639;
      display: flex;
      align-items: center;
      padding: 0 8px;
    }
    
    .toolbarHorizontalGroup {
      display: flex;
      align-items: center;
    }
    
    #toolbarViewerLeft {
      flex: 1;
    }
    
    #toolbarViewerMiddle {
      flex: 2;
      justify-content: center;
    }
    
    #toolbarViewerRight {
      flex: 1;
      justify-content: flex-end;
    }
    
    .toolbarButton {
      border: none;
      background: none;
      width: 32px;
      height: 32px;
      color: white;
      cursor: pointer;
    }
    
    .toolbarButton:hover {
      background-color: rgba(255, 255, 255, 0.1);
    }
    
    .splitToolbarButtonSeparator {
      width: 1px;
      height: 24px;
      background-color: rgba(255, 255, 255, 0.2);
      margin: 0 4px;
    }
    
    .toolbarField {
      background-color: rgba(255, 255, 255, 0.1);
      border: 1px solid rgba(255, 255, 255, 0.2);
      border-radius: 2px;
      color: white;
      padding: 2px 6px;
      height: 24px;
    }
    
    .toolbarLabel {
      color: white;
      padding: 0 8px;
      font-size: 12px;
    }
    
    #pageNumber {
      width: 40px;
      text-align: center;
    }
    
    #scaleSelect {
      background-color: rgba(255, 255, 255, 0.1);
      border: 1px solid rgba(255, 255, 255, 0.2);
      border-radius: 2px;
      color: white;
      padding: 2px 6px;
      height: 24px;
      min-width: 100px;
    }
    
    #viewerContainer {
      position: absolute;
      top: 32px;
      right: 0;
      bottom: 0;
      left: 0;
      overflow: auto;
    }
    
    .pdfViewer {
      padding: 20px 0;
    }
    
    .page {
      margin: 10px auto;
      box-shadow: 0 0 10px rgba(0, 0, 0, 0.3);
      background-color: white;
    }
    
    .canvasWrapper {
      overflow: hidden;
    }
    
    .textLayer {
      position: absolute;
      left: 0;
      top: 0;
      right: 0;
      bottom: 0;
      overflow: hidden;
      opacity: 0.2;
      line-height: 1.0;
    }
    
    .textLayer span {
      color: transparent;
      position: absolute;
      white-space: pre;
      cursor: text;
      transform-origin: 0% 0%;
    }
    
    .hidden {
      display: none !important;
    }
    
    .hiddenSmallView {
      display: flex;
    }
    
    .hiddenMediumView {
      display: flex;
    }
    
    @media (max-width: 960px) {
      .hiddenMediumView {
        display: none !important;
      }
    }
    
    @media (max-width: 640px) {
      .hiddenSmallView {
        display: none !important;
      }
    }
  </style>
  
  <style>
    /* PDF.js viewer.mjs için gerekli ek stiller */
    .loadingInput {
      display: inline-flex;
      align-items: center;
    }
    
    .dropdownToolbarButton {
      position: relative;
      display: inline-block;
    }
    
    .doorHanger {
      position: absolute;
      top: 100%;
      background-color: #323639;
      border-radius: 4px;
      padding: 8px;
      box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3);
      z-index: 10000;
    }
    
    .progress {
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      height: 3px;
      background-color: #1a73e8;
      transform-origin: 0 0;
      transform: scaleX(0);
      transition: transform 0.2s;
    }
    
    .glimmer {
      position: absolute;
      top: 0;
      left: 0;
      height: 100%;
      width: 50px;
      background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.4), transparent);
      animation: shimmer 2s infinite;
    }
    
    @keyframes shimmer {
      0% { transform: translateX(-100%); }
      100% { transform: translateX(400%); }
    }
  </style>
</head>

<body tabindex="0">
  <div id="outerContainer">
    <span id="viewer-alert" class="visuallyHidden" role="alert"></span>

    <div id="mainContainer">
      <div class="toolbar">
        <div id="toolbarContainer">
          <div id="toolbarViewer" class="toolbarHorizontalGroup">
            <div id="toolbarViewerLeft" class="toolbarHorizontalGroup">
              <button id="sidebarToggle" class="toolbarButton" title="Toggle Sidebar">
                <span>☰</span>
              </button>
              <div class="toolbarButtonSpacer"></div>
              
              <button id="viewFind" class="toolbarButton" title="Find in document">
                <span>🔍</span>
              </button>
              
              <div class="hiddenSmallView toolbarHorizontalGroup">
                <button id="previous" class="toolbarButton" title="Previous Page">
                  <span>‹</span>
                </button>
                <div class="splitToolbarButtonSeparator"></div>
                <button id="next" class="toolbarButton" title="Next Page">
                  <span>›</span>
                </button>
              </div>
              
              <div class="toolbarHorizontalGroup">
                <span class="toolbarLabel">Page:</span>
                <input type="number" id="pageNumber" class="toolbarField" value="1" min="1" />
                <span id="numPages" class="toolbarLabel">/ 1</span>
              </div>
            </div>
            
            <div id="toolbarViewerMiddle" class="toolbarHorizontalGroup">
              <div class="toolbarHorizontalGroup">
                <button id="zoomOut" class="toolbarButton" title="Zoom Out">
                  <span>-</span>
                </button>
                <div class="splitToolbarButtonSeparator"></div>
                <button id="zoomIn" class="toolbarButton" title="Zoom In">
                  <span>+</span>
                </button>
              </div>
              
              <span id="scaleSelectContainer" class="dropdownToolbarButton">
                <select id="scaleSelect" class="toolbarField">
                  <option value="auto">Auto</option>
                  <option value="page-actual">Actual Size</option>
                  <option value="page-fit">Fit Page</option>
                  <option value="page-width">Fit Width</option>
                  <option value="0.5">50%</option>
                  <option value="0.75">75%</option>
                  <option value="1" selected>100%</option>
                  <option value="1.25">125%</option>
                  <option value="1.5">150%</option>
                  <option value="2">200%</option>
                  <option value="3">300%</option>
                </select>
              </span>
            </div>
            
            <div id="toolbarViewerRight" class="toolbarHorizontalGroup">
              <div class="toolbarHorizontalGroup hiddenMediumView">
                <button id="print" class="toolbarButton" title="Print">
                  <span>🖨️</span>
                </button>
                <button id="download" class="toolbarButton" title="Download">
                  <span>💾</span>
                </button>
              </div>
              
              <button id="secondaryToolbarToggle" class="toolbarButton" title="Tools">
                <span>⋮</span>
              </button>
            </div>
          </div>
          
          <div id="loadingBar">
            <div class="progress">
              <div class="glimmer"></div>
            </div>
          </div>
        </div>
      </div>

      <div id="viewerContainer" tabindex="0">
        <div id="viewer" class="pdfViewer"></div>
      </div>
    </div>
  </div>

  <script>
    // Basitleştirilmiş PDF.js implementasyonu
    (function() {
      const isFlutterWebView = !!window.flutter_inappwebview;
      let pdfDoc = null;
      let pageNum = 1;
      let pageRendering = false;
      let pageNumPending = null;
      let scale = 1.0;
      let canvas = null;
      let ctx = null;
      
      // PDF.js worker'ını yükle
      const pdfjsLib = window['pdfjs-dist/build/pdf'];
      pdfjsLib.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
      
      function initializeViewer() {
        const viewer = document.getElementById('viewer');
        viewer.innerHTML = '';
        
        // Progress bar'ı güncelle
        const progressBar = document.querySelector('.progress');
        
        // Flutter'a hazır olduğumuzu bildir
        if (isFlutterWebView && window.flutter_inappwebview) {
          window.flutter_inappwebview.callHandler('onViewerReady');
        }
        
        // Event listener'ları ekle
        document.getElementById('previous').addEventListener('click', previousPage);
        document.getElementById('next').addEventListener('click', nextPage);
        document.getElementById('pageNumber').addEventListener('keypress', function(e) {
          if (e.key === 'Enter') {
            gotoPage(parseInt(this.value));
          }
        });
        document.getElementById('zoomIn').addEventListener('click', function() {
          scale += 0.1;
          renderPage(pageNum);
        });
        document.getElementById('zoomOut').addEventListener('click', function() {
          if (scale > 0.1) {
            scale -= 0.1;
            renderPage(pageNum);
          }
        });
        document.getElementById('scaleSelect').addEventListener('change', function() {
          scale = parseFloat(this.value);
          renderPage(pageNum);
        });
        
        // Print butonu
        document.getElementById('print').addEventListener('click', function() {
          if (pdfDoc && isFlutterWebView && window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('onPrint');
          } else {
            window.print();
          }
        });
        
        // Download butonu
        document.getElementById('download').addEventListener('click', function() {
          if (isFlutterWebView && window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('onDownload');
          }
        });
        
        console.log('PDF Viewer initialized');
      }
      
      function renderPage(num) {
        if (!pdfDoc) return;
        
        pageRendering = true;
        
        // Progress bar göster
        document.getElementById('loadingBar').classList.remove('hidden');
        
        pdfDoc.getPage(num).then(function(page) {
          const viewport = page.getViewport({ scale: scale });
          
          // Canvas oluştur
          const canvasId = 'page-' + num;
          let canvas = document.getElementById(canvasId);
          
          if (!canvas) {
            const pageDiv = document.createElement('div');
            pageDiv.className = 'page';
            pageDiv.style.width = viewport.width + 'px';
            pageDiv.style.height = viewport.height + 'px';
            pageDiv.style.margin = '10px auto';
            
            const canvasWrapper = document.createElement('div');
            canvasWrapper.className = 'canvasWrapper';
            
            canvas = document.createElement('canvas');
            canvas.id = canvasId;
            canvas.className = 'pdf-page-canvas';
            
            canvasWrapper.appendChild(canvas);
            pageDiv.appendChild(canvasWrapper);
            
            // Text layer için div
            const textLayerDiv = document.createElement('div');
            textLayerDiv.className = 'textLayer';
            pageDiv.appendChild(textLayerDiv);
            
            document.getElementById('viewer').appendChild(pageDiv);
          }
          
          canvas.height = viewport.height;
          canvas.width = viewport.width;
          
          const renderContext = {
            canvasContext: canvas.getContext('2d'),
            viewport: viewport
          };
          
          const renderTask = page.render(renderContext);
          
          renderTask.promise.then(function() {
            pageRendering = false;
            document.getElementById('loadingBar').classList.add('hidden');
            
            if (pageNumPending !== null) {
              renderPage(pageNumPending);
              pageNumPending = null;
            }
            
            // Text layer render
            page.getTextContent().then(function(textContent) {
              const textLayerDiv = canvas.parentNode.nextSibling;
              pdfjsLib.renderTextLayer({
                textContent: textContent,
                container: textLayerDiv,
                viewport: viewport,
                textDivs: []
              });
            });
            
            // Sayfa numarasını güncelle
            document.getElementById('pageNumber').value = num;
            document.getElementById('numPages').textContent = ' / ' + pdfDoc.numPages;
            
            // Önceki/sonraki butonlarını enable/disable et
            document.getElementById('previous').disabled = num <= 1;
            document.getElementById('next').disabled = num >= pdfDoc.numPages;
          });
        }).catch(function(error) {
          console.error('Error rendering page:', error);
          pageRendering = false;
          document.getElementById('loadingBar').classList.add('hidden');
        });
      }
      
      function queueRenderPage(num) {
        if (pageRendering) {
          pageNumPending = num;
        } else {
          renderPage(num);
        }
      }
      
      function previousPage() {
        if (pageNum <= 1) return;
        pageNum--;
        queueRenderPage(pageNum);
      }
      
      function nextPage() {
        if (pageNum >= pdfDoc.numPages) return;
        pageNum++;
        queueRenderPage(pageNum);
      }
      
      function gotoPage(num) {
        if (num < 1 || num > pdfDoc.numPages) return;
        pageNum = num;
        queueRenderPage(pageNum);
      }
      
      // Flutter'dan PDF yükleme handler'ı
      if (isFlutterWebView && window.flutter_inappwebview) {
        window.flutter_inappwebview.registerHandler('loadPDF', function(data) {
          try {
            const pdfBase64 = data.base64;
            const pdfName = data.name || 'Document.pdf';
            
            console.log('Loading PDF from Flutter:', pdfName);
            
            // Base64'ü decode et
            let cleanBase64 = pdfBase64;
            if (pdfBase64.startsWith('data:application/pdf;base64,')) {
              cleanBase64 = pdfBase64.substring('data:application/pdf;base64,'.length);
            }
            
            const binaryString = atob(cleanBase64);
            const bytes = new Uint8Array(binaryString.length);
            
            for (let i = 0; i < binaryString.length; i++) {
              bytes[i] = binaryString.charCodeAt(i);
            }
            
            // PDF'i yükle
            const loadingTask = pdfjsLib.getDocument({ data: bytes });
            
            loadingTask.promise.then(function(pdf) {
              pdfDoc = pdf;
              pageNum = 1;
              
              // Viewer'ı başlat
              initializeViewer();
              
              // İlk sayfayı render et
              renderPage(pageNum);
              
              // Sayfa sayısını güncelle
              document.getElementById('numPages').textContent = ' / ' + pdf.numPages;
              
              console.log('PDF loaded successfully, pages:', pdf.numPages);
              
              // Flutter'a yüklendiğini bildir
              if (window.flutter_inappwebview) {
                window.flutter_inappwebview.callHandler('onPDFLoaded', {
                  pages: pdf.numPages,
                  name: pdfName
                });
              }
              
            }).catch(function(error) {
              console.error('Error loading PDF:', error);
              
              // Flutter'a hata bildir
              if (window.flutter_inappwebview) {
                window.flutter_inappwebview.callHandler('onPDFError', {
                  error: error.message
                });
              }
            });
            
          } catch (error) {
            console.error('Error in loadPDF handler:', error);
          }
        });
      }
      
      // Sayfa yüklendiğinde viewer'ı başlat
      window.addEventListener('DOMContentLoaded', initializeViewer);
      
      // Flutter WebView içindeysek, hazır olduğumuzu bildir
      if (isFlutterWebView && window.flutter_inappwebview) {
        setTimeout(() => {
          window.flutter_inappwebview.callHandler('onViewerReady');
        }, 100);
      }
      
    })();
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pdfName ?? 'PDF Viewer'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _hasError
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'PDF Yüklenemedi',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'PDF verisi boş veya geçersiz',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                InAppWebView(
                  initialData: InAppWebViewInitialData(
                    data: _getHTMLContent(),
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                    baseUrl: WebUri('https://localhost/'),
                  ),
                  initialOptions: options,
                  onWebViewCreated: (controller) {
                    _webViewController = controller;
                    
                    // JavaScript handler'larını kaydet
                    controller.addJavaScriptHandler(
                      handlerName: 'onViewerReady',
                      callback: (args) {
                        print('WebView viewer hazır, PDF yükleniyor...');
                        
                        // PDF verisini WebView'e gönder
                        final pdfData = widget.pdfBase64!;
                        final script = '''
                          if (window.loadPDF) {
                            window.loadPDF({
                              base64: '$pdfData',
                              name: '${widget.pdfName}'
                            });
                          } else {
                            // Alternatif: direkt handler'ı çağır
                            if (window.flutter_inappwebview && window.flutter_inappwebview.handler) {
                              window.flutter_inappwebview.handler.postMessage({
                                handlerName: 'loadPDF',
                                args: [{
                                  base64: '$pdfData',
                                  name: '${widget.pdfName}'
                                }]
                              });
                            }
                          }
                        ''';
                        
                        Future.delayed(const Duration(milliseconds: 500), () {
                          controller.evaluateJavascript(source: script);
                        });
                      },
                    );
                    
                    controller.addJavaScriptHandler(
                      handlerName: 'onPDFLoaded',
                      callback: (args) {
                        print('PDF yüklendi: ${args[0]}');
                        setState(() {
                          _isLoading = false;
                          _pdfLoaded = true;
                        });
                      },
                    );
                    
                    controller.addJavaScriptHandler(
                      handlerName: 'onPDFError',
                      callback: (args) {
                        print('PDF yükleme hatası: ${args[0]}');
                        setState(() {
                          _isLoading = false;
                          _hasError = true;
                        });
                      },
                    );
                    
                    controller.addJavaScriptHandler(
                      handlerName: 'onPrint',
                      callback: (args) {
                        print('Print tıklandı');
                        // Burada print işlemini yapabilirsiniz
                      },
                    );
                    
                    controller.addJavaScriptHandler(
                      handlerName: 'onDownload',
                      callback: (args) {
                        print('Download tıklandı');
                        // PDF'i indirme işlemi
                      },
                    );
                  },
                  onLoadStart: (controller, url) {
                    print('WebView yükleniyor: $url');
                  },
                  onLoadStop: (controller, url) async {
                    print('WebView yüklendi: $url');
                    
                    // PDF.js yüklendikten sonra PDF'i gönder
                    if (widget.pdfBase64 != null && widget.pdfBase64!.isNotEmpty) {
                      await Future.delayed(const Duration(seconds: 1));
                      
                      final pdfData = widget.pdfBase64!;
                      final cleanBase64 = pdfData.startsWith('data:application/pdf;base64,')
                          ? pdfData.substring('data:application/pdf;base64,'.length)
                          : pdfData;
                      
                      final script = '''
                        try {
                          // loadPDF fonksiyonunu çağır
                          if (typeof loadPDF === 'function') {
                            loadPDF({
                              base64: '$pdfData',
                              name: '${widget.pdfName}'
                            });
                          } else {
                            // Alternatif: direkt handler
                            if (window.flutter_inappwebview && window.flutter_inappwebview.handler) {
                              const event = new MessageEvent('message', {
                                data: {
                                  handlerName: 'loadPDF',
                                  args: [{
                                    base64: '$pdfData',
                                    name: '${widget.pdfName}'
                                  }]
                                }
                              });
                              window.dispatchEvent(event);
                            }
                          }
                        } catch(e) {
                          console.error('Error loading PDF:', e);
                        }
                      ''';
                      
                      await controller.evaluateJavascript(source: script);
                    }
                  },
                  onProgressChanged: (controller, progress) {
                    print('WebView yükleme ilerlemesi: $progress%');
                  },
                  onConsoleMessage: (controller, consoleMessage) {
                    print('WebView console: ${consoleMessage.message}');
                  },
                ),
                
                if (_isLoading)
                  Container(
                    color: Colors.black.withOpacity(0.7),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'PDF yükleniyor...',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
