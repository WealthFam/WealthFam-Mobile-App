import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/modules/home/models/unparsed_message.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/modules/ingestion/widgets/forensic_annotation_form.dart';

class NeuralTrainingScreen extends StatefulWidget {
  const NeuralTrainingScreen({super.key});

  @override
  State<NeuralTrainingScreen> createState() => _NeuralTrainingScreenState();
}

class _NeuralTrainingScreenState extends State<NeuralTrainingScreen> {
  List<UnparsedMessage> _messages = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  bool _showSpamOnly = false;
  List<dynamic> _spamFilters = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    if (!mounted) return;
    final dashboard = context.read<DashboardService>();
    if (!mounted) return;

    final result = await dashboard.fetchTrainingQueue(search: _searchQuery);

    if (mounted) {
      result.fold(
        (failure) => setState(() {
          _isLoading = false;
        }),
        (messages) async {
          _messages = messages;
          if (_showSpamOnly) {
            await _loadSpamFilters();
          }
          setState(() => _isLoading = false);
        },
      );
    }
  }

  Future<void> _loadSpamFilters() async {
    if (!mounted) return;
    final dashboard = context.read<DashboardService>();
    if (!mounted) return;
    final result = await dashboard.fetchSpamFilters();

    result.fold(
      (failure) => debugPrint('Error loading spam filters: ${failure.message}'),
      (filters) {
        if (mounted) {
          setState(() => _spamFilters = filters);
        }
      },
    );
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    Color? confirmColor,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            content: Text(message, style: const TextStyle(fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor ?? AppTheme.danger,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                child: Text(
                  confirmLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _markAsSpam(String msgId) async {
    final confirm = await _showConfirmDialog(
      title: 'Declare as Spam?',
      message:
          'This will block the sender and automatically ignore all future messages matching this pattern.',
      confirmLabel: 'Mark as Spam',
    );
    if (!confirm) return;

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final dashboard = context.read<DashboardService>();
    if (!mounted) return;
    final result = await dashboard.markAsSpam(msgId);

    result.fold(
      (failure) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      },
      (_) {
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(content: Text('Marked as Spam')));
        _loadData();
        dashboard.refresh();
      },
    );
  }

  Future<void> _bulkIgnore(List<String> ids) async {
    final confirm = await _showConfirmDialog(
      title: 'Ignore All Messages?',
      message:
          'You are about to dismiss ${ids.length} messages. This action cannot be undone.',
      confirmLabel: 'Ignore All',
    );
    if (!confirm) return;

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final dashboard = context.read<DashboardService>();
    if (!mounted) return;
    final result = await dashboard.bulkIgnore(ids);

    result.fold(
      (failure) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      },
      (_) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Ignored ${ids.length} messages')),
        );
        _loadData();
        dashboard.refresh();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count =
        context.watch<DashboardService>().data?.pendingTrainingCount ?? 0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  hintText: 'Search senders or content...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (v) {
                  setState(() => _searchQuery = v);
                  _loadData();
                },
              )
            : Text(
                'Neural Training ($count)',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
        actions: [
          if (!_showSpamOnly)
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchQuery = '';
                    _searchController.clear();
                    _loadData();
                  }
                });
              },
            ),
          IconButton(
            icon: Icon(
              _showSpamOnly
                  ? Icons.mark_email_read
                  : Icons.report_gmailerrorred,
            ),
            tooltip: 'View Spam Bucket',
            onPressed: () {
              setState(() {
                _showSpamOnly = !_showSpamOnly;
                _isSearching = false;
              });
              _loadData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _showSpamOnly
          ? _buildSpamList()
          : _buildTrainingList(),
    );
  }

  final Set<String> _expandedGroups = {};

  Widget _buildTrainingList() {
    if (_messages.isEmpty) {
      return _buildEmptyState(
        'Fully Trained',
        'No new unparsed messages found.',
      );
    }

    final Map<String, List<UnparsedMessage>> groups = {};
    for (var m in _messages) {
      String key = m.sender ?? 'Unlabeled';
      if (m.subject != null && m.subject!.isNotEmpty) {
        key += " (${m.subject})";
      } else if (m.sender == null) {
        final fingerprint = m.content.length > 20
            ? '${m.content.substring(0, 20)}...'
            : m.content;
        key = "Pattern: $fingerprint";
      }

      groups.putIfAbsent(key, () => []).add(m);
    }

    final sortedKeys = groups.keys.toList()
      ..sort((a, b) => groups[b]!.length.compareTo(groups[a]!.length));

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: sortedKeys.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final patternKey = sortedKeys[index];
          final groupMessages = groups[patternKey]!;

          if (groupMessages.length > 1) {
            return _buildGroupTile(patternKey, groupMessages);
          } else {
            return _buildMessageCard(groupMessages[0]);
          }
        },
      ),
    );
  }

  Widget _buildGroupTile(String patternKey, List<UnparsedMessage> cluster) {
    final theme = Theme.of(context);
    final isUnlabeled = patternKey.startsWith('Pattern:');
    final isExpanded = _expandedGroups.contains(patternKey);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppTheme.warning.withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.warning.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(
              () => isExpanded
                  ? _expandedGroups.remove(patternKey)
                  : _expandedGroups.add(patternKey),
            ),
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isUnlabeled
                          ? Icons.fingerprint
                          : Icons.auto_awesome_motion,
                      color: AppTheme.warning,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patternKey,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${cluster.length} matching patterns • Tap to ${isExpanded ? 'collapse' : 'view all'}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () =>
                        _bulkIgnore(cluster.map((m) => m.id).toList()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.danger.withValues(alpha: 0.1),
                      foregroundColor: AppTheme.danger,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    child: const Text(
                      'Ignore All',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            ...cluster.map(
              (m) => Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                child: _buildMessageCard(
                  m,
                  isInsideGroup: true,
                  isClipped: false,
                ),
              ),
            ),
          ] else ...[
            const Divider(height: 1),
            _buildMessageCard(cluster[0], isInsideGroup: true, isClipped: true),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageCard(
    UnparsedMessage item, {
    bool isInsideGroup = false,
    bool isClipped = false,
  }) {
    final theme = Theme.of(context);
    final displayContent = isClipped && item.content.length > 80
        ? '${item.content.substring(0, 80)}...'
        : item.content;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isInsideGroup ? Colors.transparent : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: isInsideGroup
            ? null
            : Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: isInsideGroup
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isInsideGroup)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: (item.source == 'SMS' ? Colors.blue : Colors.orange)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    item.source == 'SMS' ? Icons.sms : Icons.email,
                    color: (item.source == 'SMS' ? Colors.blue : Colors.orange),
                    size: 14,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.sender ?? 'Unlabeled Source',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                Text(
                  DateFormat('MMM d, HH:mm').format(item.receivedAt),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          if (!isInsideGroup) const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.05),
              ),
            ),
            child: Text(
              displayContent,
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 12,
                height: 1.5,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.report_gmailerrorred, size: 16),
                label: const Text(
                  'Declare Spam',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                onPressed: () => _markAsSpam(item.id),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 36),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final confirm = await _showConfirmDialog(
                    title: 'Dismiss Message?',
                    message:
                        'This pattern will be ignored and removed from the training queue.',
                    confirmLabel: 'Dismiss',
                  );
                  if (!confirm) return;

                  if (!mounted) return;
                  final messenger = ScaffoldMessenger.of(context);
                  final dashboardService = context.read<DashboardService>();
                  if (!mounted) return;
                  final result = await dashboardService.dismissTraining(
                    item.id,
                  );

                  result.fold(
                    (f) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(content: Text(f.message)),
                      );
                    },
                    (_) {
                      if (!mounted) return;
                      _loadData();
                    },
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.7),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text(
                  'Dismiss',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => ForensicAnnotationForm(
                      message: item,
                      onComplete: () => _loadData(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 8,
                  shadowColor: AppTheme.primary.withValues(alpha: 0.4),
                  minimumSize: const Size(90, 36),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                child: const Text(
                  'Annotate',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpamList() {
    final theme = Theme.of(context);
    if (_spamFilters.isEmpty) {
      return _buildEmptyState(
        'Spam Free!',
        'No blocked senders or subjects yet.',
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: AppTheme.danger.withValues(alpha: 0.05),
          child: Row(
            children: [
              const Icon(Icons.security, color: AppTheme.danger, size: 16),
              const SizedBox(width: 12),
              Text(
                'SPAM PROTECTION ACTIVE',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  color: AppTheme.danger.withValues(alpha: 0.8),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _spamFilters.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final filter = _spamFilters[index];
              return ListTile(
                tileColor: theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const Icon(
                  Icons.block,
                  color: AppTheme.danger,
                  size: 20,
                ),
                title: Text(
                  filter['sender'] ?? filter['subject'] ?? 'Auto-Filter',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  'Blocked ${filter['count_blocked'] ?? 0} times',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final dashboard = context.read<DashboardService>();
                    final confirm = await _showConfirmDialog(
                      title: 'Remove Spam Filter?',
                      message:
                          'This will allow messages from this sender/subject to reach your training queue again.',
                      confirmLabel: 'Remove',
                    );
                    if (!confirm) return;

                    if (!mounted) return;
                    if (!mounted) return;
                    final result = await dashboard.deleteSpamFilter(
                      filter['id'],
                    );
                    if (!mounted) return;
                    result.fold(
                      (f) => messenger.showSnackBar(
                        SnackBar(content: Text(f.message)),
                      ),
                      (_) => _loadData(),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_awesome,
            size: 80,
            color: AppTheme.primary.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          Text(subtitle, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
