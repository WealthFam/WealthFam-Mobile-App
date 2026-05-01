import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/core/services/notification_service.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/core/utils/logger.dart';

class SocketService extends ChangeNotifier {
  final AppConfig _config;
  final AuthService _auth;
  final NotificationService _notifications;
  final DashboardService _dashboard;

  WebSocketChannel? _channel;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  bool get isConnected => _isConnected;

  SocketService(this._config, this._auth, this._notifications, this._dashboard);

  void connect() {
    if (_isConnected || _auth.accessToken == null || _auth.tenantId == null) return;

    // Build URL ultra-robustly
    var rawUrl = _config.backendUrl.trim();
    
    // Parse to ensure we only have the base part (strip fragments/paths if accidentally added)
    final baseUri = Uri.parse(rawUrl);
    var host = baseUri.host;
    var port = baseUri.port;
    var scheme = baseUri.scheme;

    // Use default IP if parsing fails (fallback)
    if (host.isEmpty) {
      if (rawUrl.contains('://')) {
        final parts = rawUrl.split('://');
        scheme = parts[0];
        final hostPort = parts[1].split('/')[0].split('#')[0];
        if (hostPort.contains(':')) {
          host = hostPort.split(':')[0];
          port = int.tryParse(hostPort.split(':')[1]) ?? 8000;
        } else {
          host = hostPort;
          port = 8000;
        }
      }
    }

    // Convert scheme to ws/wss
    final wsScheme = scheme.contains('https') ? 'wss' : 'ws';
    
    // Construct the clean final URI
    final finalWsUri = Uri(
      scheme: wsScheme,
      host: host,
      port: port,
      path: '/ws/${_auth.tenantId}',
      queryParameters: {'token': _auth.accessToken},
    );

    final wsUrl = finalWsUri.toString();

    AppLogger.info('SocketService: Connecting to $host:$port');
    AppLogger.debug('SocketService Full URL: $wsUrl');
    
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      _channel!.stream.listen(
        (message) {
          if (!_isConnected) {
            _isConnected = true;
            _reconnectAttempts = 0; // Reset attempts on success
            notifyListeners();
          }
          _handleMessage(message);
        },
        onDone: () {
          AppLogger.info('SocketService: Connection closed');
          _isConnected = false;
          notifyListeners();
          _scheduleReconnect();
        },
        onError: (error) {
          AppLogger.error('SocketService: WebSocket error', error);
          _isConnected = false;
          notifyListeners();
          _scheduleReconnect();
        },
      );
    } catch (e) {
      AppLogger.error('SocketService: Initial connection failed', e);
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      AppLogger.debug('SocketService: Message: $data');

      if (data['type'] == 'NOTIFICATION') {
        final payload = data['payload'];
        final title = payload['title'] ?? 'WealthFam Alert';
        final body = payload['body'] ?? '';
        
        // Safely parse ID which might be a string from backend
        final rawId = payload['id'];
        final int notificationId = rawId is int 
            ? rawId 
            : (int.tryParse(rawId?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch % 100000);

        // Show local notification
        _notifications.showNotification(
          title: title,
          body: body,
          id: notificationId,
        );

        // Refresh dashboard to reflect changes if it was a transaction/budget update
        _dashboard.refresh();
      }
    } catch (e) {
      AppLogger.error('SocketService: Message parse error', e);
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    
    // Bug 7 Fix: Exponential Backoff
    final delaySeconds = (5 * (1 << _reconnectAttempts)).clamp(5, 300); // 5s, 10s, 20s... max 5m
    AppLogger.info('SocketService: Reconnecting in ${delaySeconds}s (attempt ${_reconnectAttempts + 1})');
    
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_isConnected && _auth.isAuthenticated) {
        _reconnectAttempts++;
        connect();
      }
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
