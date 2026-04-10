import 'package:flutter/foundation.dart';

enum LogLevel { error, warning, info, debug }

class AppLogger {
  // Global setting to control verbosity
  static LogLevel minLevel = LogLevel.info;
  static bool showOnlyErrors = false;

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _log(LogLevel.error, '❌ ERROR: $message', error, stackTrace);
  }

  static void warn(String message) {
    _log(LogLevel.warning, '⚠️ WARN: $message');
  }

  static void info(String message) {
    _log(LogLevel.info, 'ℹ️ INFO: $message');
  }

  static void debug(String message) {
    _log(LogLevel.debug, '🔍 DEBUG: $message');
  }

  static void _log(LogLevel level, String message, [dynamic err, StackTrace? stack]) {
    if (level.index > minLevel.index) return;
    if (showOnlyErrors && level != LogLevel.error && level != LogLevel.warning) return;

    final timestamp = DateTime.now().toIso8601String().split('T').last.substring(0, 8);
    final fullMessage = '[$timestamp] $message';

    if (err != null) {
      debugPrint('$fullMessage\nError: $err');
      if (stack != null) debugPrint('Stack: $stack');
    } else {
      debugPrint(fullMessage);
    }
  }
}
