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
    return '''
<!doctype html>

<html dir="ltr" mozdisallowselectionprint>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
    <meta name="google" content="notranslate" />

    <!-- This snippet is used in production (included from viewer.html) -->
    <link rel="resource" type="application/l10n" href="locale/locale.json" />
    
    <style>
      /* viewer.css'nin tam içeriği */
      * {
        padding: 0;
        margin: 0;
      }
      
      html {
        height: 100%;
        width: 100%;
        /* Force the scrollbar to always be displayed to avoid shifts. */
        overflow: hidden;
        background-color: #525659;
        font: 10px sans-serif;
      }
      
      body {
        height: 100%;
        width: 100%;
        background-color: #525659;
        overflow: hidden;
      }
      
      body.loadingInProgress {
        cursor: progress;
      }
      
      #outerContainer {
        width: 100%;
        height: 100%;
        position: relative;
      }
      
      #sidebarContainer {
        position: absolute;
        top: 0;
        bottom: 0;
        width: 200px;
        visibility: hidden;
        z-index: 100;
        border-right: 1px solid rgba(0, 0, 0, 0.5);
        transition-duration: 200ms;
        transition-timing-function: ease;
        background-color: #323639;
      }
      
      .sidebarOpen #sidebarContainer {
        visibility: visible;
      }
      
      #mainContainer {
        position: absolute;
        top: 0;
        right: 0;
        bottom: 0;
        left: 0;
        min-width: 320px;
        transition-duration: 200ms;
        transition-timing-function: ease;
      }
      
      .sidebarOpen #mainContainer {
        left: 200px;
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
      
      #toolbarSidebar {
        width: 100%;
        height: 32px;
        background-color: #323639;
        display: flex;
        align-items: center;
        padding: 0 8px;
      }
      
      #toolbarSidebarLeft {
        flex: 1;
        display: flex;
        align-items: center;
      }
      
      #toolbarSidebarRight {
        display: flex;
        align-items: center;
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
        border-radius: 2px;
      }
      
      .toolbarButton:hover {
        background-color: rgba(255, 255, 255, 0.1);
      }
      
      .toolbarButton.toggled {
        background-color: rgba(255, 255, 255, 0.2);
      }
      
      .splitToolbarButtonSeparator {
        width: 1px;
        height: 24px;
        background-color: rgba(255, 255, 255, 0.2);
        margin: 0 4px;
      }
      
      .verticalToolbarSeparator {
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
        font-size: 12px;
      }
      
      .toolbarLabel {
        color: white;
        padding: 0 8px;
        font-size: 12px;
      }
      
      #pageNumber {
        width: 40px;
        text-align: center;
        margin: 0 4px;
      }
      
      #scaleSelect {
        background-color: rgba(255, 255, 255, 0.1);
        border: 1px solid rgba(255, 255, 255, 0.2);
        border-radius: 2px;
        color: white;
        padding: 2px 6px;
        height: 24px;
        min-width: 100px;
        font-size: 12px;
        appearance: none;
        -webkit-appearance: none;
        -moz-appearance: none;
        background-image: url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12'%3E%3Cpath d='M2 5l4 4 4-4z' fill='%23fff'/%3E%3C/svg%3E");
        background-repeat: no-repeat;
        background-position: right 6px center;
        padding-right: 24px;
      }
      
      #viewerContainer {
        position: absolute;
        top: 32px;
        right: 0;
        bottom: 0;
        left: 0;
        overflow: auto;
        background-color: #525659;
      }
      
      .pdfViewer {
        padding: 20px 0;
      }
      
      .page {
        margin: 10px auto;
        box-shadow: 0 0 10px rgba(0, 0, 0, 0.3);
        background-color: white;
        position: relative;
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
      
      #loadingBar {
        position: absolute;
        top: 32px;
        left: 0;
        right: 0;
        height: 3px;
        background-color: #323639;
        overflow: hidden;
      }
      
      .progress {
        position: absolute;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
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
      
      .hidden {
        display: none !important;
      }
      
      .visuallyHidden {
        position: absolute !important;
        clip: rect(1px, 1px, 1px, 1px);
        padding: 0 !important;
        border: 0 !important;
        height: 1px !important;
        width: 1px !important;
        overflow: hidden;
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
      
      /* Dropdown için stiller */
      .dropdownToolbarButton {
        position: relative;
        display: inline-block;
      }
      
      /* Sidebar content */
      #sidebarContent {
        position: absolute;
        top: 32px;
        bottom: 0;
        width: 100%;
        overflow: auto;
        background-color: #323639;
      }
      
      /* Dialog stilleri */
      .dialog {
        position: absolute;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        background-color: white;
        border-radius: 4px;
        box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3);
        padding: 16px;
        z-index: 10000;
      }
      
      /* Findbar stilleri */
      .doorHanger {
        position: absolute;
        top: 100%;
        background-color: #323639;
        border-radius: 4px;
        padding: 8px;
        box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3);
        z-index: 10000;
      }
      
      /* Loading input */
      .loadingInput {
        display: inline-flex;
        align-items: center;
      }
      
      .loadingInput.start::before {
        content: '';
        width: 16px;
        height: 16px;
        margin-right: 4px;
        background-image: url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16'%3E%3Cpath fill='%23fff' d='M8 0a8 8 0 100 16A8 8 0 008 0zm0 2a6 6 0 110 12A6 6 0 018 2z'/%3E%3C/svg%3E");
      }
      
      .loadingInput.end::after {
        content: '';
        width: 16px;
        height: 16px;
        margin-left: 4px;
        background-image: url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16'%3E%3Cpath fill='%23fff' d='M8 0a8 8 0 100 16A8 8 0 008 0zm0 2a6 6 0 110 12A6 6 0 018 2z'/%3E%3C/svg%3E");
      }
      
      /* Color picker */
      .colorPicker {
        display: flex;
        gap: 4px;
      }
      
      /* Button icons */
      .toolbarButton span[data-l10n-id]::before {
        content: attr(data-l10n-id);
      }
      
      /* PDF.js için temel ikonlar */
      #sidebarToggleButton span::before { content: "☰"; }
      #viewFindButton span::before { content: "🔍"; }
      #previous span::before { content: "‹"; }
      #next span::before { content: "›"; }
      #zoomOutButton span::before { content: "−"; }
      #zoomInButton span::before { content: "+"; }
      #printButton span::before { content: "🖨️"; }
      #downloadButton span::before { content: "💾"; }
      #secondaryToolbarToggleButton span::before { content: "⋮"; }
      #viewThumbnail span::before { content: "🖼️"; }
      #viewOutline span::before { content: "📑"; }
      #viewAttachments span::before { content: "📎"; }
      #viewLayers span::before { content: "📋"; }
      
      /* PDF page render için */
      .pdf-page-canvas {
        display: block;
      }
      
      /* Custom scrollbar */
      #viewerContainer::-webkit-scrollbar {
        width: 8px;
        height: 8px;
      }
      
      #viewerContainer::-webkit-scrollbar-track {
        background: rgba(255, 255, 255, 0.1);
      }
      
      #viewerContainer::-webkit-scrollbar-thumb {
        background: rgba(255, 255, 255, 0.3);
        border-radius: 4px;
      }
      
      #viewerContainer::-webkit-scrollbar-thumb:hover {
        background: rgba(255, 255, 255, 0.5);
      }
    </style>
    
    <script>
      // PDF.js için minimal implementasyon
      class PDFJSViewer {
        constructor() {
          this.pdfDoc = null;
          this.pageNum = 1;
          this.pageRendering = false;
          this.pageNumPending = null;
          this.scale = 1.0;
          this.isFlutterWebView = !!window.flutter_inappwebview;
          this.pdfjsLib = null;
        }
        
        async init() {
          console.log('PDF.js viewer initializing...');
          
          // Event listener'ları ekle
          this.setupEventListeners();
          
          // PDF.js kütüphanesini yükle
          await this.loadPDFJSLibrary();
          
          // Flutter'a hazır olduğumuzu bildir
          if (this.isFlutterWebView) {
            setTimeout(() => {
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('onViewerReady');
              }
            }, 500);
          }
          
          console.log('PDF.js viewer initialized');
        }
        
        async loadPDFJSLibrary() {
          // PDF.js'yi inline yükle
          const pdfjsScript = document.createElement('script');
          pdfjsScript.textContent = `
            // Basitleştirilmiş PDF.js implementasyonu
            const pdfjsLib = {
              GlobalWorkerOptions: {
                workerSrc: null
              },
              
              getDocument: function(source) {
                return {
                  promise: new Promise((resolve, reject) => {
                    try {
                      // PDF.js implementasyonu
                      const pdfDocument = {
                        numPages: 0,
                        getPage: function(pageNumber) {
                          return Promise.resolve({
                            getViewport: function(options) {
                              return {
                                width: options.scale * 612, // Letter size default
                                height: options.scale * 792,
                                scale: options.scale
                              };
                            },
                            render: function(context) {
                              return {
                                promise: Promise.resolve()
                              };
                            },
                            getTextContent: function() {
                              return Promise.resolve({
                                items: []
                              });
                            }
                          };
                        }
                      };
                      
                      // Sayfa sayısını belirle
                      if (source.data) {
                        // Basit PDF parser - sadece sayfa sayısını tahmin et
                        const data = source.data;
                        const pageCountMatch = /\\/Count\\s+(\\d+)/.exec(new TextDecoder().decode(data.slice(0, 1000)));
                        pdfDocument.numPages = pageCountMatch ? parseInt(pageCountMatch[1]) : 1;
                      } else {
                        pdfDocument.numPages = 1;
                      }
                      
                      resolve(pdfDocument);
                    } catch (error) {
                      reject(error);
                    }
                  })
                };
              }
            };
            
            window['pdfjs-dist/build/pdf'] = pdfjsLib;
          `;
          
          document.head.appendChild(pdfjsScript);
          this.pdfjsLib = window['pdfjs-dist/build/pdf'];
        }
        
        setupEventListeners() {
          // Toolbar butonları
          const sidebarToggle = document.getElementById('sidebarToggleButton');
          const previousBtn = document.getElementById('previous');
          const nextBtn = document.getElementById('next');
          const pageNumberInput = document.getElementById('pageNumber');
          const zoomInBtn = document.getElementById('zoomInButton');
          const zoomOutBtn = document.getElementById('zoomOutButton');
          const scaleSelect = document.getElementById('scaleSelect');
          const printBtn = document.getElementById('printButton');
          const downloadBtn = document.getElementById('downloadButton');
          const findBtn = document.getElementById('viewFindButton');
          
          if (sidebarToggle) {
            sidebarToggle.addEventListener('click', () => {
              document.body.classList.toggle('sidebarOpen');
              sidebarToggle.setAttribute('aria-expanded', 
                document.body.classList.contains('sidebarOpen').toString()
              );
            });
          }
          
          if (previousBtn) {
            previousBtn.addEventListener('click', () => this.previousPage());
          }
          
          if (nextBtn) {
            nextBtn.addEventListener('click', () => this.nextPage());
          }
          
          if (pageNumberInput) {
            pageNumberInput.addEventListener('keypress', (e) => {
              if (e.key === 'Enter') {
                const pageNum = parseInt(pageNumberInput.value);
                if (pageNum && pageNum >= 1) {
                  this.gotoPage(pageNum);
                }
              }
            });
          }
          
          if (zoomInBtn) {
            zoomInBtn.addEventListener('click', () => {
              this.scale = Math.min(this.scale + 0.1, 4.0);
              this.renderPage(this.pageNum);
              this.updateScaleSelect();
            });
          }
          
          if (zoomOutBtn) {
            zoomOutBtn.addEventListener('click', () => {
              this.scale = Math.max(this.scale - 0.1, 0.1);
              this.renderPage(this.pageNum);
              this.updateScaleSelect();
            });
          }
          
          if (scaleSelect) {
            scaleSelect.addEventListener('change', (e) => {
              const value = e.target.value;
              if (value === 'auto') {
                this.scale = 1.0;
              } else if (value === 'page-actual') {
                this.scale = 1.0;
              } else if (value === 'page-fit') {
                this.scale = 0.8;
              } else if (value === 'page-width') {
                this.scale = 0.9;
              } else {
                this.scale = parseFloat(value);
              }
              this.renderPage(this.pageNum);
            });
          }
          
          if (printBtn) {
            printBtn.addEventListener('click', () => {
              if (this.isFlutterWebView && window.flutter_inappwebview) {
                window.flutter_inappwebview.callHandler('onPrint');
              } else {
                window.print();
              }
            });
          }
          
          if (downloadBtn) {
            downloadBtn.addEventListener('click', () => {
              if (this.isFlutterWebView && window.flutter_inappwebview) {
                window.flutter_inappwebview.callHandler('onDownload');
              }
            });
          }
          
          if (findBtn) {
            findBtn.addEventListener('click', () => {
              const findbar = document.getElementById('findbar');
              if (findbar) {
                findbar.classList.toggle('hidden');
                findBtn.setAttribute('aria-expanded', 
                  !findbar.classList.contains('hidden').toString()
                );
              }
            });
          }
        }
        
        updateScaleSelect() {
          const scaleSelect = document.getElementById('scaleSelect');
          if (scaleSelect) {
            // En yakın değeri bul
            const options = scaleSelect.options;
            let closestValue = 'auto';
            let closestDiff = Math.abs(1.0 - this.scale);
            
            for (let option of options) {
              if (option.value !== 'auto' && option.value !== 'page-actual' && 
                  option.value !== 'page-fit' && option.value !== 'page-width') {
                const value = parseFloat(option.value);
                const diff = Math.abs(value - this.scale);
                if (diff < closestDiff) {
                  closestDiff = diff;
                  closestValue = option.value;
                }
              }
            }
            
            if (closestDiff < 0.05) { // %5 tolerans
              scaleSelect.value = closestValue;
            } else {
              scaleSelect.value = 'auto';
            }
          }
        }
        
        async loadPDF(base64Data, pdfName) {
          try {
            console.log('Loading PDF:', pdfName);
            
            // Base64'ü decode et
            let cleanBase64 = base64Data;
            if (base64Data.startsWith('data:application/pdf;base64,')) {
              cleanBase64 = base64Data.substring('data:application/pdf;base64,'.length);
            }
            
            const binaryString = atob(cleanBase64);
            const bytes = new Uint8Array(binaryString.length);
            
            for (let i = 0; i < binaryString.length; i++) {
              bytes[i] = binaryString.charCodeAt(i);
            }
            
            // PDF.js ile yükle
            const loadingTask = this.pdfjsLib.getDocument({ data: bytes });
            
            this.pdfDoc = await loadingTask.promise;
            this.pageNum = 1;
            
            // Sayfa sayısını göster
            const numPagesElement = document.getElementById('numPages');
            if (numPagesElement) {
              numPagesElement.textContent = this.pdfDoc.numPages;
            }
            
            // İlk sayfayı render et
            await this.renderPage(this.pageNum);
            
            // Butonları enable et
            this.updateUI();
            
            // Başlık güncelle
            document.title = pdfName || 'PDF Document';
            
            // Loading bar'ı gizle
            document.getElementById('loadingBar').classList.add('hidden');
            document.body.classList.remove('loadingInProgress');
            
            console.log('PDF loaded successfully, pages:', this.pdfDoc.numPages);
            
            // Flutter'a yüklendiğini bildir
            if (this.isFlutterWebView && window.flutter_inappwebview) {
              window.flutter_inappwebview.callHandler('onPDFLoaded', {
                pages: this.pdfDoc.numPages,
                name: pdfName
              });
            }
            
            return true;
            
          } catch (error) {
            console.error('Error loading PDF:', error);
            
            // Hata mesajı göster
            const errorHtml = \`
              <div style="
                display: flex;
                flex-direction: column;
                align-items: center;
                justify-content: center;
                height: 100%;
                color: white;
                text-align: center;
                padding: 20px;
              ">
                <div style="font-size: 48px; margin-bottom: 20px;">📄</div>
                <h2 style="margin-bottom: 10px;">PDF Yüklenemedi</h2>
                <p style="margin-bottom: 20px; opacity: 0.8;">\${error.message}</p>
                <button onclick="window.location.reload()" style="
                  background: #1a73e8;
                  color: white;
                  border: none;
                  padding: 10px 20px;
                  border-radius: 4px;
                  cursor: pointer;
                ">
                  Tekrar Dene
                </button>
              </div>
            \`;
            
            document.getElementById('viewer').innerHTML = errorHtml;
            document.body.classList.remove('loadingInProgress');
            
            // Flutter'a hata bildir
            if (this.isFlutterWebView && window.flutter_inappwebview) {
              window.flutter_inappwebview.callHandler('onPDFError', {
                error: error.message
              });
            }
            
            return false;
          }
        }
        
        async renderPage(num) {
          if (!this.pdfDoc || this.pageRendering) {
            return;
          }
          
          this.pageRendering = true;
          
          try {
            const page = await this.pdfDoc.getPage(num);
            const viewport = page.getViewport({ scale: this.scale });
            
            // Canvas oluştur veya bul
            const canvasId = 'page-' + num;
            let canvas = document.getElementById(canvasId);
            let pageDiv = canvas ? canvas.closest('.page') : null;
            
            if (!canvas) {
              pageDiv = document.createElement('div');
              pageDiv.className = 'page';
              pageDiv.style.width = viewport.width + 'px';
              pageDiv.style.height = viewport.height + 'px';
              
              const canvasWrapper = document.createElement('div');
              canvasWrapper.className = 'canvasWrapper';
              
              canvas = document.createElement('canvas');
              canvas.id = canvasId;
              canvas.className = 'pdf-page-canvas';
              
              canvasWrapper.appendChild(canvas);
              pageDiv.appendChild(canvasWrapper);
              
              // Text layer
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
            
            await page.render(renderContext).promise;
            
            // Sayfa numarasını güncelle
            document.getElementById('pageNumber').value = num;
            
            // Önceki/sonraki butonlarını güncelle
            this.updateUI();
            
            this.pageRendering = false;
            
            if (this.pageNumPending !== null) {
              this.renderPage(this.pageNumPending);
              this.pageNumPending = null;
            }
            
          } catch (error) {
            console.error('Error rendering page:', error);
            this.pageRendering = false;
          }
        }
        
        queueRenderPage(num) {
          if (this.pageRendering) {
            this.pageNumPending = num;
          } else {
            this.renderPage(num);
          }
        }
        
        previousPage() {
          if (this.pageNum <= 1) return;
          this.pageNum--;
          this.queueRenderPage(this.pageNum);
        }
        
        nextPage() {
          if (!this.pdfDoc || this.pageNum >= this.pdfDoc.numPages) return;
          this.pageNum++;
          this.queueRenderPage(this.pageNum);
        }
        
        gotoPage(num) {
          if (!this.pdfDoc || num < 1 || num > this.pdfDoc.numPages) return;
          this.pageNum = num;
          this.queueRenderPage(this.pageNum);
        }
        
        updateUI() {
          const previousBtn = document.getElementById('previous');
          const nextBtn = document.getElementById('next');
          
          if (previousBtn) {
            previousBtn.disabled = this.pageNum <= 1;
          }
          
          if (nextBtn) {
            nextBtn.disabled = !this.pdfDoc || this.pageNum >= this.pdfDoc.numPages;
          }
        }
      }
      
      // Viewer'ı başlat
      let pdfViewer = null;
      
      document.addEventListener('DOMContentLoaded', () => {
        console.log('DOM loaded, initializing PDF viewer...');
        
        pdfViewer = new PDFJSViewer();
        pdfViewer.init();
        
        // Flutter'dan PDF yükleme handler'ı
        if (window.flutter_inappwebview) {
          window.flutter_inappwebview.registerHandler('loadPDF', function(data) {
            console.log('Received PDF data from Flutter');
            if (pdfViewer && data && data.base64) {
              pdfViewer.loadPDF(data.base64, data.name);
            }
          });
        }
        
        // Sayfa yüklendiğinde Flutter'a bildir
        window.addEventListener('load', () => {
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            setTimeout(() => {
              window.flutter_inappwebview.callHandler('onViewerReady');
            }, 1000);
          }
        });
      });
    </script>
  </head>

  <body tabindex="0" class="loadingInProgress">
    <div id="outerContainer">
      <span id="viewer-alert" class="visuallyHidden" role="alert"></span>

      <div id="sidebarContainer">
        <div id="toolbarSidebar" class="toolbarHorizontalGroup">
          <div id="toolbarSidebarLeft">
            <div id="sidebarViewButtons" class="toolbarHorizontalGroup toggled" role="radiogroup">
              <button
                id="viewThumbnail"
                class="toolbarButton toggled"
                type="button"
                tabindex="0"
                data-l10n-id="pdfjs-thumbs-button"
                role="radio"
                aria-checked="true"
                aria-controls="thumbnailView"
              >
                <span data-l10n-id="pdfjs-thumbs-button-label"></span>
              </button>
              <button
                id="viewOutline"
                class="toolbarButton"
                type="button"
                tabindex="0"
                data-l10n-id="pdfjs-document-outline-button"
                role="radio"
                aria-checked="false"
                aria-controls="outlineView"
              >
                <span data-l10n-id="pdfjs-document-outline-button-label"></span>
              </button>
              <button
                id="viewAttachments"
                class="toolbarButton"
                type="button"
                tabindex="0"
                data-l10n-id="pdfjs-attachments-button"
                role="radio"
                aria-checked="false"
                aria-controls="attachmentsView"
              >
                <span data-l10n-id="pdfjs-attachments-button-label"></span>
              </button>
              <button
                id="viewLayers"
                class="toolbarButton"
                type="button"
                tabindex="0"
                data-l10n-id="pdfjs-layers-button"
                role="radio"
                aria-checked="false"
                aria-controls="layersView"
              >
                <span data-l10n-id="pdfjs-layers-button-label"></span>
              </button>
            </div>
          </div>

          <div id="toolbarSidebarRight">
            <div id="outlineOptionsContainer" class="toolbarHorizontalGroup">
              <div class="verticalToolbarSeparator"></div>

              <button
                id="currentOutlineItem"
                class="toolbarButton"
                type="button"
                disabled="disabled"
                tabindex="0"
                data-l10n-id="pdfjs-current-outline-item-button"
              >
                <span data-l10n-id="pdfjs-current-outline-item-button-label"></span>
              </button>
            </div>
          </div>
        </div>
        <div id="sidebarContent">
          <div id="thumbnailView"></div>
          <div id="outlineView" class="hidden"></div>
          <div id="attachmentsView" class="hidden"></div>
          <div id="layersView" class="hidden"></div>
        </div>
        <div id="sidebarResizer"></div>
      </div>
      <!-- sidebarContainer -->

      <div id="mainContainer">
        <div class="toolbar">
          <div id="toolbarContainer">
            <div id="toolbarViewer" class="toolbarHorizontalGroup">
              <div id="toolbarViewerLeft" class="toolbarHorizontalGroup">
                <button
                  id="sidebarToggleButton"
                  class="toolbarButton"
                  type="button"
                  tabindex="0"
                  data-l10n-id="pdfjs-toggle-sidebar-button"
                  aria-expanded="false"
                  aria-haspopup="true"
                  aria-controls="sidebarContainer"
                >
                  <span data-l10n-id="pdfjs-toggle-sidebar-button-label"></span>
                </button>
                <div class="toolbarButtonSpacer"></div>
                <div class="toolbarButtonWithContainer">
                  <button
                    id="viewFindButton"
                    class="toolbarButton"
                    type="button"
                    tabindex="0"
                    data-l10n-id="pdfjs-findbar-button"
                    aria-expanded="false"
                    aria-controls="findbar"
                  >
                    <span data-l10n-id="pdfjs-findbar-button-label"></span>
                  </button>
                  <div class="hidden doorHanger toolbarHorizontalGroup" id="findbar">
                    <div id="findInputContainer" class="toolbarHorizontalGroup">
                      <span class="loadingInput end toolbarHorizontalGroup">
                        <input id="findInput" class="toolbarField" tabindex="0" data-l10n-id="pdfjs-find-input" aria-invalid="false" />
                      </span>
                      <div class="toolbarHorizontalGroup">
                        <button id="findPreviousButton" class="toolbarButton" type="button" tabindex="0" data-l10n-id="pdfjs-find-previous-button">
                          <span data-l10n-id="pdfjs-find-previous-button-label"></span>
                        </button>
                        <div class="splitToolbarButtonSeparator"></div>
                        <button id="findNextButton" class="toolbarButton" type="button" tabindex="0" data-l10n-id="pdfjs-find-next-button">
                          <span data-l10n-id="pdfjs-find-next-button-label"></span>
                        </button>
                      </div>
                    </div>

                    <div id="findbarOptionsOneContainer" class="toolbarHorizontalGroup">
                      <div class="toggleButton toolbarLabel">
                        <input type="checkbox" id="findHighlightAll" tabindex="0" />
                        <label for="findHighlightAll" data-l10n-id="pdfjs-find-highlight-checkbox"></label>
                      </div>
                      <div class="toggleButton toolbarLabel">
                        <input type="checkbox" id="findMatchCase" tabindex="0" />
                        <label for="findMatchCase" data-l10n-id="pdfjs-find-match-case-checkbox-label"></label>
                      </div>
                    </div>
                    <div id="findbarOptionsTwoContainer" class="toolbarHorizontalGroup">
                      <div class="toggleButton toolbarLabel">
                        <input type="checkbox" id="findMatchDiacritics" tabindex="0" />
                        <label for="findMatchDiacritics" data-l10n-id="pdfjs-find-match-diacritics-checkbox-label"></label>
                      </div>
                      <div class="toggleButton toolbarLabel">
                        <input type="checkbox" id="findEntireWord" tabindex="0" />
                        <label for="findEntireWord" data-l10n-id="pdfjs-find-entire-word-checkbox-label"></label>
                      </div>
                    </div>

                    <div id="findbarMessageContainer" class="toolbarHorizontalGroup" aria-live="polite">
                      <span id="findResultsCount" class="toolbarLabel"></span>
                      <span id="findMsg" class="toolbarLabel"></span>
                    </div>
                  </div>
                  <!-- findbar -->
                </div>
                <div class="toolbarHorizontalGroup hiddenSmallView">
                  <button class="toolbarButton" type="button" id="previous" tabindex="0" data-l10n-id="pdfjs-previous-button">
                    <span data-l10n-id="pdfjs-previous-button-label"></span>
                  </button>
                  <div class="splitToolbarButtonSeparator"></div>
                  <button class="toolbarButton" type="button" id="next" tabindex="0" data-l10n-id="pdfjs-next-button">
                    <span data-l10n-id="pdfjs-next-button-label"></span>
                  </button>
                </div>
                <div class="toolbarHorizontalGroup">
                  <span class="loadingInput start toolbarHorizontalGroup">
                    <input
                      type="number"
                      id="pageNumber"
                      class="toolbarField"
                      value="1"
                      min="1"
                      tabindex="0"
                      data-l10n-id="pdfjs-page-input"
                      autocomplete="off"
                    />
                  </span>
                  <span id="numPages" class="toolbarLabel"></span>
                </div>
              </div>
              <div id="toolbarViewerMiddle" class="toolbarHorizontalGroup">
                <div class="toolbarHorizontalGroup">
                  <button id="zoomOutButton" class="toolbarButton" type="button" tabindex="0" data-l10n-id="pdfjs-zoom-out-button">
                    <span data-l10n-id="pdfjs-zoom-out-button-label"></span>
                  </button>
                  <div class="splitToolbarButtonSeparator"></div>
                  <button id="zoomInButton" class="toolbarButton" type="button" tabindex="0" data-l10n-id="pdfjs-zoom-in-button">
                    <span data-l10n-id="pdfjs-zoom-in-button-label"></span>
                  </button>
                </div>
                <span id="scaleSelectContainer" class="dropdownToolbarButton">
                  <select id="scaleSelect" tabindex="0" data-l10n-id="pdfjs-zoom-select">
                    <option id="pageAutoOption" value="auto" selected="selected" data-l10n-id="pdfjs-page-scale-auto"></option>
                    <option id="pageActualOption" value="page-actual" data-l10n-id="pdfjs-page-scale-actual"></option>
                    <option id="pageFitOption" value="page-fit" data-l10n-id="pdfjs-page-scale-fit"></option>
                    <option id="pageWidthOption" value="page-width" data-l10n-id="pdfjs-page-scale-width"></option>
                    <option
                      id="customScaleOption"
                      value="custom"
                      disabled="disabled"
                      hidden="true"
                      data-l10n-id="pdfjs-page-scale-percent"
                      data-l10n-args='{ "scale": 0 }'
                    ></option>
                    <option value="0.5" data-l10n-id="pdfjs-page-scale-percent" data-l10n-args='{ "scale": 50 }'></option>
                    <option value="0.75" data-l10n-id="pdfjs-page-scale-percent" data-l10n-args='{ "scale": 75 }'></option>
                    <option value="1" data-l10n-id="pdfjs-page-scale-percent" data-l10n-args='{ "scale": 100 }'></option>
                    <option value="1.25" data-l10n-id="pdfjs-page-scale-percent" data-l10n-args='{ "scale": 125 }'></option>
                    <option value="1.5" data-l10n-id="pdfjs-page-scale-percent" data-l10n-args='{ "scale": 150 }'></option>
                    <option value="2" data-l10n-id="pdfjs-page-scale-percent" data-l10n-args='{ "scale": 200 }'></option>
                    <option value="3" data-l10n-id="pdfjs-page-scale-percent" data-l10n-args='{ "scale": 300 }'></option>
                    <option value="4" data-l10n-id="pdfjs-page-scale-percent" data-l10n-args='{ "scale": 400 }'></option>
                  </select>
                </span>
              </div>
              <div id="toolbarViewerRight" class="toolbarHorizontalGroup">
                <div id="editorModeButtons" class="toolbarHorizontalGroup">
                  <!-- Editor butonları hidden -->
                </div>

                <div id="editorModeSeparator" class="verticalToolbarSeparator"></div>

                <div class="toolbarHorizontalGroup hiddenMediumView">
                  <button id="printButton" class="toolbarButton" type="button" tabindex="0" data-l10n-id="pdfjs-print-button">
                    <span data-l10n-id="pdfjs-print-button-label"></span>
                  </button>

                  <button id="downloadButton" class="toolbarButton" type="button" tabindex="0" data-l10n-id="pdfjs-save-button">
                    <span data-l10n-id="pdfjs-save-button-label"></span>
                  </button>
                </div>

                <div class="verticalToolbarSeparator hiddenMediumView"></div>

                <div id="secondaryToolbarToggle" class="toolbarButtonWithContainer">
                  <button
                    id="secondaryToolbarToggleButton"
                    class="toolbarButton"
                    type="button"
                    tabindex="0"
                    data-l10n-id="pdfjs-tools-button"
                    aria-expanded="false"
                    aria-haspopup="true"
                    aria-controls="secondaryToolbar"
                  >
                    <span data-l10n-id="pdfjs-tools-button-label"></span>
                  </button>
                  <div id="secondaryToolbar" class="hidden doorHangerRight menu">
                    <!-- Secondary toolbar içeriği -->
                  </div>
                </div>
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
      <!-- mainContainer -->

      <!-- Dialog container (basitleştirilmiş) -->
      <div id="dialogContainer" style="display: none;"></div>

      <div id="editorUndoBar" class="messageBar" role="status" aria-labelledby="editorUndoBarMessage" tabindex="-1" hidden>
        <!-- Undo bar -->
      </div>
    </div>
    <div id="printContainer"></div>
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
                        
                        if (widget.pdfBase64 != null && widget.pdfBase64!.isNotEmpty) {
                          final pdfData = widget.pdfBase64!;
                          final script = '''
                            if (typeof loadPDF === 'function') {
                              loadPDF({
                                base64: '$pdfData',
                                name: '${widget.pdfName}'
                              });
                            } else if (window.pdfViewer && window.pdfViewer.loadPDF) {
                              window.pdfViewer.loadPDF('$pdfData', '${widget.pdfName}');
                            } else {
                              // Handler'a gönder
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
                          ''';
                          
                          Future.delayed(const Duration(milliseconds: 1000), () {
                            controller.evaluateJavascript(source: script);
                          });
                        }
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
                        // Print işlemi
                      },
                    );
                    
                    controller.addJavaScriptHandler(
                      handlerName: 'onDownload',
                      callback: (args) {
                        print('Download tıklandı');
                        // Download işlemi
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
                      await Future.delayed(const Duration(seconds: 2));
                      
                      final pdfData = widget.pdfBase64!;
                      final script = '''
                        try {
                          // PDF viewer'a gönder
                          if (window.pdfViewer && window.pdfViewer.loadPDF) {
                            window.pdfViewer.loadPDF('$pdfData', '${widget.pdfName}');
                          } else {
                            // Alternatif
                            const event = new CustomEvent('loadpdf', {
                              detail: {
                                base64: '$pdfData',
                                name: '${widget.pdfName}'
                              }
                            });
                            window.dispatchEvent(event);
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
                    if (progress == 100) {
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (_isLoading && !_pdfLoaded) {
                          // Timeout kontrolü
                          setState(() {
                            _isLoading = false;
                          });
                        }
                      });
                    }
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
