// Dil ayarları
const languageConfig = {
    
    current: 'en',
    
    // Dil isimleri
    names: {
        ar: "Arabic",
        bn: "Bengali",
        de: "German",
        en: "English",
        es: "Spanish",
        fr: "French",
        hi: "Hindi",
        id: "Indonesian",
        ja: "Japanese",
        ku: "Kurmanci",
        pt: "Portuguese",
        ru: "Russian",
        sw: "Swahili",
        tr: "Turkish",
        ur: "Urdu",
        za: "Zazakî",
        zh: "Chinese"
    },
    
    // Dil değiştirme fonksiyonu
    setLanguage: function(langCode) {
        if (this.names[langCode]) {
            this.current = langCode;
            if (typeof updateUIText === 'function') {
                updateUIText();
            }
            return true;
        }
        return false;
    },
    
    // Mevcut dili al
    getCurrent: function() {
        return this.current;
    },
    
    // Tüm dilleri al
    getAvailableLanguages: function() {
        return this.names;
    }
};

// Dil değişimi için global fonksiyon
function changeLanguage(langCode) {
    if (languageConfig.setLanguage(langCode)) {
        console.log('Dil değiştirildi:', langCode);
    }
}

// Sayfa yüklendiğinde UI'ı güncelle
document.addEventListener('DOMContentLoaded', function() {
    if (typeof updateUIText === 'function') {
        updateUIText();
    }
});
