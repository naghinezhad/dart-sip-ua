import '../../sip_ua.dart';
import '../grammar.dart';
import '../logger.dart';
import 'socket_interface.dart';

import 'websocket_dart_impl.dart'
    if (dart.library.js) 'websocket_web_impl.dart';

class SIPUAWebSocket extends SIPUASocketInterface {
  SIPUAWebSocket(String url,
      {required int messageDelay,
      WebSocketSettings? webSocketSettings,
      int? weight})
      : _messageDelay = messageDelay {
    logger.d('new() [url:$url]');
    _url = url;
    _weight = weight;
    dynamic parsed_url = Grammar.parse(url, 'absoluteURI');
    if (parsed_url == -1) {
      logger.e('invalid WebSocket URI: $url');
      throw AssertionError('Invalid argument: $url');
    } else if (parsed_url.scheme != 'wss' && parsed_url.scheme != 'ws') {
      logger.e('invalid WebSocket URI scheme: ${parsed_url.scheme}');
      throw AssertionError('Invalid argument: $url');
    } else {
      String transport_scheme = webSocketSettings != null &&
              webSocketSettings.transport_scheme != null
          ? webSocketSettings.transport_scheme!.toLowerCase()
          : parsed_url.scheme;

      String port = parsed_url.port != null ? ':${parsed_url.port}' : '';
      _sip_uri = 'sip:${parsed_url.host}$port;transport=$transport_scheme';
      logger.d('SIP URI: $_sip_uri');
      _via_transport = transport_scheme.toUpperCase();
    }
    _webSocketSettings = webSocketSettings ?? WebSocketSettings();
  }
  final int _messageDelay;

  String? _url;
  String? _sip_uri;
  late String _via_transport;
  final String _websocket_protocol = 'sip';
  SIPUAWebSocketImpl? _ws;
  bool _closed = false;
  bool _connected = false;
  int? _weight;
  int? status;
  late WebSocketSettings _webSocketSettings;

  @override
  String get via_transport => _via_transport;

  @override
  set via_transport(String value) {
    _via_transport = value.toUpperCase();
  }

  @override
  String? get sip_uri => _sip_uri;

  @override
  int? get weight => _weight;

  @override
  String? get url => _url;

  @override
  void connect() async {
    logger.d('connect()');

    if (_url == null) {
      throw AssertionError('Invalid argument: _url');
    }

    if (isConnected()) {
      logger.d('WebSocket $_url is already connected');
      return;
    } else if (isConnecting()) {
      logger.d('WebSocket $_url is connecting');
      return;
    }
    if (_ws != null) {
      disconnect();
    }
    logger.d('connecting to WebSocket $_url');
    try {
      _ws = SIPUAWebSocketImpl(_url!, _messageDelay);

      _ws!.onOpen = () {
        _closed = false;
        _connected = true;
        logger.d('Web Socket is now connected');
        _onOpen();
      };

      _ws!.onMessage = (dynamic data) {
        _onMessage(data);
      };

      _ws!.onClose = (int? closeCode, String? closeReason) {
        logger.d('Closed [$closeCode, $closeReason]!');
        _connected = false;
        _onClose(true, closeCode, closeReason);
      };

      _ws!.connect(
          protocols: <String>[_websocket_protocol],
          webSocketSettings: _webSocketSettings);
    } catch (e, s) {
      logger.e(e.toString(), error: e, stackTrace: s);
      _connected = false;
      logger.e('WebSocket $_url error: $e');
    }
  }

  @override
  void disconnect() {
    logger.d('disconnect()');
    if (_closed) return;
    // Don't wait for the WebSocket 'close' event, do it now.
    _closed = true;
    _connected = false;
    _onClose(true, 0, 'Client send disconnect');
    try {
      if (_ws != null) {
        _ws!.close();
      }
    } catch (error) {
      logger.e('close() | error closing the WebSocket: $error');
    }
  }

  @override
  bool send(dynamic message) {
    logger.d('send()');
    if (_closed) {
      throw 'transport closed';
    }
    try {
      _ws!.send(message);
      return true;
    } catch (error) {
      logger.e('send() | error sending message: $error');
      rethrow;
    }
  }

  @override
  bool isConnected() {
    return _connected;
  }

  @override
  bool isConnecting() {
    return _ws != null && _ws!.isConnecting();
  }

  /**
   * WebSocket Event Handlers
   */
  void _onOpen() {
    logger.d('WebSocket $_url connected');
    onconnect!();
  }

  void _onClose(bool wasClean, int? code, String? reason) {
    logger.d('WebSocket $_url closed');
    if (wasClean == false) {
      logger.d('WebSocket abrupt disconnection');
    }
    ondisconnect!(this, !wasClean, code, reason);
  }

  void _onMessage(dynamic data) {
    logger.d('Received WebSocket message');
    if (data != null) {
      if (data.toString().trim().isNotEmpty) {
        ondata!(data);
      } else {
        logger.d('Received and ignored empty packet');
      }
    }
  }
}
