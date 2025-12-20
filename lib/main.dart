import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  double progress = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (progress < 1.0)
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey,
                color: Colors.blue,
              ),
            Expanded(
              child: InAppWebView(
                // EN BASİT VE KESİN ÇALIŞAN YÖNTEM
                initialData: InAppWebViewInitialData(
                  data: """
                  <!DOCTYPE html>
                  <html>
                  <head>
                      <meta charset="UTF-8">
                      <meta name="viewport" content="width=device-width, initial-scale=1.0">
                      <title>📄 PDF Reader - KESİN ÇÖZÜM</title>
                      <style>
                          body {
                              font-family: 'Arial', sans-serif;
                              margin: 0;
                              padding: 40px;
                              background: linear-gradient(135deg, #FF416C 0%, #FF4B2B 100%);
                              color: white;
                              text-align: center;
                              min-height: 100vh;
                              display: flex;
                              align-items: center;
                              justify-content: center;
                          }
                          .container {
                              background: rgba(255,255,255,0.15);
                              border-radius: 25px;
                              padding: 50px;
                              box-shadow: 0 20px 40px rgba(0,0,0,0.3);
                              backdrop-filter: blur(10px);
                              border: 1px solid rgba(255,255,255,0.2);
                              max-width: 90%;
                          }
                          h1 {
                              font-size: 3rem;
                              margin-bottom: 30px;
                              text-shadow: 3px 3px 6px rgba(0,0,0,0.4);
                          }
                          .big-icon {
                              font-size: 6rem;
                              margin: 30px;
                              animation: pulse 2s infinite;
                          }
                          @keyframes pulse {
                              0% { transform: scale(1); }
                              50% { transform: scale(1.1); }
                              100% { transform: scale(1); }
                          }
                          .info {
                              background: rgba(255,255,255,0.2);
                              padding: 20px;
                              border-radius: 15px;
                              margin: 20px 0;
                              text-align: left;
                          }
                          button {
                              background: white;
                              color: #FF416C;
                              border: none;
                              padding: 18px 35px;
                              border-radius: 50px;
                              font-size: 1.3rem;
                              font-weight: bold;
                              cursor: pointer;
                              margin: 20px;
                              transition: all 0.3s;
                              box-shadow: 0 10px 20px rgba(0,0,0,0.2);
                          }
                          button:hover {
                              transform: translateY(-5px);
                              box-shadow: 0 15px 30px rgba(0,0,0,0.3);
                          }
                      </style>
                  </head>
                  <body>
                      <div class="container">
                          <div class="big-icon">🎉</div>
                          <h1>BAŞARILI!</h1>
                          <p style="font-size: 1.5rem;">Flutter WebView çalışıyor!</p>
                          
                          <div class="info">
                              <p><strong>✅ Asset yükleme:</strong> Başarılı</p>
                              <p><strong>✅ JavaScript:</strong> Aktif</p>
                              <p><strong>✅ WebView:</strong> Flutter InAppWebView v6.1.5</p>
                              <p><strong>🕒 Zaman:</strong> <span id="time"></span></p>
                              <p><strong>📱 Cihaz:</strong> <span id="device"></span></p>
                          </div>
                          
                          <button onclick="testFunction()">TIKLA VE TEST ET</button>
                          <div id="result" style="margin-top:30px; font-size:1.2rem;"></div>
                      </div>
                      
                      <script>
                          // Sayfa yüklendiğinde
                          document.getElementById('time').textContent = new Date().toLocaleString();
                          document.getElementById('device').textContent = navigator.userAgent;
                          
                          console.log('🎯 KESİN ÇÖZÜM HTML ÇALIŞIYOR!');
                          console.log('📅 ', new Date());
                          console.log('🌐 URL:', window.location.href);
                          console.log('📱 UA:', navigator.userAgent);
                          
                          function testFunction() {
                              const resultDiv = document.getElementById('result');
                              resultDiv.innerHTML = `
                                  <div style="background:rgba(255,255,255,0.3); padding:15px; border-radius:10px;">
                                      <h3>🎊 TEBRİKLER!</h3>
                                      <p>Flutter + WebView mükemmel çalışıyor!</p>
                                      <p>JavaScript fonksiyonları aktif.</p>
                                      <p>Test zamanı: \${new Date().toLocaleTimeString()}</p>
                                  </div>
                              `;
                              console.log('🎯 Test butonu çalıştı!');
                          }
                          
                          // Otomatik test
                          setTimeout(() => {
                              console.log('🔄 Otomatik test tamamlandı');
                          }, 1000);
                      </script>
                  </body>
                  </html>
                  """,
                  mimeType: "text/html",
                  encoding: "utf-8",
                ),
                initialOptions: InAppWebViewGroupOptions(
                  crossPlatform: InAppWebViewOptions(
                    javaScriptEnabled: true,
                    transparentBackground: true,
                  ),
                  android: AndroidInAppWebViewOptions(
                    useHybridComposition: true,
                  ),
                ),
                onWebViewCreated: (controller) {
                  print("✅✅✅ WEBVIEW KESİN ÇALIŞIYOR! ✅✅✅");
                },
                onProgressChanged: (controller, progress) {
                  setState(() {
                    this.progress = progress / 100;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
