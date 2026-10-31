import 'dart:async';

import 'package:flutter/widgets.dart';

import 'plus_controller.dart';

/// Menyediakan [PlusController] ke seluruh pohon widget dan menyegarkan status
/// lokal setiap aplikasi kembali ke depan.
class PlusScope extends StatefulWidget {
  const PlusScope({super.key, required this.controller, required this.child});

  final PlusController controller;
  final Widget child;

  static PlusController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_PlusScopeInherited>()
      ?.notifier;

  static PlusController of(BuildContext context) {
    final controller = maybeOf(context);
    if (controller == null) {
      throw FlutterError(
        'PlusScope.of dipanggil tanpa PlusScope di atasnya. '
        'Bungkus MaterialApp dengan PlusScope.',
      );
    }
    return controller;
  }

  @override
  State<PlusScope> createState() => _PlusScopeState();
}

class _PlusScopeState extends State<PlusScope> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(widget.controller.refreshAccess());
    unawaited(widget.controller.refreshRemote());
  }

  @override
  Widget build(BuildContext context) => _PlusScopeInherited(
        notifier: widget.controller,
        child: widget.child,
      );
}

class _PlusScopeInherited extends InheritedNotifier<PlusController> {
  const _PlusScopeInherited({
    required super.notifier,
    required super.child,
  });
}
