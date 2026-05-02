import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:telephony/telephony.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/ingestion/services/sms_service.dart';
import 'package:mobile_app/core/widgets/app_shell.dart';
import 'package:intl/intl.dart';

class SmsManagementScreen extends StatefulWidget {
  const SmsManagementScreen({super.key});

  @override
  State<SmsManagementScreen> createState() => _SmsManagementScreenState();
}

class _SmsManagementScreenState extends State<SmsManagementScreen> {
  List<SmsMessage> _messages = [];
  bool _isLoading = true;
  bool _isProcessing = false;
  final Set<String> _selectedHashes = {};

  final TextEditingController _filterController = TextEditingController();
  List<SmsMessage> _filteredMessages = [];

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _filterMessages() {
    final query = _filterController.text.toLowerCase();
    setState(() {
      _filteredMessages = _messages.where((msg) {
        final address = (msg.address ?? '').toLowerCase();
        final body = (msg.body ?? '').toLowerCase();
        return address.contains(query) || body.contains(query);
      }).toList();
    });
  }

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    final smsService = context.read<SmsService>();
    final msgs = await smsService.getAllMessages();

    msgs.sort((a, b) => (b.date ?? 0).compareTo(a.date ?? 0));

    if (context.mounted) {
      setState(() {
        _messages = msgs;
        _isLoading = false;
      });
    }
  }

  Future<void> _pushSingle(SmsMessage msg) async {
    setState(() => _isProcessing = true);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final smsService = context.read<SmsService>();
    if (!context.mounted) return;
    try {
      await smsService.sendSmsToBackend(msg.address!, msg.body!, msg.date!);
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('SMS pushed successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to push: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _pushBulk() async {
    if (_selectedHashes.isEmpty) return;

    setState(() => _isProcessing = true);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    int success = 0;
    int failed = 0;

    final smsService = context.read<SmsService>();

    for (final msg in _messages) {
      final hash = smsService.computeHash(
        msg.address ?? '',
        (msg.date ?? 0).toString(),
        msg.body ?? '',
      );
      if (_selectedHashes.contains(hash)) {
        final smsService = context.read<SmsService>();
        if (!context.mounted) return;
        try {
          await smsService.sendSmsToBackend(msg.address!, msg.body!, msg.date!);
          success++;
        } catch (e) {
          failed++;
        }
      }
    }

    if (context.mounted) {
      setState(() {
        _isProcessing = false;
        _selectedHashes.clear();
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('Bulk push complete: $success success, $failed failed'),
        ),
      );
    }
  }

  Future<void> _pickAndSyncDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 1)),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Sync'),
          content: Text(
            'Scan and sync all SMS from ${DateFormat('dd MMM yyyy').format(picked)}? This might take a moment.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Start Sync'),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        setState(() => _isProcessing = true);
        messenger.showSnackBar(
          const SnackBar(content: Text('Starting Sync...')),
        );

        final smsService = context.read<SmsService>();
        if (!context.mounted) return;
        try {
          final count = await smsService.syncFromDate(picked);
          if (context.mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text('Sync Complete. Pushed $count new messages.'),
                backgroundColor: AppTheme.success,
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text('Sync Error: $e'),
                backgroundColor: AppTheme.danger,
              ),
            );
          }
        } finally {
          if (context.mounted) {
            setState(() => _isProcessing = false);
            _loadMessages(); // Refresh list to show status changes
          }
        }
      }
    }
  }

  Future<void> _deepQueryAddress() async {
    final controller = TextEditingController();
    final address = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Deep Search Address"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Enter Sender Address / Number",
          ),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text("Search"),
          ),
        ],
      ),
    );

    if (address != null && address.isNotEmpty && mounted) {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      setState(() => _isLoading = true);
      final smsService = context.read<SmsService>();
      final msgs = await smsService.querySpecificAddress(address);
      if (context.mounted) {
        setState(() {
          _messages = msgs;
          _isLoading = false;
          _filterController.clear(); // Clear local filter to show results
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text("Found ${msgs.length} messages from $address"),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final smsService = context.watch<SmsService>();
    final theme = Theme.of(context);

    // Choose list to display
    final displayList = _filterController.text.isEmpty
        ? _messages
        : _filteredMessages;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('SMS Management'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _filterController,
                    onChanged: (_) => _filterMessages(),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 16,
                    ),
                    decoration: InputDecoration(
                      hintText: "Search SMS...",
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      border: InputBorder.none,
                      prefixIcon: Icon(
                        Icons.search,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadMessages,
              child: _isLoading && _messages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : displayList.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.2,
                        ),
                        Center(
                          child: Text(
                            _filterController.text.isEmpty
                                ? 'No SMS messages found'
                                : 'No matching SMS found',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: displayList.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final msg = displayList[index];
                        final hash = smsService.computeHash(
                          msg.address ?? '',
                          (msg.date ?? 0).toString(),
                          msg.body ?? '',
                        );
                        final isSynced = smsService.isCached(hash);
                        final isSelected = _selectedHashes.contains(hash);

                        return _buildSmsCard(
                          smsService,
                          msg,
                          hash,
                          isSynced,
                          isSelected,
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedHashes.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _isProcessing
                  ? null
                  : () async {
                      bool? confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text("Bulk Push"),
                          content: Text(
                            "Push ${_selectedHashes.length} selected messages to the server?",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text("Cancel"),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text("Proceed"),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        if (!context.mounted) return;
                        _pushBulk();
                      }
                    },
              icon: const Icon(Icons.cloud_upload),
              label: Text("Push (${_selectedHashes.length})"),
              backgroundColor: theme.primaryColor,
              foregroundColor: theme.colorScheme.onPrimary,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
      bottomNavigationBar: BottomAppBar(
        color: theme.colorScheme.surface,
        elevation: 8,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: Icon(
                Icons.saved_search,
                color: theme.colorScheme.onSurface,
              ),
              tooltip: 'Deep Search Address',
              onPressed: _isProcessing ? null : _deepQueryAddress,
            ),
            IconButton(
              icon: Icon(
                Icons.calendar_month,
                color: theme.colorScheme.onSurface,
              ),
              tooltip: 'Sync from Date',
              onPressed: _isProcessing
                  ? null
                  : () async {
                      bool? confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text("Sync from Date"),
                          content: const Text(
                            "This will search and potentially re-sync messages from a chosen date. Proceed?",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text("Cancel"),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text("Proceed"),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        if (!context.mounted) return;
                        _pickAndSyncDate();
                      }
                    },
            ),
            IconButton(
              icon: Icon(
                Icons.cleaning_services_outlined,
                color: AppTheme.danger,
              ),
              tooltip: 'Clear Cache & Force Push All',
              onPressed: _isProcessing
                  ? null
                  : () async {
                      bool? confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text("Force Push All"),
                          content: const Text(
                            "This will clear the local SMS sync cache and push ALL messages in your inbox to the server. This may take a while and cause duplicate notifications. Proceed?",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text("Cancel"),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text(
                                "Proceed",
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;

                      setState(() => _isProcessing = true);
                      if (!context.mounted) return;
                      final messenger = ScaffoldMessenger.of(context);
                      final smsService = context.read<SmsService>();
                      if (!context.mounted) return;
                      try {
                        if (!context.mounted) return;
                        await smsService.clearCache();

                        if (!context.mounted) return;
                        final count = await smsService.pushAllUnsynced();

                        if (context.mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Cleared cache & Pushed $count messages',
                              ),
                            ),
                          );
                          _loadMessages();
                        }
                      } finally {
                        if (mounted) setState(() => _isProcessing = false);
                      }
                    },
            ),
            IconButton(
              icon: Icon(
                Icons.cloud_upload_outlined,
                color: theme.colorScheme.primary,
              ),
              tooltip: 'Push All Unsynced',
              onPressed: _isProcessing
                  ? null
                  : () async {
                      bool? confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text("Push All Unsynced"),
                          content: const Text(
                            "This will send all currently unsynced messages to the backend. Proceed?",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text("Cancel"),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text("Proceed"),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                      if (!context.mounted) return;

                      setState(() => _isProcessing = true);
                      if (!context.mounted) return;
                      final messenger = ScaffoldMessenger.of(context);
                      final smsService = context.read<SmsService>();
                      if (!context.mounted) return;
                      try {
                        if (!context.mounted) return;
                        final count = await smsService.pushAllUnsynced();

                        if (context.mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Pushed $count unsynced messages'),
                            ),
                          );
                          _loadMessages();
                        }
                      } finally {
                        if (mounted) setState(() => _isProcessing = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmsCard(
    SmsService smsService,
    SmsMessage msg,
    String hash,
    bool isSynced,
    bool isSelected,
  ) {
    final theme = Theme.of(context);
    final date = msg.date != null
        ? DateTime.fromMillisecondsSinceEpoch(msg.date!)
        : DateTime.now();
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(date);

    return InkWell(
      onLongPress: () {
        setState(() {
          if (isSelected) {
            _selectedHashes.remove(hash);
          } else {
            _selectedHashes.add(hash);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.primaryColor.withValues(alpha: 0.1)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? theme.primaryColor
                : (isSynced
                      ? AppTheme.success.withValues(alpha: 0.3)
                      : theme.dividerColor),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  msg.address ?? 'Unknown',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (isSynced)
                  Row(
                    children: [
                      const Icon(
                        Icons.cloud_done,
                        color: AppTheme.success,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Synced',
                        style: TextStyle(
                          color: AppTheme.success,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                else if (smsService.isInOfflineQueue(hash))
                  Row(
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        color: AppTheme.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Queued',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      const Icon(
                        Icons.cloud_off,
                        color: AppTheme.warning,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Pending',
                        style: TextStyle(
                          color: AppTheme.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              dateStr,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Hash: ${hash.substring(0, 8)}...",
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),

            // Precision Metadata (Location)
            Builder(
              builder: (context) {
                final metadata = smsService.getMetadata(hash);
                if (metadata == null ||
                    (metadata['lat'] == null && metadata['lng'] == null)) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 10,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${metadata['lat']?.toStringAsFixed(6)}, ${metadata['lng']?.toStringAsFixed(6)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 12),
            Text(
              msg.body ?? '',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : () => _pushSingle(msg),
                icon: Icon(isSynced ? Icons.refresh : Icons.upload, size: 16),
                label: Text(isSynced ? 'Resend' : 'Push Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSynced
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.primaryColor,
                  foregroundColor: isSynced
                      ? theme.colorScheme.onSurfaceVariant
                      : Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: isSynced ? 0 : 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
