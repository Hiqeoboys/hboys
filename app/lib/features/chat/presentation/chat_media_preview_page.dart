import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../design/widgets/hiqeo_back_button.dart';
import 'chat_room_chrome.dart';

/// Hasil konfirmasi pratinjau media kamera sebelum dikirim ke ruang obrolan.
@immutable
class CapturedMediaSubmission {
  const CapturedMediaSubmission({
    required this.file,
    required this.isVideo,
    this.durationSec,
    this.caption,
  });

  final File file;
  final bool isVideo;
  final int? durationSec;
  final String? caption;
}

/// Layar pratinjau layar penuh setelah mengambil foto/video dari kamera chat.
///
/// Pengguna dapat memeriksa hasil tangkapan, memutar video, atau menambahkan
/// keterangan (*caption*) sebelum mengirim, atau menekan tombol kembali untuk
/// membatalkan pengiriman.
class ChatMediaPreviewPage extends StatefulWidget {
  const ChatMediaPreviewPage({
    super.key,
    required this.file,
    required this.isVideo,
    this.durationSec,
  });

  final File file;
  final bool isVideo;
  final int? durationSec;

  @override
  State<ChatMediaPreviewPage> createState() => _ChatMediaPreviewPageState();
}

class _ChatMediaPreviewPageState extends State<ChatMediaPreviewPage> {
  final TextEditingController _captionCtrl = TextEditingController();
  VideoPlayerController? _videoCtrl;
  bool _videoInitialized = false;
  bool _videoPlaying = false;
  int? _resolvedDurationSec;

  @override
  void initState() {
    super.initState();
    _resolvedDurationSec = widget.durationSec;
    if (widget.isVideo) {
      unawaited(_initVideo());
    }
  }

  Future<void> _initVideo() async {
    VideoPlayerController? c;
    try {
      c = VideoPlayerController.file(widget.file);
      await c.initialize();
      await c.seekTo(Duration.zero);
      await c.pause();
      if (!mounted) {
        unawaited(c.dispose().catchError((Object _) {}));
        return;
      }
      final secs = c.value.duration.inSeconds;
      if (secs > 0) {
        _resolvedDurationSec = secs;
      }
      c.addListener(_onVideoTick);
      setState(() {
        _videoCtrl = c;
        _videoInitialized = true;
        _videoPlaying = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ChatMediaPreviewPage video init failed: $e');
      }
      if (c != null) {
        unawaited(c.dispose().catchError((Object _) {}));
      }
    }
  }

  void _onVideoTick() {
    final c = _videoCtrl;
    if (c == null || !mounted) return;
    final val = c.value;
    if (_videoPlaying != val.isPlaying) {
      setState(() => _videoPlaying = val.isPlaying);
    } else if (val.isPlaying) {
      setState(() {});
    }
  }

  Future<void> _togglePlayPause() async {
    final c = _videoCtrl;
    if (c == null || !_videoInitialized) return;
    try {
      if (c.value.isPlaying) {
        await c.pause();
      } else {
        if (c.value.duration > Duration.zero &&
            c.value.position >=
                c.value.duration - const Duration(milliseconds: 120)) {
          await c.seekTo(Duration.zero);
        }
        await c.play();
      }
    } catch (_) {}
  }

  void _submit() {
    final trimmed = _captionCtrl.text.trim();
    Navigator.of(context).pop(
      CapturedMediaSubmission(
        file: widget.file,
        isVideo: widget.isVideo,
        durationSec: _resolvedDurationSec,
        caption: trimmed.isEmpty ? null : trimmed,
      ),
    );
  }

  String _formatDuration(Duration d) {
    final totalSec = d.inSeconds.clamp(0, 3599);
    final mm = (totalSec ~/ 60).toString().padLeft(2, '0');
    final ss = (totalSec % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    final c = _videoCtrl;
    if (c != null) {
      c.removeListener(_onVideoTick);
      unawaited(c.dispose().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final composerBottom =
        (keyboardInset > 0 ? keyboardInset : safeBottom) + 12;

    final c = _videoCtrl;
    final totalDuration = _videoInitialized && c != null
        ? c.value.duration
        : Duration(seconds: _resolvedDurationSec ?? 0);
    final posDuration = _videoInitialized && c != null
        ? c.value.position
        : Duration.zero;
    final durationLabel = _videoPlaying && totalDuration > Duration.zero
        ? '${_formatDuration(posDuration)} / ${_formatDuration(totalDuration)}'
        : _formatDuration(totalDuration);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 1. Media utama layar penuh di tengah
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(bottom: composerBottom + 70),
              child: widget.isVideo
                  ? GestureDetector(
                      key: const ValueKey<String>('media-preview-video-area'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => unawaited(_togglePlayPause()),
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          if (_videoInitialized && c != null)
                            Center(
                              child: AspectRatio(
                                aspectRatio: c.value.aspectRatio > 0
                                    ? c.value.aspectRatio
                                    : 16 / 9,
                                child: VideoPlayer(c),
                              ),
                            )
                          else
                            const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          if (!_videoPlaying)
                            Container(
                              key: const ValueKey<String>(
                                'media-preview-play-button',
                              ),
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white70),
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          Positioned(
                            top: topPad + 18,
                            right: 16,
                            child: Container(
                              key: const ValueKey<String>(
                                'media-preview-duration',
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.62),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.22),
                                ),
                              ),
                              child: Text(
                                durationLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  fontFeatures: <FontFeature>[
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : InteractiveViewer(
                      key: const ValueKey<String>(
                        'media-preview-interactive-viewer',
                      ),
                      minScale: 1.0,
                      maxScale: 3.5,
                      child: Center(
                        child: Image.file(
                          widget.file,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
            ),
          ),

          // 2. Kiri atas: tombol kembali Liquid Glass untuk batal kirim
          Positioned(
            top: topPad + 10,
            left: 14,
            child: HiqeoBackButton(
              key: const ValueKey<String>('media-preview-back'),
              brightness: Brightness.dark,
              onTap: () => Navigator.of(context).pop(null),
            ),
          ),

          // 3. Bawah (di atas keyboard / SafeArea): pil caption putih solid + tombol kirim
          Positioned(
            left: 14,
            right: 14,
            bottom: composerBottom,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: ChatSolidComposerPill(
                    key: const ValueKey<String>('media-preview-caption-pill'),
                    borderRadius: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 50),
                      child: Center(
                        child: TextField(
                          key: const ValueKey<String>(
                            'media-preview-caption-input',
                          ),
                          controller: _captionCtrl,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 500,
                          textCapitalization: TextCapitalization.sentences,
                          cursorColor: ChatSolidComposerPill.textColor,
                          style: const TextStyle(
                            fontSize: 14.5,
                            color: ChatSolidComposerPill.textColor,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Tambahkan keterangan...',
                            hintStyle: TextStyle(
                              color: ChatSolidComposerPill.hintColor,
                              fontSize: 14,
                            ),
                            counterText: '',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ChatSolidSendButton(
                  key: const ValueKey<String>('media-preview-send'),
                  semanticsLabel: 'Kirim media',
                  size: 50,
                  enabled: true,
                  sending: false,
                  onTap: _submit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
