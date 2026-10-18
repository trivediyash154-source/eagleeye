import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

const _viewType = 'eagleeye-cabinet-scene';
bool _registered = false;
final _elements = <int, web.HTMLDivElement>{};
final _listeners = <int, void Function(String)>{};

JSObject? _api() {
  final ready = globalContext.getProperty<JSAny?>('EagleEyeScene'.toJS);
  if (ready != null && ready.isA<JSObject>()) return ready as JSObject;
  final pending = globalContext.getProperty<JSAny?>('EagleEyeScenePending'.toJS);
  if (pending != null && pending.isA<JSObject>()) return pending as JSObject;
  return null;
}

void _register() {
  if (_registered) return;
  _registered = true;
  ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId, {Object? params}) {
    final div = web.HTMLDivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.pointerEvents = 'none';
    _elements[viewId] = div;
    div.addEventListener(
      'eagleeye-scene-status',
      (web.Event e) {
        final detail = (e as web.CustomEvent).detail;
        final s = (detail != null && detail.isA<JSString>()) ? (detail as JSString).toDart : 'error';
        _listeners[viewId]?.call(s);
      }.toJS,
    );
    final reduced = params is Map && params['reduced'] == true;
    final api = _api();
    if (api == null) {
      Future.microtask(() => _listeners[viewId]?.call('error'));
    } else {
      final opts = JSObject()..setProperty('reducedMotion'.toJS, reduced.toJS);
      api.callMethod('mount'.toJS, div, opts);
    }
    return div;
  });
}

Widget buildScene({required bool reducedMotion, required Widget fallback}) => _WebScene(reducedMotion: reducedMotion, fallback: fallback);

class _WebScene extends StatefulWidget {
  const _WebScene({required this.reducedMotion, required this.fallback});
  final bool reducedMotion;
  final Widget fallback;
  @override
  State<_WebScene> createState() => _WebSceneState();
}

class _WebSceneState extends State<_WebScene> {
  int? _viewId;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void dispose() {
    final id = _viewId;
    if (id != null) {
      final el = _elements.remove(id);
      _listeners.remove(id);
      final api = globalContext.getProperty<JSAny?>('EagleEyeScene'.toJS);
      if (el != null && api != null && api.isA<JSObject>()) (api as JSObject).callMethod('unmount'.toJS, el);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback;
    return HtmlElementView(
      viewType: _viewType,
      creationParams: {'reduced': widget.reducedMotion},
      onPlatformViewCreated: (id) {
        _viewId = id;
        _listeners[id] = (status) {
          if ((status == 'unsupported' || status == 'error') && mounted) setState(() => _failed = true);
        };
      },
    );
  }
}
