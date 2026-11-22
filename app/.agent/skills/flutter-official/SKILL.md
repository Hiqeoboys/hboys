---
name: flutter-official
description: Official guidelines for Flutter/Dart architecture, widgets, state management, 120fps performance, and layout. Use when writing, refactoring, or auditing Flutter code.
---
# Flutter & Dart Engineering Guidelines

## 1. Widget Composition & Code Structure
- Break complex UI into small, isolated `StatelessWidget` or `StatefulWidget` classes. Avoid helper methods (`Widget _buildCard()`) that return widgets, because they prevent Flutter from optimizing rebuilds and the `Element` tree.
- Use a `const` constructor on every widget and static value where possible to reduce memory allocation and excessive rebuilds.
- Separate business logic, API/database calls, and data transformations from the `build()` method. The `build()` method must be pure and fast.

## 2. Layout, Constraints, & Responsiveness
- Understand the principle *"Constraints go down. Sizes go up. Parent sets position."*
- Never place a `ListView` or `Expanded` directly inside a `Column` or `SingleChildScrollView` without bounded constraints.
- For elements that fit their content width (such as chat bubbles or badges), use `ConstrainedBox(maxWidth: ...)` or `IntrinsicWidth`, and avoid widgets that accidentally stretch to full width.
- Always use `SafeArea` and `MediaQuery.viewInsetsOf(context)` / `MediaQuery.paddingOf(context)` (not `MediaQuery.of(context)`) so widgets do not rebuild excessively when the viewport size changes.

## 3. Theme, Styling, & Typography
- Centralize all color tokens, radii, spacing, and glass styles using `ThemeData` and `ThemeExtension`. Avoid repeated hardcoded hex colors inside page files.
- Use modern color properties such as `color.withValues(alpha: ...)` instead of the *deprecated* `withOpacity(...)`.
- Handle dynamic text with `maxLines` and `overflow: TextOverflow.ellipsis` on title/card rows to avoid `RenderFlex overflow`.

## 4. 120Hz Rendering Performance & Animation
- Avoid using the `Opacity` widget or `BackdropFilter` inside items of a `ListView` / `SingleChildScrollView` that is continuously scrolled, because it triggers repeated `saveLayer` calls on the GPU. Use color transparency directly and isolate animations with `RepaintBoundary`.
- Always `dispose()` every `TextEditingController`, `ScrollController`, `AnimationController`, and `StreamSubscription` inside `dispose()`.
- Limit the decode size of network/asset images using `cacheWidth` / `cacheHeight` matching the display dimensions on screen.

## 5. Async Handling & Null Safety
- Always check `if (!mounted) return;` before using `BuildContext` or calling `setState()` after an `await` operation.
- Use `dart format` and make sure there are 0 errors/warnings in `flutter analyze` for the modified files.