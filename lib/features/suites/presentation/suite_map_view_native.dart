import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// The 3D suite map in a WebView, loaded from the bundled page in web/three/.
/// Tapping a suite calls [onSuiteTap] with its number.
class SuiteMapView extends StatefulWidget {
  const SuiteMapView({
    super.key,
    required this.sceneData,
    required this.onSuiteTap,
  });

  final Map<String, Object?> sceneData;
  final ValueChanged<String> onSuiteTap;

  @override
  State<SuiteMapView> createState() => _SuiteMapViewState();
}

class _SuiteMapViewState extends State<SuiteMapView> {
  late final WebViewController _controller;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF1EDE4))
      ..addJavaScriptChannel('SuiteMapChannel', onMessageReceived: _onMessage)
      // Only the bundled page may load; never navigate elsewhere.
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => request.url.startsWith('file:')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      )
      ..loadFlutterAsset('web/three/suite_map.html');
  }

  void _onMessage(JavaScriptMessage message) {
    final Object? data;
    try {
      data = jsonDecode(message.message);
    } on FormatException {
      return;
    }
    if (data is! Map) return;
    if (data['type'] == 'cutx-suite-map-ready') {
      _ready = true;
      _sendSceneData();
    } else if (data['type'] == 'cutx-suite-map-select' &&
        data['suite'] is String) {
      widget.onSuiteTap(data['suite'] as String);
    }
  }

  @override
  void didUpdateWidget(covariant SuiteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sceneData != widget.sceneData && _ready) {
      _sendSceneData();
    }
  }

  void _sendSceneData() {
    _controller.runJavaScript(
      'window.cutxSuiteMap.render(${jsonEncode(widget.sceneData)});',
    );
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(
    controller: _controller,
    // Let the map take drags so rotating it does not scroll the page.
    gestureRecognizers: {
      Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
    },
  );
}
