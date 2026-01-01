import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';
import 'package:device_info_plus/device_info_plus.dart';

class PermissionService {
  
  // ==================== STORAGE İZNİ KONTROLÜ ====================
  Future<bool> checkStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        debugPrint("🔒 PermissionService: Storage izni kontrol ediliyor...");
        
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        
        debugPrint("📱 PermissionService: Android SDK: $sdkInt");
        
        // Android 13+ (API 33+) için
        if (sdkInt >= 33) {
          debugPrint("🔒 PermissionService: Android 13+ izinleri kontrol ediliyor");
          
          final android13Permissions = await Future.wait([
            Permission.photos.status,
            Permission.videos.status,
            Permission.audio.status,
          ]);
          
          final hasAnyGranted = android13Permissions.any((status) => status.isGranted);
          
          if (hasAnyGranted) {
            debugPrint("✅ PermissionService: Android 13+ izni var");
            return true;
          }
          
          debugPrint("❌ PermissionService: Android 13+ izni yok");
        }
        
        // Android 11-12 (API 30-32) için
        if (sdkInt >= 30) {
          debugPrint("🔒 PermissionService: Android 11-12 manageExternalStorage kontrol ediliyor");
          
          final manageStorageStatus = await Permission.manageExternalStorage.status;
          
          if (manageStorageStatus.isGranted) {
            debugPrint("✅ PermissionService: manageExternalStorage izni var");
            return true;
          }
          
          debugPrint("⚠️ PermissionService: manageExternalStorage izni yok");
        }
        
        // Android 10 ve altı (API 29 ve altı) için
        debugPrint("🔒 PermissionService: Android 10- storage izni kontrol ediliyor");
        
        final storageStatus = await Permission.storage.status;
        
        if (storageStatus.isGranted) {
          debugPrint("✅ PermissionService: Storage izni var");
          return true;
        }
        
