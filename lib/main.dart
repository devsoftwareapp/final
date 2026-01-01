import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'pages/index_page.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Android için WebView debugging aktif
  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  
  // Status bar ve Navigation bar ayarları
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
  
  // Ekran yönelimi ayarı (opsiyonel - gerekirse aktif et)
  // await SystemChrome.setPreferredOrientations([
  //   DeviceOrientation.portraitUp,
  //   DeviceOrientation.portraitDown,
  // ]);
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PDF Reader',
      
      // ==================== LIGHT THEME ====================
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primarySwatch: Colors.red,
        primaryColor: const Color(0xFFE53935),
        scaffoldBackgroundColor: const Color(0xFFE8E8E8),
        
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE53935),
          brightness: Brightness.light,
          primary: const Color(0xFFE53935),
          secondary: const Color(0xFFB71C1C),
          surface: const Color(0xFFE8E8E8),
          background: const Color(0xFFE8E8E8),
          error: const Color(0xFFF94144),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: const Color(0xFF0F172A),
          onBackground: const Color(0xFF0F172A),
        ),
        
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFE8E8E8),
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
          centerTitle: true,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
          titleTextStyle: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        
        cardTheme: CardTheme(
          color: const Color(0xFFE8E8E8),
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFE53935),
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1E293B),
          contentTextStyle: const TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFFE8E8E8),
          selectedItemColor: Color(0xFFE53935),
          unselectedItemColor: Color(0xFF64748B),
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        
        dialogTheme: DialogTheme(
          backgroundColor: const Color(0xFFE8E8E8),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        
        dividerTheme: const DividerThemeData(
          color: Color(0xFFD4D4D4),
          thickness: 1,
        ),
        
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF0F172A)),
          bodyMedium: TextStyle(color: Color(0xFF0F172A)),
          bodySmall: TextStyle(color: Color(0xFF64748B)),
          titleLarge: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
          titleMedium: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
          titleSmall: TextStyle(color: Color(0xFF0F172A)),
        ),
      ),
      
      // ==================== DARK THEME ====================
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primarySwatch: Colors.red,
        primaryColor: const Color(0xFFFF6961),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6961),
          brightness: Brightness.dark,
          primary: const Color(0xFFFF6961),
          secondary: const Color(0xFFB71C1C),
          surface: const Color(0xFF1E293B),
          background: const Color(0xFF0F172A),
          error: const Color(0xFFF94144),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: const Color(0xFFF8FAFC),
          onBackground: const Color(0xFFF8FAFC),
        ),
        
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E293B),
          foregroundColor: Color(0xFFF8FAFC),
          elevation: 0,
          centerTitle: true,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
          titleTextStyle: TextStyle(
            color: Color(0xFFF8FAFC),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        
        cardTheme: CardTheme(
          color: const Color(0xFF1E293B),
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFFF6961),
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF334155),
          contentTextStyle: const TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1E293B),
          selectedItemColor: Color(0xFFFF6961),
          unselectedItemColor: Color(0xFFCBD5E1),
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        
        dialogTheme: DialogTheme(
          backgroundColor: const Color(0xFF1E293B),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        
        dividerTheme: const DividerThemeData(
          color: Color(0xFF334155),
          thickness: 1,
        ),
        
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFF8FAFC)),
          bodyMedium: TextStyle(color: Color(0xFFF8FAFC)),
          bodySmall: TextStyle(color: Color(0xFFCBD5E1)),
          titleLarge: TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.w600),
          titleMedium: TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.w500),
          titleSmall: TextStyle(color: Color(0xFFF8FAFC)),
        ),
      ),
      
      // ==================== THEME MODE ====================
      themeMode: ThemeMode.system, // Sistem temasını takip eder
      
      // ==================== HOME PAGE ====================
      home: const IndexPage(),
      
      // ==================== DEBUG ====================
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.0), // Font scaling disable
          ),
          child: child!,
        );
      },
    );
  }
}


