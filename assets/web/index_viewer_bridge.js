// index_viewer_bridge.js - EN BAŞINA EKLEYİN

// Global fonksiyonları tanımla
window.showPage = window.showPage || function(id, el) {
    console.log('Global showPage called:', id);
    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
    document.querySelectorAll('.bottom-tab').forEach(t => t.classList.remove('active'));
    document.getElementById(id)?.classList.add('active');
    if (el) el.classList.add('active');
};

window.setTab = window.setTab || function(index) {
    console.log('Global setTab called:', index);
    const tabs = document.querySelectorAll('.tab');
    const contents = document.querySelectorAll('.tab-content');
    tabs.forEach(t => t.classList.remove('active'));
    contents.forEach(c => c.classList.remove('active'));
    tabs[index]?.classList.add('active');
    contents[index]?.classList.add('active');
};

// Sonra diğer kodlar...

// index_viewer_bridge.js - PDF Viewer ve Index arasında köprü (Flutter + Tarayıcı)
// Hem Flutter inappwebview hem de mobil tarayıcılar için optimize edilmiştir

document.addEventListener('DOMContentLoaded', function() {
  // 📱 Ortam tespiti
  const isFlutterWebView = () => {
    return window.flutter_inappwebview !== undefined || 
           /flutter_inappwebview/i.test(navigator.userAgent);
  };

  const isMobileBrowser = () => /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
  
  // Platform log'u
  console.log(`Platform: ${isFlutterWebView() ? 'Flutter WebView' : 'Mobil Tarayıcı'}`);
  
  // 📦 PDF veri yapısı
  let pdfList = JSON.parse(localStorage.getItem('pdfList')) || [];
  let favorites = JSON.parse(localStorage.getItem('favorites')) || [];
  let pdfFiles = JSON.parse(localStorage.getItem('pdfFiles')) || {};
  
  // 📁 Geçici değişkenler
  let currentContextPDFId = null;
  let currentPDFViewerId = null;
  let drawerOpen = false;
  let fabOpen = false;

  // 🌉 Flutter <-> JavaScript Köprüsü
  const FlutterBridge = {
    // 🔗 Flutter'a PDF paylaşımı için base64 gönder
    sharePDF: function(base64Data, fileName) {
      if (!isFlutterWebView()) return false;
      
      try {
        console.log('Flutter paylaşımı başlatılıyor:', fileName);
        
        // Method 1: callHandler kullanımı (en iyi yöntem)
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('sharePDF', {
            base64: base64Data,
            fileName: fileName,
            timestamp: Date.now()
          });
          showPDFToast('Flutter ile paylaşılıyor...', 2000);
          return true;
        }
        
        // Method 2: postMessage fallback
        window.postMessage({
          type: 'SHARE_PDF',
          base64: base64Data,
          fileName: fileName
        }, '*');
        
        return true;
      } catch (error) {
        console.error('Flutter paylaşım hatası:', error);
        return false;
      }
    },
    
    // 🖨️ Flutter üzerinden yazdırma
    printPDF: function(base64Data, fileName) {
      if (!isFlutterWebView()) return false;
      
      try {
        console.log('Flutter yazdırma başlatılıyor:', fileName);
        
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('printPDF', {
            base64: base64Data,
            fileName: fileName,
            type: 'application/pdf'
          });
          showPDFToast('Flutter ile yazdırılıyor...', 2000);
          return true;
        }
        
        // Fallback
        window.postMessage({
          type: 'PRINT_PDF',
          base64: base64Data,
          fileName: fileName
        }, '*');
        
        return true;
      } catch (error) {
        console.error('Flutter yazdırma hatası:', error);
        return false;
      }
    },
    
    // 💾 Flutter üzerinden dosya kaydetme
    savePDF: function(base64Data, fileName) {
      if (!isFlutterWebView()) return false;
      
      try {
        console.log('Flutter kaydetme başlatılıyor:', fileName);
        
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('savePDF', {
            base64: base64Data,
            fileName: fileName,
            mimeType: 'application/pdf'
          });
          showPDFToast('Flutter ile kaydediliyor...', 2000);
          return true;
        }
        
        window.postMessage({
          type: 'SAVE_PDF',
          base64: base64Data,
          fileName: fileName
        }, '*');
        
        return true;
      } catch (error) {
        console.error('Flutter kaydetme hatası:', error);
        return false;
      }
    },
    
    // 📱 Flutter'a mesaj gönder (genel)
    sendToFlutter: function(messageType, data) {
      if (!isFlutterWebView()) return;
      
      const message = {
        type: messageType,
        data: data,
        timestamp: Date.now(),
        platform: 'web'
      };
      
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('webMessage', message);
      } else {
        window.postMessage(message, '*');
      }
    }
  };

  // 🌐 Tarayıcı (Web) Fonksiyonları
  const BrowserFunctions = {
    // 🔗 Tarayıcıda paylaşım
    sharePDF: function(base64Data, fileName) {
      try {
        const byteCharacters = atob(base64Data);
        const byteNumbers = new Array(byteCharacters.length);
        for (let i = 0; i < byteCharacters.length; i++) {
          byteNumbers[i] = byteCharacters.charCodeAt(i);
        }
        const byteArray = new Uint8Array(byteNumbers);
        const blob = new Blob([byteArray], { type: 'application/pdf' });
        const file = new File([blob], fileName, { type: 'application/pdf' });
        
        // Web Share API (modern tarayıcılar)
        if (navigator.share && navigator.canShare && navigator.canShare({ files: [file] })) {
          navigator.share({
            title: fileName,
            files: [file],
            text: 'PDF dosyası'
          }).then(() => {
            showPDFToast('PDF paylaşıldı', 2000);
          }).catch(error => {
            console.log('Paylaşım iptal edildi veya başarısız:', error);
            this.downloadPDF(base64Data, fileName); // Fallback
          });
        } else {
          // Web Share API desteklenmiyorsa indirme
          this.downloadPDF(base64Data, fileName);
        }
        
        return true;
      } catch (error) {
        console.error('Tarayıcı paylaşım hatası:', error);
        return false;
      }
    },
    
    // 🖨️ Tarayıcıda yazdırma
    printPDF: function(base64Data, fileName) {
      return directPrintPDF(base64Data, fileName);
    },
    
    // 💾 Tarayıcıda kaydetme/indirme
    savePDF: function(base64Data, fileName) {
      this.downloadPDF(base64Data, fileName);
      return true;
    },
    
    // 📥 Tarayıcıda dosya indirme
    downloadPDF: function(base64Data, fileName) {
      try {
        const byteCharacters = atob(base64Data);
        const byteNumbers = new Array(byteCharacters.length);
        for (let i = 0; i < byteCharacters.length; i++) {
          byteNumbers[i] = byteCharacters.charCodeAt(i);
        }
        const byteArray = new Uint8Array(byteNumbers);
        const blob = new Blob([byteArray], { type: 'application/pdf' });
        
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = fileName;
        a.style.display = 'none';
        document.body.appendChild(a);
        a.click();
        
        // Temizlik
        setTimeout(() => {
          URL.revokeObjectURL(url);
          document.body.removeChild(a);
        }, 100);
        
        showPDFToast(`${fileName} indiriliyor...`, 2000);
        return true;
      } catch (error) {
        console.error('İndirme hatası:', error);
        showPDFToast('İndirme başarısız oldu', 3000);
        return false;
      }
    }
  };

  // 🎯 Platforma özel işlemler için birleşik fonksiyon
  const PlatformActions = {
    share: function(base64Data, fileName) {
      return isFlutterWebView() 
        ? FlutterBridge.sharePDF(base64Data, fileName)
        : BrowserFunctions.sharePDF(base64Data, fileName);
    },
    
    print: function(base64Data, fileName) {
      return isFlutterWebView()
        ? FlutterBridge.printPDF(base64Data, fileName)
        : BrowserFunctions.printPDF(base64Data, fileName);
    },
    
    save: function(base64Data, fileName) {
      return isFlutterWebView()
        ? FlutterBridge.savePDF(base64Data, fileName)
        : BrowserFunctions.savePDF(base64Data, fileName);
    }
  };

  // 🖨️ Yazdırma fonksiyonu - GÜNCELLENDİ (DÜZELTİLDİ)
  function directPrintPDF(base64Data, pdfName) {
    console.log('Yazdırma başlatılıyor:', pdfName);
    
    if (!base64Data) {
      showPDFToast('PDF verisi bulunamadı', 3000);
      return false;
    }

    try {
      // Base64 formatını temizle
      let cleanBase64 = base64Data;
      if (base64Data.startsWith("data:application/pdf;base64,")) {
        cleanBase64 = base64Data.split(',')[1];
      }
      
      console.log('Base64 temizlendi, yazdırma hazırlanıyor...');
      
      // Base64'i decode et
      const byteCharacters = atob(cleanBase64);
      const byteNumbers = new Array(byteCharacters.length);
      for (let i = 0; i < byteCharacters.length; i++) {
        byteNumbers[i] = byteCharacters.charCodeAt(i);
      }
      const byteArray = new Uint8Array(byteNumbers);
      const blob = new Blob([byteArray], { type: 'application/pdf' });
      const url = URL.createObjectURL(blob);

      console.log('Blob URL oluşturuldu:', url.substring(0, 50) + '...');

      // Gizli bir iframe oluştur ve PDF'i yükle
      const printFrame = document.createElement('iframe');
      printFrame.style.display = 'none';
      printFrame.style.position = 'fixed';
      printFrame.style.left = '-9999px';
      printFrame.style.top = '-9999px';
      printFrame.style.width = '0';
      printFrame.style.height = '0';
      printFrame.style.border = 'none';
      printFrame.src = url;
      
      // Iframe'i body'e ekle
      document.body.appendChild(printFrame);

      // PDF yüklendiğinde yazdır
      printFrame.onload = function() {
        console.log('PDF iframe yüklendi, yazdırma başlatılıyor...');
        
        try {
          // Yazdırma diyaloğunu aç
          if (printFrame.contentWindow) {
            // Kısa bir bekleme (PDF'in tam yüklenmesi için)
            setTimeout(() => {
              try {
                printFrame.contentWindow.focus();
                printFrame.contentWindow.print();
                
                // Toast mesajı göster
                showPDFToast('Yazdırma başlatıldı', 2000);
                console.log('Yazdırma diyaloğu açıldı');
                
                // Başarılı
                return true;
              } catch (printError) {
                console.error('Yazdırma hatası:', printError);
                showPDFToast('Yazdırma başlatılamadı', 3000);
                return false;
              }
            }, 1000); // 1 saniye bekle
          }
        } catch (error) {
          console.error('Yazdırma işlemi hatası:', error);
          showPDFToast('Yazdırma hatası: ' + error.message, 3000);
          return false;
        }
        
        // Temizlik - 10 saniye sonra
        setTimeout(() => {
          try {
            URL.revokeObjectURL(url);
            if (printFrame.parentNode) {
              printFrame.parentNode.removeChild(printFrame);
            }
            console.log('Yazdırma temizliği yapıldı');
          } catch (cleanupError) {
            console.error('Temizlik hatası:', cleanupError);
          }
        }, 10000);
      };

      // Hata durumu
      printFrame.onerror = function(error) {
        console.error('Iframe yükleme hatası:', error);
        showPDFToast('PDF yazdırma için yüklenemedi', 3000);
        
        // Temizlik
        try {
          URL.revokeObjectURL(url);
          if (printFrame.parentNode) {
            printFrame.parentNode.removeChild(printFrame);
          }
        } catch (cleanupError) {
          console.error('Hata temizliği hatası:', cleanupError);
        }
        return false;
      };

      // Timeout
      setTimeout(() => {
        if (printFrame.parentNode) {
          console.log('Yazdırma timeout oldu');
          showPDFToast('Yazdırma zaman aşımına uğradı', 3000);
          
          try {
            URL.revokeObjectURL(url);
            printFrame.parentNode.removeChild(printFrame);
          } catch (error) {
            console.error('Timeout temizliği hatası:', error);
          }
        }
      }, 30000); // 30 saniye timeout
      
      return true;
      
    } catch (error) {
      console.error('PDF yazdırma hatası:', error);
      showPDFToast('PDF yazdırılırken bir hata oluştu: ' + error.message, 3000);
      return false;
    }
  }

  // 🏠 Ana sayfa fonksiyonları
  window.showPage = function(id, el) {
    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
    document.querySelectorAll('.bottom-tab').forEach(t => t.classList.remove('active'));
    document.getElementById(id).classList.add('active');
    el.classList.add('active');
    
    // Sadece Anasayfa'da FAB'ı göster
    if (id === 'home') {
      document.getElementById('fabContainer').classList.add('active');
    } else {
      document.getElementById('fabContainer').classList.remove('active');
      closeFAB(); // Diğer sayfalara geçince FAB'ı kapat
    }
    
    // Tab içeriklerini güncelle
    updatePDFLists();
    closeContextMenu(); // Sayfa değişince context menu kapat
    
    // Flutter'a sayfa değişikliğini bildir
    if (isFlutterWebView()) {
      FlutterBridge.sendToFlutter('PAGE_CHANGED', { pageId: id });
    }
  };

  window.setTab = function(index) {
    const tabs = document.querySelectorAll('.tab');
    const contents = document.querySelectorAll('.tab-content');
    tabs.forEach(t => t.classList.remove('active'));
    contents.forEach(c => c.classList.remove('active'));
    tabs[index].classList.add('active');
    contents[index].classList.add('active');
    closeContextMenu(); // Tab değişince context menu kapat
    
    // Flutter'a bildir
    if (isFlutterWebView()) {
      FlutterBridge.sendToFlutter('TAB_CHANGED', { tabIndex: index });
    }
  };

  // 📁 Kart yönlendirme fonksiyonu
  window.redirectToPage = function(pageUrl) {
    // Flutter WebView'da ise özel yönlendirme
    if (isFlutterWebView() && window.flutter_inappwebview) {
      FlutterBridge.sendToFlutter('NAVIGATE_TO', { url: pageUrl });
    } else {
      // Normal tarayıcıda
      window.location.href = pageUrl;
    }
  };

  // Swipe fonksiyonu
  let touchstartX = 0;
  let touchendX = 0;
  const swipeArea = document.getElementById('swipe-area');

  if (swipeArea) {
    swipeArea.addEventListener('touchstart', e => {
      touchstartX = e.changedTouches[0].screenX;
    }, {passive: true});

    swipeArea.addEventListener('touchend', e => {
      touchendX = e.changedTouches[0].screenX;
      handleGesture();
    }, {passive: true});
  }

  function handleGesture() {
    const xDiff = touchstartX - touchendX;
    if (Math.abs(xDiff) > 50) {
      const tabs = document.querySelectorAll('.tab');
      let activeIndex = 0;
      tabs.forEach((tab, index) => {
        if (tab.classList.contains('active')) activeIndex = index;
      });
      if (xDiff > 0 && activeIndex < tabs.length - 1) setTab(activeIndex + 1);
      else if (xDiff < 0 && activeIndex > 0) setTab(activeIndex - 1);
    }
  }

  // 📚 Drawer fonksiyonları
  window.toggleDrawer = function() {
    const drawer = document.getElementById('drawerSidebar');
    const overlay = document.getElementById('drawerOverlay');
    
    if (!drawerOpen) {
      drawer.classList.add('active');
      overlay.classList.add('active');
      drawerOpen = true;
    } else {
      closeDrawer();
    }
  };

  function closeDrawer() {
    const drawer = document.getElementById('drawerSidebar');
    const overlay = document.getElementById('drawerOverlay');
    
    drawer.classList.remove('active');
    overlay.classList.remove('active');
    drawerOpen = false;
  }

  // 📂 Alt menü açma/kapama
  window.toggleSubMenu = function(menuId) {
    const submenu = document.getElementById(menuId + 'Submenu');
    const arrow = document.getElementById(menuId + 'Arrow');
    
    if (submenu && submenu.classList.contains('active')) {
      submenu.classList.remove('active');
      if (arrow) arrow.classList.remove('rotated');
    } else {
      // Diğer tüm alt menüleri kapat
      document.querySelectorAll('.drawer-submenu').forEach(sm => sm.classList.remove('active'));
      document.querySelectorAll('.drawer-arrow').forEach(arr => arr.classList.remove('rotated'));
      
      // Seçili olanı aç
      if (submenu) submenu.classList.add('active');
      if (arrow) arrow.classList.add('rotated');
    }
  };

  // 📄 Drawer menü öğesi açma
  window.openDrawerItem = function(itemId) {
    const items = document.querySelectorAll('.drawer-item');
    const subitems = document.querySelectorAll('.drawer-subitem');
    
    items.forEach(item => item.classList.remove('active'));
    subitems.forEach(item => item.classList.remove('active'));
    
    // Drawer'ı kapat
    closeDrawer();
    
    // İlgili sayfayı göster
    let pageId;
    switch(itemId) {
      case 'about':
        pageId = 'about-page';
        break;
      case 'app-language':
        pageId = 'app-language-page';
        break;
      case 'pdf-language':
        pageId = 'pdf-language-page';
        break;
      case 'theme':
        pageId = 'theme-page';
        break;
      case 'privacy':
        pageId = 'privacy-page';
        break;
      case 'help':
        pageId = 'help-page';
        break;
      default:
        pageId = 'home';
    }
    
    // Alt navigasyonu güncelle
    document.querySelectorAll('.bottom-tab').forEach(t => t.classList.remove('active'));
    
    // Sayfayı göster
    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
    const page = document.getElementById(pageId);
    if (page) page.classList.add('active');
    
    // Flutter'a bildir
    if (isFlutterWebView()) {
      FlutterBridge.sendToFlutter('MENU_ITEM_CLICKED', { itemId: itemId });
    }
  };

  // 🎨 Tema seçimi
  window.selectTheme = function(theme) {
    const options = document.querySelectorAll('.theme-option');
    options.forEach(opt => opt.classList.remove('active'));
    
    if (theme === 'device') {
      const option = document.querySelector('.theme-option:nth-child(1)');
      if (option) option.classList.add('active');
    } else if (theme === 'light') {
      const option = document.querySelector('.theme-option:nth-child(2)');
      if (option) option.classList.add('active');
    } else if (theme === 'dark') {
      const option = document.querySelector('.theme-option:nth-child(3)');
      if (option) option.classList.add('active');
    }
    
    // Seçimi localStorage'a kaydet
    localStorage.setItem('selectedTheme', theme);
    
    // Flutter'a bildir
    if (isFlutterWebView()) {
      FlutterBridge.sendToFlutter('THEME_CHANGED', { theme: theme });
    }
  };

  // ➕ FAB Fonksiyonları
  window.toggleFAB = function() {
    const fabMain = document.getElementById('fabMain');
    const fabMenu = document.getElementById('fabMenu');
    const fabOverlay = document.getElementById('fabOverlay');
    
    if (!fabMain || !fabMenu || !fabOverlay) return;
    
    if (!fabOpen) {
      fabMain.classList.add('rotated');
      fabMenu.classList.add('active');
      fabOverlay.classList.add('active');
      fabOpen = true;
    } else {
      closeFAB();
    }
  };

  function closeFAB() {
    const fabMain = document.getElementById('fabMain');
    const fabMenu = document.getElementById('fabMenu');
    const fabOverlay = document.getElementById('fabOverlay');
    
    if (fabMain) fabMain.classList.remove('rotated');
    if (fabMenu) fabMenu.classList.remove('active');
    if (fabOverlay) fabOverlay.classList.remove('active');
    fabOpen = false;
  }

  // 📋 Context Menu Fonksiyonları
  window.showContextMenu = function(event, pdfId) {
    event.stopPropagation();
    event.preventDefault();
    
    currentContextPDFId = pdfId;
    
    const contextMenu = document.getElementById('contextMenu');
    const overlay = document.getElementById('contextMenuOverlay');
    
    if (!contextMenu || !overlay) return;
    
    // Context menüyü tıklanan noktaya yakın bir yere konumlandır
    const rect = event.currentTarget.getBoundingClientRect();
    contextMenu.style.top = rect.bottom + 5 + 'px';
    contextMenu.style.right = window.innerWidth - rect.right + 10 + 'px';
    
    contextMenu.classList.add('active');
    overlay.classList.add('active');
  };

  window.closeContextMenu = function() {
    const contextMenu = document.getElementById('contextMenu');
    const overlay = document.getElementById('contextMenuOverlay');
    
    if (contextMenu) contextMenu.classList.remove('active');
    if (overlay) overlay.classList.remove('active');
    currentContextPDFId = null;
  };

  // 🔄 Context Menu İşlemleri
  window.renamePDF = function() {
    if (!currentContextPDFId) return;
    
    const pdf = pdfList.find(p => p.id === currentContextPDFId);
    if (!pdf) return;
    
    const newName = prompt('Yeni dosya adını girin:', pdf.name);
    if (newName && newName.trim() !== '' && newName !== pdf.name) {
      pdf.name = newName.trim();
      localStorage.setItem('pdfList', JSON.stringify(pdfList));
      updatePDFLists();
      showPDFToast('Dosya adı güncellendi', 2000);
    }
    
    closeContextMenu();
  };

  // 🔗 Paylaşım - Platforma özel
  window.sharePDF = function() {
    if (!currentContextPDFId) return;
    
    const pdf = pdfList.find(p => p.id === currentContextPDFId);
    if (!pdf) return;
    
    const base64Data = pdfFiles[currentContextPDFId];
    if (base64Data) {
      // Platforma özel paylaşım
      PlatformActions.share(base64Data, pdf.name);
    } else {
      showPDFToast('PDF dosyası bulunamadı', 3000);
    }
    
    closeContextMenu();
  };

  // 🖨️ Yazdırma - Platforma özel
  window.printPDF = function() {
    if (!currentContextPDFId) return;
    
    const pdf = pdfList.find(p => p.id === currentContextPDFId);
    if (!pdf) return;
    
    const base64Data = pdfFiles[currentContextPDFId];
    if (base64Data) {
      // Platforma özel yazdırma
      const result = PlatformActions.print(base64Data, pdf.name);
      if (!result) {
        showPDFToast('Yazdırma başlatılamadı', 3000);
      }
    } else {
      showPDFToast('PDF dosyası bulunamadı', 3000);
    }
    
    closeContextMenu();
  };

  // 🗑️ Silme
  window.deletePDF = function() {
    if (!currentContextPDFId) return;
    
    if (confirm('Bu PDF dosyasını silmek istediğinize emin misiniz?')) {
      // PDF'i listeden sil
      const index = pdfList.findIndex(p => p.id === currentContextPDFId);
      if (index !== -1) {
        pdfList.splice(index, 1);
        localStorage.setItem('pdfList', JSON.stringify(pdfList));
      }
      
      // Favorilerden sil
      const favIndex = favorites.indexOf(currentContextPDFId);
      if (favIndex !== -1) {
        favorites.splice(favIndex, 1);
        localStorage.setItem('favorites', JSON.stringify(favorites));
      }
      
      // PDF dosyasını storage'dan sil
      delete pdfFiles[currentContextPDFId];
      localStorage.setItem('pdfFiles', JSON.stringify(pdfFiles));
      
      updatePDFLists();
      showPDFToast('PDF dosyası silindi', 2000);
    }
    
    closeContextMenu();
  };

  // 📁 File Picker Fonksiyonları
  window.openFilePickerModal = function() {
    closeFAB(); // FAB'ı kapat
    const overlay = document.getElementById('filePickerOverlay');
    const modal = document.getElementById('filePickerModal');
    
    if (!overlay || !modal) return;
    
    overlay.classList.add('active');
    modal.classList.add('active');
  };

  window.closeFilePicker = function() {
    const overlay = document.getElementById('filePickerOverlay');
    const modal = document.getElementById('filePickerModal');
    
    if (overlay) overlay.classList.remove('active');
    if (modal) modal.classList.remove('active');
  };

  window.openFilePicker = function() {
    const fileInput = document.getElementById('fileInput');
    if (fileInput) {
      fileInput.click();
      closeFilePicker();
    }
  };

  // 📄 Dosya seçimi işleme
  window.handleFileSelect = function(event) {
    const file = event.target.files[0];
    if (file && file.type === 'application/pdf') {
      const reader = new FileReader();
      
      reader.onload = function(e) {
        const base64 = e.target.result.split(",")[1];
        
        // PDF'i listeye ekle
        addPDF(file.name, file.size, new Date().toISOString(), base64);
        
        // Input'u temizle
        event.target.value = '';
      };
      
      reader.readAsDataURL(file);
    } else {
      alert('Lütfen bir PDF dosyası seçin.');
    }
  };

  // 📋 PDF Yönetimi
  function addPDF(name, size, date, base64Data) {
    const id = Date.now().toString();
    const pdf = {
      id,
      name,
      size: formatFileSize(size),
      date,
      timestamp: new Date().getTime()
    };
    
    pdfList.unshift(pdf); // En başa ekle
    
    // PDF dosyasını sakla
    if (base64Data) {
      pdfFiles[id] = base64Data;
      localStorage.setItem('pdfFiles', JSON.stringify(pdfFiles));
    }
    
    if (pdfList.length > 20) pdfList = pdfList.slice(0, 20); // Son 20'yi tut
    
    localStorage.setItem('pdfList', JSON.stringify(pdfList));
    updatePDFLists();
    
    // Otomatik olarak son kullanılanlar sekmesine geç
    setTab(0);
    
    showPDFToast(`${name} başarıyla eklendi!`, 2000);
    
    // Flutter'a bildir
    if (isFlutterWebView()) {
      FlutterBridge.sendToFlutter('PDF_ADDED', { 
        fileName: name,
        fileSize: pdf.size 
      });
    }
  }

  function formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  window.toggleFavorite = function(pdfId, event) {
    if (event) event.stopPropagation();
    const index = favorites.indexOf(pdfId);
    if (index > -1) {
      favorites.splice(index, 1);
      showPDFToast('Favorilerden çıkarıldı', 1500);
    } else {
      favorites.push(pdfId);
      showPDFToast('Favorilere eklendi', 1500);
    }
    localStorage.setItem('favorites', JSON.stringify(favorites));
    updatePDFLists();
  };

  // 👁️ PDF Viewer Fonksiyonları
  function openPDFViewer(pdfId) {
    // Context menu elementi kontrolü
    const contextMenu = document.getElementById('contextMenu');
    if (contextMenu && contextMenu.classList.contains('active')) {
      return;
    }
    
    // LocalStorage'dan PDF'i bul
    const pdf = pdfList.find(p => p.id === pdfId);
    if (!pdf) {
      alert('PDF bulunamadı');
      return;
    }
    
    currentPDFViewerId = pdfId;
    
    // Başlık ayarla
    const titleElement = document.getElementById('pdfViewerTitle');
    if (titleElement) titleElement.textContent = pdf.name;
    
    // Loading göster
    const loadingOverlay = document.getElementById('pdfLoadingOverlay');
    if (loadingOverlay) {
      loadingOverlay.style.display = 'flex';
    }
    
    // Modal'ı göster
    const viewerModal = document.getElementById('pdfViewerModal');
    if (viewerModal) {
      viewerModal.style.display = 'flex';
      document.body.classList.add('pdf-viewer-open');
    }
    
    // PDF verisini al ve iframe'de aç
    const base64Data = pdfFiles[pdfId];
    if (base64Data) {
      openPDFInIframe(base64Data, pdf.name);
    } else {
      alert('PDF verisi bulunamadı');
      closePDFViewer();
    }
  }

  window.closePDFViewer = function() {
    const viewerModal = document.getElementById('pdfViewerModal');
    if (viewerModal) {
      viewerModal.style.display = 'none';
    }
    document.body.classList.remove('pdf-viewer-open');
    
    // Iframe'i temizle
    const iframe = document.getElementById('pdfViewerIframe');
    if (iframe) {
      iframe.src = 'about:blank';
    }
    
    currentPDFViewerId = null;
  };

  // 📄 PDF Iframe'de açma (GÜNCELLENDİ - URL PARAMETRESİ İLE)
  function openPDFInIframe(base64Data, pdfName) {
    const iframe = document.getElementById('pdfViewerIframe');
    if (!iframe) return;
    
    console.log('Opening PDF in iframe:', pdfName);
    
    // URL parametresi olarak base64'i gönder
    const encodedBase64 = encodeURIComponent(base64Data);
    const viewerUrl = `viewer.html?base64=${encodedBase64}&name=${encodeURIComponent(pdfName)}`;
    
    console.log('Setting iframe src:', viewerUrl.substring(0, 100) + '...');
    
    // Iframe'i yükle
    iframe.src = viewerUrl;
    
    // Iframe yüklendiğinde
    iframe.onload = function() {
      console.log('PDF iframe loaded, sending data via postMessage...');
      
      // Mesaj gönder (backup yöntemi)
      setTimeout(() => {
        iframe.contentWindow.postMessage(
          { 
            type: "pdfData", 
            base64: base64Data, 
            name: pdfName 
          },
          "*"
        );
        
        console.log('PDF data sent to iframe');
      }, 500);
    };
    
    // Viewer'dan gelen mesajları dinle
    function handleViewerMessage(event) {
      // Sadece viewer.html'den gelen mesajları işle
      if (!event.source || event.source !== iframe.contentWindow) return;
      
      console.log('Message from viewer:', event.data?.type);
      
      switch(event.data?.type) {
        case 'VIEWER_READY':
          console.log('Viewer ready');
          break;
          
        case 'PDF_VIEWER_READY':
          console.log('PDF viewer ready:', event.data.fileName);
          
          // Loading'i gizle
          setTimeout(() => {
            const loadingOverlay = document.getElementById('pdfLoadingOverlay');
            if (loadingOverlay) {
              loadingOverlay.style.display = 'none';
            }
            
            showPDFToast('PDF açıldı', 1500);
          }, 500);
          break;
          
        case 'PDF_PAGES_LOADED':
          console.log('PDF pages loaded:', event.data.pageCount);
          break;
          
        case 'PDF_ERROR':
          console.error('PDF error:', event.data.error);
          showPDFToast('PDF açılamadı: ' + event.data.error, 3000);
          
          const loadingOverlay = document.getElementById('pdfLoadingOverlay');
          if (loadingOverlay) {
            loadingOverlay.style.display = 'none';
          }
          break;
          
        case 'PDF_VIEWER_TIMEOUT':
          console.error('PDF viewer timeout');
          showPDFToast('PDF görüntüleyici hazırlanamadı', 3000);
          
          const loading = document.getElementById('pdfLoadingOverlay');
          if (loading) {
            loading.style.display = 'none';
          }
          break;
      }
    }
    
    // Mesaj listener'ını ekle
    window.addEventListener('message', handleViewerMessage);
    
    // 10 saniye sonra listener'ı temizle
    setTimeout(() => {
      window.removeEventListener('message', handleViewerMessage);
    }, 10000);
  }

  // 📄 PDF açma fonksiyonu
  window.openPDF = function(pdfId, event) {
    if (event) event.stopPropagation();
    
    // Context menu elementi kontrolü
    const contextMenu = document.getElementById('contextMenu');
    if (contextMenu && contextMenu.classList.contains('active')) {
      return;
    }
    
    openPDFViewer(pdfId);
  };

  // 💬 Toast mesajı göster
  function showPDFToast(message, duration = 3000) {
    const toast = document.getElementById('pdfToast');
    if (!toast) return;
    
    toast.textContent = message;
    toast.classList.add('show');
    
    setTimeout(() => {
      toast.classList.remove('show');
    }, duration);
  }

  // 📊 Listeleri güncelle
  function updatePDFLists() {
    // Son Kullanılanlar
    const recentList = document.getElementById('recent-pdfs-list');
    if (recentList) {
      recentList.innerHTML = '';
      
      if (pdfList.length === 0) {
        recentList.innerHTML = `
          <div class="empty-state">
            <div class="empty-icon"><span class="material-icons">description</span></div>
            <div class="empty-text">Henüz PDF yüklenmemiş</div>
          </div>
        `;
      } else {
        pdfList.forEach(pdf => {
          const isFavorite = favorites.includes(pdf.id);
          const item = document.createElement('div');
          item.className = 'pdf-item';
          
          // PDF'e tıklanınca direkt açılması için
          item.onclick = (e) => openPDF(pdf.id, e);
          
          item.innerHTML = `
            <div class="pdf-icon">
              <span class="material-icons">picture_as_pdf</span>
            </div>
            <div class="pdf-info">
              <div class="pdf-name">${pdf.name}</div>
              <div class="pdf-meta">${pdf.size} • ${new Date(pdf.date).toLocaleDateString('tr-TR')}</div>
            </div>
            <div class="pdf-actions">
              <div class="favorite-star ${isFavorite ? 'favorited' : ''}" onclick="event && event.stopPropagation(); toggleFavorite('${pdf.id}', event)">
                <span class="material-icons">${isFavorite ? 'star' : 'star_border'}</span>
              </div>
              <div class="more-options" onclick="event && event.stopPropagation(); showContextMenu(event, '${pdf.id}')">
                <span class="material-icons">more_vert</span>
              </div>
            </div>
          `;
          recentList.appendChild(item);
        });
      }
    }
    
    // Favoriler
    const favoriteList = document.getElementById('favorite-pdfs-list');
    if (favoriteList) {
      favoriteList.innerHTML = '';
      
      const favoritePDFs = pdfList.filter(pdf => favorites.includes(pdf.id));
      if (favoritePDFs.length === 0) {
        favoriteList.innerHTML = `
          <div class="empty-state">
            <div class="empty-icon"><span class="material-icons">star</span></div>
            <div class="empty-text">Henüz favori PDF yok</div>
          </div>
        `;
      } else {
        favoritePDFs.forEach(pdf => {
          const item = document.createElement('div');
          item.className = 'pdf-item';
          
          // PDF'e tıklanınca direkt açılması için
          item.onclick = (e) => openPDF(pdf.id, e);
          
          item.innerHTML = `
            <div class="pdf-icon">
              <span class="material-icons">picture_as_pdf</span>
            </div>
            <div class="pdf-info">
              <div class="pdf-name">${pdf.name}</div>
              <div class="pdf-meta">${pdf.size} • ${new Date(pdf.date).toLocaleDateString('tr-TR')}</div>
            </div>
            <div class="pdf-actions">
              <div class="favorite-star favorited" onclick="event && event.stopPropagation(); toggleFavorite('${pdf.id}', event)">
                <span class="material-icons">star</span>
              </div>
              <div class="more-options" onclick="event && event.stopPropagation(); showContextMenu(event, '${pdf.id}')">
                <span class="material-icons">more_vert</span>
              </div>
            </div>
          `;
          favoriteList.appendChild(item);
        });
      }
    }
    
    // Cihazda (simülasyon)
    const deviceList = document.getElementById('device-pdfs-list');
    if (deviceList) {
      deviceList.innerHTML = `
        <div class="empty-state">
          <div class="empty-icon"><span class="material-icons">smartphone</span></div>
          <div class="empty-text">Cihazda henüz PDF bulunmuyor</div>
        </div>
      `;
    }
  }

  // 🔌 Event listeners'ları bağla
  function setupEventListeners() {
    const drawerOverlay = document.getElementById('drawerOverlay');
    const filePickerOverlay = document.getElementById('filePickerOverlay');
    const fabOverlay = document.getElementById('fabOverlay');
    const contextMenuOverlay = document.getElementById('contextMenuOverlay');
    
    if (drawerOverlay) {
      drawerOverlay.addEventListener('click', closeDrawer);
    }
    
    if (filePickerOverlay) {
      filePickerOverlay.addEventListener('click', closeFilePicker);
    }
    
    if (fabOverlay) {
      fabOverlay.addEventListener('click', closeFAB);
    }
    
    if (contextMenuOverlay) {
      contextMenuOverlay.addEventListener('click', closeContextMenu);
    }
    
    // PDF Viewer action butonlarını bağla
    const pdfShareBtn = document.getElementById('pdfShareBtn');
    const pdfPrintBtn = document.getElementById('pdfPrintBtn');
    const pdfSaveBtn = document.getElementById('pdfSaveBtn');
    
    if (pdfShareBtn) {
      pdfShareBtn.onclick = async () => {
        if (!currentPDFViewerId) {
          showPDFToast('PDF hazır değil', 2000);
          return;
        }
        
        const pdf = pdfList.find(p => p.id === currentPDFViewerId);
        if (!pdf) return;
        
        const base64Data = pdfFiles[currentPDFViewerId];
        if (base64Data) {
          PlatformActions.share(base64Data, pdf.name);
        } else {
          showPDFToast('PDF verisi bulunamadı', 3000);
        }
      };
    }
    
    if (pdfPrintBtn) {
      pdfPrintBtn.onclick = () => {
        if (!currentPDFViewerId) {
          showPDFToast('PDF hazır değil', 2000);
          return;
        }
        
        const pdf = pdfList.find(p => p.id === currentPDFViewerId);
        if (!pdf) return;
        
        const base64Data = pdfFiles[currentPDFViewerId];
        if (base64Data) {
          PlatformActions.print(base64Data, pdf.name);
        } else {
          showPDFToast('PDF verisi bulunamadı', 3000);
        }
      };
    }
    
    if (pdfSaveBtn) {
      pdfSaveBtn.onclick = async () => {
        if (!currentPDFViewerId) return;
        
        const pdf = pdfList.find(p => p.id === currentPDFViewerId);
        if (!pdf) return;
        
        const base64Data = pdfFiles[currentPDFViewerId];
        if (base64Data) {
          PlatformActions.save(base64Data, pdf.name);
        }
      };
    }
    
    // ESC tuşu ile PDF viewer'ı kapat
    document.addEventListener('keydown', (e) => {
      const pdfViewerModal = document.getElementById('pdfViewerModal');
      if (pdfViewerModal && e.key === 'Escape' && pdfViewerModal.style.display === 'flex') {
        closePDFViewer();
      }
    });
    
    // Sayfa tıklanınca context menu kapat
    document.addEventListener('click', function(event) {
      const contextMenu = document.getElementById('contextMenu');
      if (!contextMenu) return;
      
      if (!event.target.closest('.context-menu') && !event.target.closest('.more-options')) {
        closeContextMenu();
      }
    });
    
    // Flutter'dan gelen mesajları dinle
    window.addEventListener('message', function(event) {
      try {
        // Flutter'dan gelen mesajları işle
        if (event.data && event.data.type === 'FROM_FLUTTER') {
          console.log('Flutter\'dan mesaj:', event.data);
          
          switch(event.data.action) {
            case 'CLOSE_DRAWER':
              closeDrawer();
              break;
            case 'GO_BACK':
              if (document.getElementById('pdfViewerModal')?.style.display === 'flex') {
                closePDFViewer();
              } else {
                showPage('home', document.querySelector('.bottom-tab.active'));
              }
              break;
            case 'RELOAD_PDFS':
              updatePDFLists();
              break;
            case 'ADD_PDF':
              if (event.data.base64 && event.data.fileName) {
                addPDF(event.data.fileName, 0, new Date().toISOString(), event.data.base64);
              }
              break;
          }
        }
      } catch (error) {
        console.error('Flutter mesaj işleme hatası:', error);
      }
    });
  }

  // 🚀 Uygulamayı başlat
  function initializeApp() {
    // Tema seçimini yükle
    const savedTheme = localStorage.getItem('selectedTheme');
    if (savedTheme) {
      selectTheme(savedTheme);
    }
    
    // PDF dosyalarını localStorage'dan yükle
    pdfFiles = JSON.parse(localStorage.getItem('pdfFiles')) || {};
    
    // PDF listelerini güncelle
    updatePDFLists();
    
    // Event listeners'ları kur
    setupEventListeners();
    
    // Flutter'a uygulama hazır olduğunu bildir
    setTimeout(() => {
      if (isFlutterWebView()) {
        FlutterBridge.sendToFlutter('APP_READY', { 
          platform: navigator.platform,
          pdfCount: pdfList.length
        });
      }
    }, 500);
  }

  // Uygulamayı başlat
  initializeApp();
});
