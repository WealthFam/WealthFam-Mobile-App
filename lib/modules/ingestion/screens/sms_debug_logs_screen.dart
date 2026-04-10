import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_app/modules/ingestion/services/sms_service.dart';

class SmsDebugLogsScreen extends StatelessWidget {
  const SmsDebugLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final smsService = context.watch<SmsService>();
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Payloads'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => smsService.refreshDebugLogs(),
          ),
        ]
      ),
      body: smsService.debugLogs.isEmpty 
        ? Center(
            child: Text(
              "No debug payloads found.\nEnsure 'Show Data In Backend' is enabled.", 
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            )
          )
        : ListView.builder(
            itemCount: smsService.debugLogs.length,
            itemBuilder: (context, index) {
               final log = smsService.debugLogs[index];
               final formatted = const JsonEncoder.withIndent('  ').convert(log);
               return Card(
                 margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                 color: theme.colorScheme.surface,
                 shape: RoundedRectangleBorder(
                   borderRadius: BorderRadius.circular(12),
                   side: BorderSide(color: theme.dividerColor),
                 ),
                 child: Padding(
                   padding: const EdgeInsets.all(16),
                   child: SelectableText(
                     formatted,
                     style: TextStyle(
                       fontFamily: 'monospace', 
                       fontSize: 12,
                       color: theme.colorScheme.onSurface
                     ),
                   ),
                 ),
               );
            },
          ),
    );
  }
}
