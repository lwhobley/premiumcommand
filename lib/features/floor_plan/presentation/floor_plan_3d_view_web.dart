import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class FloorPlan3DView extends StatefulWidget {
  const FloorPlan3DView({super.key, required this.sceneData});
  final Map<String, Object?> sceneData;

  @override
  State<FloorPlan3DView> createState() => _FloorPlan3DViewState();
}

class _FloorPlan3DViewState extends State<FloorPlan3DView> {
  static const _viewType = 'cutx-floor-plan-3d';
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
        final iframe = web.document.createElement('iframe') as web.HTMLIFrameElement
          ..style.border = '0'
          ..style.width = '100%'
          ..style.height = '100%'
          ..src = Uri.parse(web.document.baseURI).resolve('three/scene.html').toString();
        _frames[viewId] = iframe;
        return iframe;
      });
      _registered = true;
    }
    _messageListener = ((web.Event event) {
      final message = event as web.MessageEvent;
      final data = message.data?.dartify();
      if (message.source == _iframe?.contentWindow &&
          message.origin == web.window.location.origin &&
          data is Map &&
          data['type'] == 'eventtwin-room-scene-ready') {
        _ready = true;
        _sendSceneData();
      }
    }).toJS;
    web.window.addEventListener('message', _messageListener);
  }

  @override
  void didUpdateWidget(covariant FloorPlan3DView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sceneData != widget.sceneData && _ready) {
      _sendSceneData();
    }
  }

  void _sendSceneData() {
    _iframe?.contentWindow?.postMessage({
      'type': 'eventtwin-room-scene',
      'payload': widget.sceneData,
    }.jsify(), web.window.location.origin.toJS);
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
  Widget build(BuildContext context) =>
      SizedBox(height: 480, child: HtmlElementView(
        viewType: _viewType,
        onPlatformViewCreated: (id) {
          _viewId = id;
          _iframe = _frames[id];
        },
      ));
}
