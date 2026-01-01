import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';

class PDFService {
  final Map<String, String> _tempFiles = {};

  // Temp dosyaları temizle
  Future<void> cleanupTempFiles() async {
    for (var path in _tempFiles.values) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint("⚠️ Temp dosya silinemedi: $e");
      }
    }
    _tempFiles.clear();
  }

  // PDF listesi
  Future<String> listPdfFiles() async {
    List<Map<String, dynamic>> pdfFiles = [];
    
    try {
      if (Platform.isAndroid) {
        debugPrint("📂 PDF dosyaları taranıyor...");
        
        List<String> searchPaths = [
          '/storage/emulated/0/Download',
          '/storage/emulated/0/Documents',
          '/storage/emulated/0/Downloads',
        ];

        for (String path in searchPaths) {
          try {
            final directory = Directory(path);
            if (await directory.exists()) {
              await _scanDirectoryRecursive(directory, pdfFiles);
            }
          } catch (e) {
            continue;
          }
        }
        
        debugPrint("✅ ${pdfFiles.length} PDF bulundu");
      }
    } catch (e) {
      debugPrint("❌ PDF listeleme hatası: $e");
    }
    
    return jsonEncode(pdfFiles);
  }

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
            
            if (sizeInMB > 100) continue;
            
            pdfFiles.add({
              'path': entity.path,
              'name': entity.path.split('/').last,
              'size': stat.size,
              'modified': stat.modified.toIso8601String(),
            });
          } catch (e) {
            continue;
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Dizin tarama hatası: $e");
    }
  }

  // PDF path al
  Future<String?> getPdfPath(String sourcePath, String fileName) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) return null;
      
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$fileName';
      
      await sourceFile.copy(tempPath);
      _tempFiles[fileName] = tempPath;
      
      return tempPath;
    } catch (e) {
      debugPrint("❌ PDF path hatası: $e");
      return null;
    }
  }

  // Dosya oku
  Future<dynamic> readPdfFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint("❌ Dosya okuma hatası: $e");
    }
    return null;
  }

  // Paylaş
  Future<void> sharePdf(String filePath, String? fileName) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(file.path)], 
          text: fileName ?? file.path.split('/').last
        );
      }
    } catch (e) {
      debugPrint("❌ Paylaşma hatası: $e");
    }
  }

  // Yazdır
  Future<void> printPdf(BuildContext context, String filePath, String? fileName) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        await Printing.layoutPdf(
          onLayout: (format) async => bytes,
          name: fileName ?? file.path.split('/').last,
        );
      }
    } catch (e) {
      debugPrint("❌ Yazdırma hatası: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yazdırma hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // İndir
  Future<void> downloadPdf(BuildContext context, String sourcePath, String? fileName) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) return;
      
      final directory = Directory('/storage/emulated/0/Download');
      if (await directory.exists()) {
        final name = fileName ?? sourceFile.path.split('/').last;
        final targetPath = '${directory.path}/$name';
        await sourceFile.copy(targetPath);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ İndirildi: $name'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      debugPrint("❌ İndirme hatası: $e");
    }
  }
}
