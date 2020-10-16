import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:async';
import 'package:sip_ua/src/sip_ua_helper.dart';

import '../logger.dart';
import '../grammar.dart';

typedef void OnMessageCallback(dynamic msg);
typedef void OnCloseCallback(int code, String reason);
typedef void OnOpenCallback();

class WebSocketImpl {
  final String _url;
  WebSocket _socket;

  OnOpenCallback onOpen;
  OnMessageCallback onMessage;
  OnCloseCallback onClose;
  WebSocketImpl(this._url);

  void connect(
      {Iterable<String> protocols, WebSocketSettings webSocketSettings}) async {
    logger.info('connect $_url, ${webSocketSettings.extraHeaders}, $protocols');
    try {
      if (webSocketSettings.allowBadCertificate) {
        /// Allow self-signed certificate, for test only.
        _socket = await _connectForBadCertificate(_url, webSocketSettings);
      } else {
        _socket = await WebSocket.connect(_url,
            protocols: protocols, headers: webSocketSettings.extraHeaders);
      }

      onOpen?.call();
      _socket.listen((data) {
        onMessage?.call(data);
      }, onDone: () {
        onClose?.call(_socket.closeCode, _socket.closeReason);
      });
    } catch (e) {
      onClose?.call(500, e.toString());
    }
  }

  void send(data) {
    if (_socket != null) {
      _socket.add(data);
      logger.debug('send: \n\n$data');
    }
  }

  void close() {
    _socket.close();
  }

  bool isConnecting() {
    return _socket != null && _socket.readyState == WebSocket.connecting;
  }

  /// For test only.
  Future<WebSocket> _connectForBadCertificate(
      String url, WebSocketSettings webSocketSettings) async {
    try {
      var r = Random();
      var key = base64.encode(List<int>.generate(16, (_) => r.nextInt(255)));
      var securityContext = SecurityContext();
      var client = HttpClient(context: securityContext);

      if (webSocketSettings.userAgent != null) {
        client.userAgent = webSocketSettings.userAgent;
      }

      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        logger.warn('Allow self-signed certificate => $host:$port. ');
        return true;
      };

      var parsed_uri = Uri.parse(url);
      var uri = parsed_uri.replace(
          scheme: parsed_uri.scheme == 'wss' ? 'https' : 'http');

      var request = await client.getUrl(uri); // form the correct url here
      request.headers.add('Connection', 'Upgrade', preserveHeaderCase: true);
      request.headers.add('Upgrade', 'websocket', preserveHeaderCase: true);
      request.headers.add('Sec-WebSocket-Version', '13',
          preserveHeaderCase: true); // insert the correct version here
      request.headers.add('Sec-WebSocket-Key', key.toLowerCase(),
          preserveHeaderCase: true);
      request.headers
          .add('Sec-WebSocket-Protocol', 'sip', preserveHeaderCase: true);

      webSocketSettings.extraHeaders.forEach((key, value) {
        request.headers.add(key, value, preserveHeaderCase: true);
      });

      var response = await request.close();
      var socket = await response.detachSocket();
      var webSocket = WebSocket.fromUpgradedSocket(
        socket,
        protocol: 'sip',
        serverSide: false,
      );

      return webSocket;
    } catch (e) {
      logger.error('error $e');
      throw e;
    }
  }
}
