import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';

class PermissionService {
  
  Future<bool> checkStoragePermission() async {
    if (Platform.isAndroid) {
      final android13 = await Future.wait([
        Permission.photos.status,
        Permission.videos.status,
        Permission.audio.status,
      ]);
      
      if (android13.any((status) => status.isGranted)) return true;
      
      if ((await Permission.manageExternalStorage.status).isGranted) return true;
      if ((await Permission.storage.status).isGranted) return true;
      
      return false;
    }
    return true;
  }

  Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.status.isDenied) {
        final result = await Permission.manageExternalStorage.request();
        if (result.isGranted) return true;
        if (result.isPermanentlyDenied) {
          await openAppSettings();
          return false;
        }
      }
      
      if (await Permission.storage.status.isDenied) {
        final result = await Permission.storage.request();
        if (result.isGranted) return true;
      }
      
      return false;
    }
    return true;
  }

  Future<void> openAppSettings() async {
    try {
      if (Platform.isAndroid) {
        await AppSettings.openAppSettings(type: AppSettingsType.settings);
      } else {
        await AppSettings.openAppSettings();
      }
    } catch (e) {
      debugPrint("❌ Ayarlar açma hatası: $e");
    }
  }
}


