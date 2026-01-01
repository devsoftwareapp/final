import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';

class PermissionService {
  /* --------------------------------------------------------
   * CHECK
   * ------------------------------------------------------*/
  Future<bool> checkStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Android 13+ medya izinleri
    final mediaStatuses = await Future.wait([
      Permission.photos.status,
      Permission.videos.status,
      Permission.audio.status,
    ]);

    if (mediaStatuses.any((s) => s.isGranted)) {
      return true;
    }

    // Android 11–12
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }

    if (await Permission.storage.isGranted) {
      return true;
    }

    return false;
  }

  /* --------------------------------------------------------
   * REQUEST
   * ------------------------------------------------------*/
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Android 11+ full access
    if (await Permission.manageExternalStorage.isDenied) {
      final result =
          await Permission.manageExternalStorage.request();

      if (result.isGranted) return true;

      if (result.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
    }

    // Legacy
    if (await Permission.storage.isDenied) {
      final result = await Permission.storage.request();
      if (result.isGranted) return true;
    }

    return false;
  }

  /* --------------------------------------------------------
   * OPEN SETTINGS
   * ------------------------------------------------------*/
  Future<void> openAppSettings() async {
    try {
      await AppSettings.openAppSettings(
        type: AppSettingsType.settings,
      );
    } catch (e) {
      debugPrint("❌ Ayarlar açılamadı: $e");
    }
  }
}
