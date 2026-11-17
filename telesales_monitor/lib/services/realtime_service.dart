import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

import 'api_service.dart';

class RealtimeService {
  static sio.Socket? _socket;
  static String _token = '';
  static VoidCallback? _onReconnected;
  static final Map<String, List<void Function(dynamic)>> _eventHandlers = {};

  static String _socketBaseUrl() {
    final api = Uri.parse(ApiService.baseUrl);
    final path = api.path.replaceFirst(RegExp(r'/api/?$'), '');
    return api
        .replace(path: path, query: null, fragment: null)
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }

  static void on(String event, void Function(dynamic) handler) {
    _eventHandlers.putIfAbsent(event, () => []).add(handler);
    _socket?.on(event, handler);
  }

  static void off(String event, [void Function(dynamic)? handler]) {
    if (handler != null) {
      _eventHandlers[event]?.remove(handler);
      _socket?.off(event, handler);
    } else {
      _eventHandlers.remove(event);
      _socket?.off(event);
    }
  }

  static void connect(String token, {VoidCallback? onReconnected}) {
    if (token.isEmpty) return;
    if (_socket != null && _token == token) {
      _onReconnected = onReconnected;
      return;
    }
    disconnect();

    _token = token;
    _onReconnected = onReconnected;
    var connectedBefore = false;
    final socket = sio.io(
      _socketBaseUrl(),
      sio.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );
    _socket = socket;

    _eventHandlers.forEach((evt, handlers) {
      for (final h in handlers) {
        socket.on(evt, h);
      }
    });

    socket.onConnect((_) {
      debugPrint('Realtime socket connected');
      if (connectedBefore) _onReconnected?.call();
      connectedBefore = true;
    });
    socket.onConnectError((error) {
      debugPrint('Realtime socket connection failed: $error');
    });
    socket.onDisconnect((_) {
      debugPrint('Realtime socket disconnected');
    });
    socket.connect();
  }

  static void disconnect() {
    _socket?.dispose();
    _socket = null;
    _token = '';
    _onReconnected = null;
  }
}
