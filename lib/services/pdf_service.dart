import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';

class PDFService {
  final Map<String, String> _tempFiles = {};

  // ==================== TEMP DOSYALARI TEMİZLE ====================
  Future<void> cleanupTempFiles() async {
    debugPrint("🗑️ PDFService: Temp dosyalar temizleniyor...");
    
    for (var path in _tempFiles.values) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          debugPrint("✅ PDFService: Temp dosya silindi: $path");
        }
      } catch (e) {
        debugPrint("⚠️ PDFService: Temp dosya silinemedi: $e");
      }
    }
    _tempFiles.clear();
    debugPrint("✅ PDFService: Tüm temp dosyalar temizlendi");
  }

  // ==================== PDF LİSTESİ ====================
  Future<String> listPdfFiles() async {
    List<Map<String, dynamic>> pdfFiles = [];
    
    try {
      if (Platform.isAndroid) {
        debugPrint("📂 PDFService: PDF dosyaları taranıyor...");
        
        List<String> searchPaths = [
          '/storage/emulated/0/Download',
          '/storage/emulated/0/Documents',
          '/storage/emulated/0/Downloads',
          '/storage/emulated/0/DCIM',
          '/storage/emulated/0',
          '/sdcard/Download',
          '/sdcard/Documents',
        ];

        for (String path in searchPaths) {
          try {
            final directory = Directory(path);
            if (await directory.exists()) {
              await _scanDirectoryRecursive(directory, pdfFiles);
            }
          } catch (e) {
            debugPrint("⚠️ PDFService: Dizin tarama hatası: $path - $e");
            continue;
          }
        }
        
        // Boyuta göre sırala (büyükten küçüğe)
        pdfFiles.sort((a, b) => b['size'].compareTo(a['size']));
        
        debugPrint("✅ PDFService: ${pdfFiles.length} PDF dosyası bulundu");
      }
    } catch (e) {
      debugPrint("❌ PDFService: PDF listeleme hatası: $e");
    }
    
    return jsonEncode(pdfFiles);
  }

  // ==================== DİZİNİ RECURSIVE TARA ====================
  Future<void> _scanDirectoryRecursive(
    Directory directory, 
    List<Map<String, dynamic>> pdfFiles
  ) async {
    try {
      final contents = directory.list(recursive: false);
      
      await for (var entity in contents) {
        if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
          try {
            final stat = await entity.stat();
            final sizeInMB = stat.size / (1024 * 1024);
            
            // IndexedDB için boyut limiti (100MB)
            if (sizeInMB > 100) {
              debugPrint("⚠️ PDFService: Büyük dosya atlandı: ${entity.path} (${sizeInMB.toStringAsFixed(2)} MB) - IndexedDB limiti");
              continue;
            }
            
            pdfFiles.add({
              'path': entity.path,
              'name': entity.path.split('/').last,
              'size': stat.size,
              'modified': stat.modified.toIso8601String(),
              'sizeMB': sizeInMB,
            });
            
          } catch (e) {
            debugPrint("⚠️ PDFService: Dosya bilgisi alınamadı: ${entity.path}");
            continue;
          }
        } else if (entity is Directory) {
          final dirName = entity.path.split('/').last.toLowerCase();
          // Gizli ve sistem dizinlerini atla
          if (!dirName.startsWith('.') && 
              dirName != 'android' && 
              dirName != 'lost+found' &&
              !dirName.contains('cache') &&
              !dirName.contains('trash')) {
            await _scanDirectoryRecursive(entity, pdfFiles);
          }
        }
      }
    } catch (e) {
      debugPrint("❌ PDFService: Dizin tarama hatası (${directory.path}): $e");
    }
  }

  // ==================== DOSYA BOYUTUNU FORMATLA ====================
  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // ==================== PDF PATH AL (TEMP'E KOPYALA) ====================
  Future<String?> getPdfPath(String sourcePath, String fileName) async {
    try {
      debugPrint("📋 PDFService: PDF temp'e kopyalanıyor: $fileName");
      
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        debugPrint("❌ PDFService: Kaynak dosya bulunamadı: $sourcePath");
        return null;
      }
      
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$fileName';
      final tempFile = File(tempPath);
      
      // Eğer temp'te varsa ve güncel ise tekrar kopyalama
      if (await tempFile.exists()) {
        final sourceStat = await sourceFile.stat();
        final tempStat = await tempFile.stat();
        
        if (sourceStat.size == tempStat.size && 
            sourceStat.modified.isBefore(tempStat.modified.add(const Duration(minutes: 5)))) {
          debugPrint("✅ PDFService: Temp dosya güncel, kopyalama atlandı");
          _tempFiles[fileName] = tempPath;
          return tempPath;
        }
      }
      
      // Dosyayı kopyala
      await sourceFile.copy(tempPath);
      _tempFiles[fileName] = tempPath;
      
      final sizeInMB = (await tempFile.stat()).size / (1024 * 1024);
      debugPrint("✅ PDFService: PDF temp'e kopyalandı: $tempPath (${sizeInMB.toStringAsFixed(2)} MB)");
      
      return tempPath;
      
    } catch (e) {
      debugPrint("❌ PDFService: Temp kopyalama hatası: $e");
      return null;
    }
  }

  // ==================== DOSYA OKU (BINARY) ====================
  Future<dynamic> readPdfFile(String filePath) async {
    try {
      debugPrint("📖 PDFService: PDF dosyası okunuyor: $filePath");
      
      final file = File(filePath);
      
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final sizeInMB = bytes.length / (1024 * 1024);
        debugPrint("✅ PDFService: PDF okundu: ${sizeInMB.toStringAsFixed(2)} MB");
        
        return bytes;
      } else {
        debugPrint("❌ PDFService: Dosya bulunamadı: $filePath");
        return null;
      }
    } catch (e) {
      debugPrint("❌ PDFService: Dosya okuma hatası: $e");
      return null;
    }
  }

  // ==================== PAYLAŞ ====================
  Future<void> sharePdf(String filePath, String? fileName) async {
    try {
      debugPrint("📤 PDFService: PDF paylaşılıyor: ${fileName ?? filePath}");
      
      final file = File(filePath);
      
      if (await file.exists()) {
        final name = fileName ?? file.path.split('/').last;
        
        await Share.shareXFiles(
          [XFile(file.path)], 
          text: name,
          subject: name,
        );
        
        debugPrint("✅ PDFService: PDF paylaşıldı");
      } else {
        debugPrint("❌ PDFService: Paylaşılacak dosya bulunamadı: $filePath");
      }
    } catch (e) {
      debugPrint("❌ PDFService: Paylaşma hatası: $e");
    }
  }

  // ==================== YAZDIR ====================
  Future<void> printPdf(BuildContext context, String filePath, String? fileName) async {
    try {
      debugPrint("🖨️ PDFService: PDF yazdırılıyor: ${fileName ?? filePath}");
      
      final file = File(filePath);
      
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final name = fileName ?? file.path.split('/').last;
        
        await Printing.layoutPdf(
          onLayout: (format) async => bytes,
          name: name,
        );
        
        debugPrint("✅ PDFService: Yazdırma tamamlandı");
      } else {
        debugPrint("❌ PDFService: Yazdırılacak dosya bulunamadı: $filePath");
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Dosya bulunamadı'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("❌ PDFService: Yazdırma hatası: $e");
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Yazdırma hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // ==================== İNDİR ====================
  Future<void> downloadPdf(BuildContext context, String sourcePath, String? fileName) async {
    try {
      debugPrint("💾 PDFService: PDF indiriliyor: ${fileName ?? sourcePath}");
      
      final sourceFile = File(sourcePath);
      
      if (!await sourceFile.exists()) {
        debugPrint("❌ PDFService: Kaynak dosya bulunamadı: $sourcePath");
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Dosya bulunamadı'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = Directory('/storage/emulated/0/Downloads');
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory != null && await directory.exists()) {
        final name = fileName ?? sourceFile.path.split('/').last;
        String finalName = name;
        String nameWithoutExt = name.replaceAll('.pdf', '');
        File targetFile = File('${directory.path}/$finalName');
        
        // Aynı isimli dosya varsa numara ekle
        int counter = 1;
        while (await targetFile.exists()) {
          finalName = '$nameWithoutExt ($counter).pdf';
          targetFile = File('${directory.path}/$finalName');
          counter++;
        }
        
        await sourceFile.copy(targetFile.path);
        
        final sizeInMB = (await targetFile.stat()).size / (1024 * 1024);
        debugPrint("✅ PDFService: PDF indirildi: ${targetFile.path} (${sizeInMB.toStringAsFixed(2)} MB)");

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ İndirildi: $finalName'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Tamam',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
      } else {
        debugPrint("❌ PDFService: Download dizini bulunamadı");
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ İndirme dizini bulunamadı'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("❌ PDFService: İndirme hatası: $e");
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ İndirme hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // ==================== DOSYA VAR MI KONTROL ====================
  Future<bool> fileExists(String filePath) async {
    try {
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      debugPrint("❌ PDFService: Dosya varlık kontrolü hatası: $e");
      return false;
    }
  }

  // ==================== DOSYA BOYUTU AL ====================
  Future<int> getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final stat = await file.stat();
        return stat.size;
      }
    } catch (e) {
      debugPrint("❌ PDFService: Dosya boyutu alma hatası: $e");
    }
    return 0;
  }

  // ==================== DOSYA SİL ====================
  Future<bool> deleteFile(String filePath) async {
    try {
      debugPrint("🗑️ PDFService: Dosya siliniyor: $filePath");
      
      final file = File(filePath);
      
      if (await file.exists()) {
        await file.delete();
        
        // Temp files'dan da sil
        _tempFiles.removeWhere((key, value) => value == filePath);
        
        debugPrint("✅ PDFService: Dosya silindi");
        return true;
      } else {
        debugPrint("⚠️ PDFService: Silinecek dosya bulunamadı");
        return false;
      }
    } catch (e) {
      debugPrint("❌ PDFService: Dosya silme hatası: $e");
      return false;
    }
  }

  // ==================== DOSYA YENİDEN ADLANDIR ====================
  Future<String?> renameFile(String oldPath, String newName) async {
    try {
      debugPrint("✏️ PDFService: Dosya yeniden adlandırılıyor: $oldPath -> $newName");
      
      final oldFile = File(oldPath);
      
      if (!await oldFile.exists()) {
        debugPrint("❌ PDFService: Eski dosya bulunamadı");
        return null;
      }
      
      final directory = oldFile.parent;
      final newPath = '${directory.path}/$newName';
      
      final newFile = await oldFile.rename(newPath);
      
      debugPrint("✅ PDFService: Dosya yeniden adlandırıldı: $newPath");
      return newFile.path;
      
    } catch (e) {
      debugPrint("❌ PDFService: Dosya yeniden adlandırma hatası: $e");
      return null;
    }
  }

  // ==================== STORAGE BİLGİSİ ====================
  Future<Map<String, dynamic>> getStorageInfo() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final appDir = await getApplicationDocumentsDirectory();
      
      return {
        'tempDir': tempDir.path,
        'appDir': appDir.path,
        'tempFiles': _tempFiles.length,
        'indexedDBSupported': true,
        'maxPdfSize': 100, // MB
        'storageType': 'indexeddb-arraybuffer',
      };
    } catch (e) {
      debugPrint("❌ PDFService: Storage bilgisi hatası: $e");
      return {};
    }
  }
}


