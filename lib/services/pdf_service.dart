import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';

class PDFService {
  final Map<String, String> _tempFiles = {};

  /* --------------------------------------------------------
   * TEMP CLEANUP
   * ------------------------------------------------------*/
  Future<void> cleanupTempFiles() async {
    for (final path in _tempFiles.values) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint("⚠️ Temp silinemedi: $e");
      }
    }
    _tempFiles.clear();
  }

  /* --------------------------------------------------------
   * LIST PDF FILES (ANDROID)
   * JS -> String (json)
   * ------------------------------------------------------*/
  Future<String> listPdfFiles() async {
    final List<Map<String, dynamic>> pdfFiles = [];

    if (!Platform.isAndroid) {
      return jsonEncode(pdfFiles);
    }

    try {
      const searchPaths = [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Documents',
        '/storage/emulated/0/Downloads',
      ];

      for (final path in searchPaths) {
        final dir = Directory(path);
        if (await dir.exists()) {
          await _scanDirectory(dir, pdfFiles);
        }
      }

      debugPrint("✅ ${pdfFiles.length} PDF bulundu");
    } catch (e) {
      debugPrint("❌ PDF tarama hatası: $e");
    }

    return jsonEncode(pdfFiles);
  }

  Future<void> _scanDirectory(
    Directory directory,
    List<Map<String, dynamic>> pdfFiles,
  ) async {
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File &&
            entity.path.toLowerCase().endsWith('.pdf')) {
          try {
            final stat = await entity.stat();
            final sizeMB = stat.size / (1024 * 1024);

            // Güvenli limit
            if (sizeMB > 100) continue;

            pdfFiles.add({
              'path': entity.path,
              'name': entity.uri.pathSegments.last,
              'size': stat.size,
              'modified': stat.modified.toIso8601String(),
            });
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /* --------------------------------------------------------
   * COPY PDF TO TEMP (VIEWER)
   * ------------------------------------------------------*/
  Future<String?> getPdfPath(
    String sourcePath,
    String fileName,
  ) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) return null;

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$fileName';

      await sourceFile.copy(tempPath);
      _tempFiles[fileName] = tempPath;

      return tempPath;
    } catch (e) {
      debugPrint("❌ getPdfPath hatası: $e");
      return null;
    }
  }

  /* --------------------------------------------------------
   * READ PDF (Uint8List for JS)
   * ------------------------------------------------------*/
  Future<List<int>?> readPdfFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint("❌ Okuma hatası: $e");
    }
    return null;
  }

  /* --------------------------------------------------------
   * SHARE
   * ------------------------------------------------------*/
  Future<void> sharePdf(
    String filePath,
    String? fileName,
  ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return;

      await Share.shareXFiles(
        [XFile(file.path)],
        text: fileName ?? file.uri.pathSegments.last,
      );
    } catch (e) {
      debugPrint("❌ Paylaşım hatası: $e");
    }
  }

  /* --------------------------------------------------------
   * PRINT
   * ------------------------------------------------------*/
  Future<void> printPdf(
    BuildContext context,
    String filePath,
    String? fileName,
  ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return;

      final bytes = await file.readAsBytes();
      await Printing.layoutPdf(
        name: fileName ?? file.uri.pathSegments.last,
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      debugPrint("❌ Yazdırma hatası: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Yazdırma hatası'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /* --------------------------------------------------------
   * DOWNLOAD
   * ------------------------------------------------------*/
  Future<void> downloadPdf(
    BuildContext context,
    String sourcePath,
    String? fileName,
  ) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) return;

      final targetDir =
          Directory('/storage/emulated/0/Download');
      if (!await targetDir.exists()) return;

      final name =
          fileName ?? sourceFile.uri.pathSegments.last;
      final targetPath = '${targetDir.path}/$name';

      await sourceFile.copy(targetPath);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ İndirildi: $name'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ İndirme hatası: $e");
    }
  }
}