        debugPrint("❌ PermissionService: Hiçbir storage izni yok");
        return false;
      }
      
      // iOS için
      debugPrint("✅ PermissionService: iOS platformu - izin kontrolü gerekmiyor");
      return true;
      
    } catch (e) {
      debugPrint("❌ PermissionService: İzin kontrolü hatası: $e");
      return false;
    }
  }

  // ==================== STORAGE İZNİ İSTE ====================
  Future<bool> requestStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        debugPrint("🔒 PermissionService: Storage izni isteniyor...");
        
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        
        debugPrint("📱 PermissionService: Android SDK: $sdkInt");
        
        // Android 13+ (API 33+) için
        if (sdkInt >= 33) {
          debugPrint("🔒 PermissionService: Android 13+ izinleri isteniyor");
          
          final results = await [
            Permission.photos,
            Permission.videos,
            Permission.audio,
          ].request();
          
          final hasAnyGranted = results.values.any((status) => status.isGranted);
          
          if (hasAnyGranted) {
            debugPrint("✅ PermissionService: Android 13+ izinleri verildi");
            return true;
          }
          
          // Kalıcı olarak reddedildiyse ayarlara yönlendir
          final hasAnyPermanentlyDenied = results.values.any((status) => status.isPermanentlyDenied);
          
          if (hasAnyPermanentlyDenied) {
            debugPrint("⚠️ PermissionService: Android 13+ izinleri kalıcı olarak reddedildi, ayarlara yönlendiriliyor");
            await openAppSettings();
            return false;
          }
          
          debugPrint("❌ PermissionService: Android 13+ izinleri reddedildi");
          return false;
        }
        
        // Android 11-12 (API 30-32) için
        if (sdkInt >= 30) {
          debugPrint("🔒 PermissionService: Android 11-12 manageExternalStorage izni isteniyor");
          
          if (await Permission.manageExternalStorage.status.isDenied) {
            final result = await Permission.manageExternalStorage.request();
            
            if (result.isGranted) {
              debugPrint("✅ PermissionService: manageExternalStorage izni verildi");
              return true;
            }
            
            if (result.isPermanentlyDenied) {
              debugPrint("⚠️ PermissionService: manageExternalStorage kalıcı olarak reddedildi, ayarlara yönlendiriliyor");
              await openAppSettings();
              return false;
            }
            
            debugPrint("❌ PermissionService: manageExternalStorage izni reddedildi");
          }
        }
        
        // Android 10 ve altı (API 29 ve altı) için
        debugPrint("🔒 PermissionService: Storage izni isteniyor");
        
        if (await Permission.storage.status.isDenied) {
          final result = await Permission.storage.request();
          
          if (result.isGranted) {
            debugPrint("✅ PermissionService: Storage izni verildi");
            return true;
          }
          
          if (result.isPermanentlyDenied) {
            debugPrint("⚠️ PermissionService: Storage izni kalıcı olarak reddedildi, ayarlara yönlendiriliyor");
            await openAppSettings();
            return false;
          }
          
          debugPrint("❌ PermissionService: Storage izni reddedildi");
        }
        
        // Son kontrol
        final finalCheck = await checkStoragePermission();
        debugPrint("🔒 PermissionService: Final izin durumu: $finalCheck");
        return finalCheck;
      }
      
      // iOS için
      debugPrint("✅ PermissionService: iOS platformu - izin kontrolü gerekmiyor");
      return true;
      
    } catch (e) {
      debugPrint("❌ PermissionService: İzin isteme hatası: $e");
      return false;
    }
  }

  // ==================== UYGULAMA AYARLARINI AÇ ====================
  Future<void> openAppSettings() async {
    try {
      debugPrint("⚙️ PermissionService: Uygulama ayarları açılıyor...");
      
      if (Platform.isAndroid) {
        // Android için özel izin ayarları
        try {
          await AppSettings.openAppSettings(type: AppSettingsType.settings);
          debugPrint("✅ PermissionService: Android ayarları açıldı (AppSettings)");
          return;
        } catch (e) {
          debugPrint("⚠️ PermissionService: AppSettings açma hatası: $e");
        }
        
        // Fallback: permission_handler'ın openAppSettings'i
        try {
          await openAppSettings();
          debugPrint("✅ PermissionService: Android ayarları açıldı (fallback)");
          return;
        } catch (e) {
          debugPrint("❌ PermissionService: Fallback ayarlar açma hatası: $e");
        }
      } else {
        // iOS için
        await AppSettings.openAppSettings();
        debugPrint("✅ PermissionService: iOS ayarları açıldı");
      }
      
    } catch (e) {
      debugPrint("❌ PermissionService: Ayarlar açma hatası: $e");
    }
  }

  // ==================== NOTIFICATION İZNİ KONTROLÜ ====================
  Future<bool> checkNotificationPermission() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        
        // Android 13+ (API 33+) için notification izni gerekli
        if (sdkInt >= 33) {
          final status = await Permission.notification.status;
          debugPrint("🔔 PermissionService: Notification izni: $status");
          return status.isGranted;
        }
      }
      
      // Android 12 ve altı veya iOS için
      return true;
    } catch (e) {
      debugPrint("❌ PermissionService: Notification izin kontrolü hatası: $e");
      return false;
    }
  }

  // ==================== NOTIFICATION İZNİ İSTE ====================
  Future<bool> requestNotificationPermission() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        
        // Android 13+ (API 33+) için notification izni iste
        if (sdkInt >= 33) {
          debugPrint("🔔 PermissionService: Notification izni isteniyor...");
          
          final status = await Permission.notification.request();
          
          if (status.isGranted) {
            debugPrint("✅ PermissionService: Notification izni verildi");
            return true;
          }
          
          if (status.isPermanentlyDenied) {
            debugPrint("⚠️ PermissionService: Notification izni kalıcı olarak reddedildi");
            await openAppSettings();
            return false;
          }
          
          debugPrint("❌ PermissionService: Notification izni reddedildi");
          return false;
        }
      }
      
      return true;
    } catch (e) {
      debugPrint("❌ PermissionService: Notification izin isteme hatası: $e");
      return false;
    }
  }

  // ==================== TÜM İZİNLERİ KONTROL ET ====================
  Future<Map<String, bool>> checkAllPermissions() async {
    try {
      final storage = await checkStoragePermission();
      final notification = await checkNotificationPermission();
      
      final permissions = {
        'storage': storage,
        'notification': notification,
      };
      
      debugPrint("📋 PermissionService: Tüm izinler: $permissions");
      
      return permissions;
    } catch (e) {
      debugPrint("❌ PermissionService: Tüm izinleri kontrol hatası: $e");
      return {
        'storage': false,
        'notification': false,
      };
    }
  }

  // ==================== TÜM İZİNLERİ İSTE ====================
  Future<Map<String, bool>> requestAllPermissions() async {
    try {
      debugPrint("🔒 PermissionService: Tüm izinler isteniyor...");
      
      final storage = await requestStoragePermission();
      final notification = await requestNotificationPermission();
      
      final permissions = {
        'storage': storage,
        'notification': notification,
      };
      
      debugPrint("📋 PermissionService: Tüm izinler sonucu: $permissions");
      
      return permissions;
    } catch (e) {
      debugPrint("❌ PermissionService: Tüm izinleri isteme hatası: $e");
      return {
        'storage': false,
        'notification': false,
      };
    }
  }

  // ==================== İZİN DURUMU BİLGİSİ ====================
  Future<Map<String, dynamic>> getPermissionInfo() async {
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      
      final storageStatus = await checkStoragePermission();
      final notificationStatus = await checkNotificationPermission();
      
      String requiredPermissions = '';
      
      if (sdkInt >= 33) {
        requiredPermissions = 'photos, videos, audio, notification';
      } else if (sdkInt >= 30) {
        requiredPermissions = 'manageExternalStorage';
      } else {
        requiredPermissions = 'storage';
      }
      
      final info = {
        'platform': Platform.operatingSystem,
        'sdkInt': sdkInt,
        'requiredPermissions': requiredPermissions,
        'storageGranted': storageStatus,
        'notificationGranted': notificationStatus,
        'allGranted': storageStatus && (sdkInt < 33 || notificationStatus),
      };
      
      debugPrint("📋 PermissionService: İzin bilgisi: $info");
      
      return info;
    } catch (e) {
      debugPrint("❌ PermissionService: İzin bilgisi hatası: $e");
      return {};
    }
  }

  // ==================== İZİN DURUMU GÖSTERİCİSİ (UI İÇİN) ====================
  Future<void> showPermissionDialog(BuildContext context) async {
    try {
      final info = await getPermissionInfo();
      
      if (!context.mounted) return;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_outline, color: Color(0xFFE53935)),
              SizedBox(width: 8),
              Text('İzin Gerekli'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PDF dosyalarına erişebilmek için depolama izni gereklidir.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              Text(
                'Gerekli İzinler:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                info['requiredPermissions'] ?? 'storage',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await requestStoragePermission();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
              ),
              child: const Text('İzin Ver'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint("❌ PermissionService: Dialog gösterme hatası: $e");
    }
  }

  // ==================== İZİN DURUMU SNACKBAR ====================
  void showPermissionSnackBar(BuildContext context, {required bool granted}) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted 
            ? '✅ İzin verildi' 
            : '❌ İzin reddedildi. Ayarlardan izin verebilirsiniz.',
        ),
        backgroundColor: granted ? Colors.green : Colors.red,
        duration: Duration(seconds: granted ? 2 : 4),
        action: !granted ? SnackBarAction(
          label: 'Ayarlar',
          textColor: Colors.white,
          onPressed: () => openAppSettings(),
        ) : null,
      ),
    );
  }

  // ==================== ANDROID SDK SÜRÜMÜNÜ AL ====================
  Future<int> getAndroidSdkVersion() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        return androidInfo.version.sdkInt;
      }
      return 0;
    } catch (e) {
      debugPrint("❌ PermissionService: SDK sürümü alma hatası: $e");
      return 0;
    }
  }
}


