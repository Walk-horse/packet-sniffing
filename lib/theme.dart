import 'package:flutter/material.dart';

/// 重新设计的视觉体系：靛蓝(brand) + 青绿(accent) + 琥珀(action)，
/// 浅灰背景 + 白卡片 + 柔和阴影。区别于参考图的蓝/橙配色。
class AppColors {
  static const Color brand = Color(0xFF4F46E5); // 靛蓝
  static const Color brandDark = Color(0xFF4338CA);
  static const Color brandLight = Color(0xFFEEF0FF);
  static const Color accent = Color(0xFF0EA5A4); // 青绿
  static const Color accentSoft = Color(0xFFE2F7F6);
  static const Color action = Color(0xFFF59E0B); // 琥珀（主操作）
  static const Color actionSoft = Color(0xFFFEF3E2);
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerSoft = Color(0xFFFDECEC);
  static const Color success = Color(0xFF22B573);

  static const Color bg = Color(0xFFF5F6FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF1A1A1A); // 中性近黑（对齐参考 iOS Stream 主文字）
  static const Color subtext = Color(0xFF8E8E93); // 浅中性灰（对齐参考 SubText）
  static const Color border = Color(0xFFECEEF3);
  static const Color chipTrack = Color(0xFFE7E9F0);

  // HTTP method 彩标
  static const Color methodGet = Color(0xFF10B981);
  static const Color methodPost = Color(0xFF3B82F6);
  static const Color methodPut = Color(0xFFF59E0B);
  static const Color methodDelete = Color(0xFFEF4444);
  static const Color methodHead = Color(0xFF8B5CF6);
  static const Color methodPatch = Color(0xFFEC4899);
  static const Color methodOptions = Color(0xFF64748B);

  static Color methodColor(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return methodGet;
      case 'POST':
        return methodPost;
      case 'PUT':
        return methodPut;
      case 'DELETE':
        return methodDelete;
      case 'HEAD':
        return methodHead;
      case 'PATCH':
        return methodPatch;
      case 'OPTIONS':
        return methodOptions;
      default:
        return subtext;
    }
  }
}

class AppGradients {
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF4338CA), Color(0xFF6366F1), Color(0xFF0EA5A4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient actionGradient = LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        // 全站紧凑：控件默认内外边距整体收缩
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        scaffoldBackgroundColor: AppColors.bg,
        primaryColor: AppColors.brand,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.brand,
          primary: AppColors.brand,
          secondary: AppColors.accent,
          error: AppColors.danger,
          surface: AppColors.surface,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: AppColors.text, fontSize: 15),
          titleMedium: TextStyle(color: AppColors.text, fontWeight: FontWeight.w500),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border, width: 1),
          ),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 38),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 34),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.brand,
            side: const BorderSide(color: AppColors.brand),
            minimumSize: const Size(0, 34),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            textStyle: const TextStyle(fontSize: 14),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 30),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            textStyle: const TextStyle(fontSize: 13),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            minimumSize: WidgetStateProperty.all(const Size(0, 30)),
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
            textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13)),
            shape: WidgetStateProperty.all(RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7))),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: AppColors.brand, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        // 颜色必须显式给：只覆盖部分字段时未选中 label 会解析成白色，文字「消失」
        chipTheme: const ChipThemeData(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          labelPadding: EdgeInsets.symmetric(horizontal: 2),
          backgroundColor: Colors.white,
          selectedColor: AppColors.brandLight,
          disabledColor: Colors.white,
          labelStyle: TextStyle(fontSize: 12.5, color: AppColors.text),
          secondaryLabelStyle:
              TextStyle(fontSize: 12.5, color: AppColors.subtext),
          checkmarkColor: AppColors.brand,
          side: BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(6))),
        ),
        dividerTheme: const DividerThemeData(
            color: AppColors.border, thickness: 1, space: 1),
        listTileTheme: const ListTileThemeData(
          iconColor: AppColors.brand,
          visualDensity: VisualDensity.compact,
          minVerticalPadding: 6,
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        ),
        switchTheme: SwitchThemeData(
          thumbColor:
              WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
                  ? AppColors.brand
                  : Colors.white),
          trackColor:
              WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
                  ? AppColors.brand.withValues(alpha: 0.5)
                  : Colors.grey.shade300),
        ),
      );
}
