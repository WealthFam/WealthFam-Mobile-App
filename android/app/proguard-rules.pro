# Flutter Foreground Task
-keep class com.pravera.flutter_foreground_task.** { *; }

# Keep service and receiver
-keep class com.pravera.flutter_foreground_task.service.ForegroundService { *; }

# Allow obfuscation but keep entry points
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Keep callback handle logic
-keep class * extends io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }
