import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// The 3D suite map in an iframe. Tapping a suite calls [onSuiteTap] with its number.
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
  static const _viewType = 'cutx-suite-map-3d';
  static final _frames = <int, web.HTMLIFrameElement>{};
  static bool _registered = false;
  int? _viewId;
  web.HTMLIFrameElement? _iframe;
  JSFunction? _messageListener;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    if (!_registered) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final iframe =
            web.document.createElement('iframe') as web.HTMLIFrameElement
              ..title = 'Premium level suite map'
              ..style.border = '0'
              ..style.width = '100%'
              ..style.height = '100%'
              ..src = Uri.parse(web.document.baseURI)
                  .resolve('three/suite_map.html')
                  .toString();
        _frames[viewId] = iframe;
        return iframe;
      });
      _registered = true;
    }
    _messageListener = ((web.Event event) {
      final message = event as web.MessageEvent;
      final data = message.data?.dartify();
      if (message.source != _iframe?.contentWindow ||
          message.origin != web.window.location.origin ||
          data is! Map) {
        return;
      }
      if (data['type'] == 'cutx-suite-map-ready') {
        _ready = true;
        _sendSceneData();
      } else if (data['type'] == 'cutx-suite-map-select' &&
          data['suite'] is String) {
        widget.onSuiteTap(data['suite'] as String);
      }
    }).toJS;
    web.window.addEventListener('message', _messageListener);
  }

  @override
  void didUpdateWidget(covariant SuiteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sceneData != widget.sceneData && _ready) {
      _sendSceneData();
    }
  }

  void _sendSceneData() {
    _iframe?.contentWindow?.postMessage(
      {'type': 'cutx-suite-map-scene', 'payload': widget.sceneData}.jsify(),
      web.window.location.origin.toJS,
    );
  }

  @override
  void dispose() {
    if (_messageListener != null) {
      web.window.removeEventListener('message', _messageListener);
    }
    if (_viewId != null) _frames.remove(_viewId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(
    viewType: _viewType,
    onPlatformViewCreated: (id) {
      _viewId = id;
      _iframe = _frames[id];
    },
  );
}
