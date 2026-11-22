import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../data/community_service.dart';

enum CameraCaptureMode { photo, video }

@immutable
class CapturedMediaResult {
  const CapturedMediaResult({
    required this.file,
    required this.isVideo,
    this.durationSec,
  });

  final File file;
  final bool isVideo;
  final int? durationSec;
}

/// Layar kamera full-screen khusus Chat Komunitas:
/// - Kiri atas: Kembali
/// - Kanan atas: Senter (Flashlight)
/// - Bawah tengah: Tombol Shutter / Rekam
/// - Di bawah tombol shutter: label mode `Video` (kiri) & `Foto` (tengah);
///   mengetuk `Video` menggeser `Video` mulus ke tengah & `Foto` ke kanan.
/// - Bawah kiri: Galeri (foto / video maks. 60 dtk)
/// - Bawah kanan: Ganti kamera depan/belakang
class CommunityCameraPage extends StatefulWidget {
  const CommunityCameraPage({super.key});

  @override
  State<CommunityCameraPage> createState() => _CommunityCameraPageState();
}

class _CommunityCameraPageState extends State<CommunityCameraPage>
    with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();

  List<CameraDescription> _cameras = const <CameraDescription>[];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _initializing = true;
  String? _cameraError;

  CameraCaptureMode _mode = CameraCaptureMode.photo;
  bool _torchOn = false;
  bool _isRecording = false;
  bool _busy = false;
  int _recordedSeconds = 0;
  Timer? _recordTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initCameras());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      unawaited(controller.dispose());
      _controller = null;
    } else if (state == AppLifecycleState.resumed && _cameras.isNotEmpty) {
      unawaited(_setupCamera(_cameraIndex));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordTimer?.cancel();
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _initCameras() async {
    try {
      final list = await availableCameras();
      if (!mounted) return;
      if (list.isEmpty) {
        setState(() {
          _initializing = false;
          _cameraError = 'Kamera tidak tersedia di perangkat ini.';
        });
        return;
      }
      _cameras = list;
      final backIdx = list.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      _cameraIndex = backIdx >= 0 ? backIdx : 0;
      await _setupCamera(_cameraIndex);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityCameraPage open failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _cameraError =
            'Kamera tidak dapat dibuka. Periksa izin kamera di perangkat.';
      });
    }
  }

  Future<void> _setupCamera(int index) async {
    setState(() {
      _initializing = true;
      _cameraError = null;
      _torchOn = false;
    });
    final prev = _controller;
    _controller = null;
    await prev?.dispose();

    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.medium,
      enableAudio: true,
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityCameraPage._setupCamera failed: $e');
      }
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _cameraError =
            'Kamera belum siap digunakan. Coba buka ulang halaman ini.';
      });
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final next = !_torchOn;
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = next);
    } catch (_) {
      // Kamera depan umumnya tidak memiliki senter.
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _isRecording || _busy) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _setupCamera(_cameraIndex);
  }

  Future<void> _onShutterPressed() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;

    if (_mode == CameraCaptureMode.photo) {
      setState(() => _busy = true);
      try {
        final xfile = await controller.takePicture();
        if (!mounted) return;
        Navigator.of(context).pop(
          CapturedMediaResult(file: File(xfile.path), isVideo: false),
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('CommunityCameraPage takePicture failed: $e');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Foto belum bisa diambil. Coba lagi.'),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    // Mode Video (maks. 60 detik)
    if (_isRecording) {
      await _stopVideoRecording();
    } else {
      await _startVideoRecording();
    }
  }

  Future<void> _startVideoRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.prepareForVideoRecording();
      await controller.startVideoRecording();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordedSeconds = 0;
      });
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _recordedSeconds++);
        if (_recordedSeconds >= CommunityService.maxVideoDurationSec) {
          timer.cancel();
          unawaited(_stopVideoRecording());
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityCameraPage startVideo failed: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rekaman video belum bisa dimulai. Coba lagi.'),
          ),
        );
      }
    }
  }

  Future<void> _stopVideoRecording() async {
    final controller = _controller;
    if (controller == null || !_isRecording) return;
    _recordTimer?.cancel();
    _recordTimer = null;
    setState(() => _busy = true);
    try {
      final xfile = await controller.stopVideoRecording();
      final duration = _recordedSeconds.clamp(
        1,
        CommunityService.maxVideoDurationSec,
      );
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _busy = false;
      });
      Navigator.of(context).pop(
        CapturedMediaResult(
          file: File(xfile.path),
          isVideo: true,
          durationSec: duration,
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityCameraPage stopVideo failed: $e');
      }
      if (mounted) {
        setState(() {
          _isRecording = false;
          _busy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video belum bisa disimpan. Coba rekam ulang.'),
          ),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isRecording || _busy) return;
    setState(() => _busy = true);
    try {
      if (_mode == CameraCaptureMode.photo) {
        final picked = await _picker.pickImage(source: ImageSource.gallery);
        if (picked != null && mounted) {
          Navigator.of(context).pop(
            CapturedMediaResult(file: File(picked.path), isVideo: false),
          );
          return;
        }
      } else {
        final picked = await _picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(
            seconds: CommunityService.maxVideoDurationSec,
          ),
        );
        if (picked != null) {
          final file = File(picked.path);
          final durationSec = await _probeVideoDurationSec(file);
          if (!mounted) return;
          if (durationSec > CommunityService.maxVideoDurationSec) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Durasi video maksimal 60 detik.'),
              ),
            );
            return;
          }
          Navigator.of(context).pop(
            CapturedMediaResult(
              file: file,
              isVideo: true,
              durationSec: durationSec,
            ),
          );
          return;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityCameraPage._pickFromGallery failed: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Galeri belum bisa dibuka. Periksa izin penyimpanan.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<int> _probeVideoDurationSec(File file) async {
    final vp = VideoPlayerController.file(file);
    try {
      await vp.initialize();
      final secs = vp.value.duration.inSeconds;
      return secs <= 0 ? 1 : secs;
    } catch (_) {
      return 1;
    } finally {
      await vp.dispose();
    }
  }

  String _formatTimer(int secs) {
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final controller = _controller;
    final isVideo = _mode == CameraCaptureMode.video;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Preview Kamera Full-Screen
          if (controller != null && controller.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: 1 / controller.value.aspectRatio,
                child: CameraPreview(controller),
              ),
            )
          else if (_initializing)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _cameraError ?? 'Kamera tidak tersedia.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
            ),

          // Kiri atas: Kembali
          Positioned(
            top: topPad + 12,
            left: 16,
            child: _CameraControlBackdrop(
              child: IconButton(
                key: const ValueKey('camera-back-button'),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                tooltip: 'Kembali',
              ),
            ),
          ),

          // Tengah atas: Timer perekaman saat merekam video
          if (_isRecording)
            Positioned(
              top: topPad + 18,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_formatTimer(_recordedSeconds)} / 01:00',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),

          // Kanan atas: Senter (Flashlight)
          Positioned(
            top: topPad + 12,
            right: 16,
            child: _CameraControlBackdrop(
              child: IconButton(
                key: const ValueKey('camera-flash-button'),
                onPressed: _toggleTorch,
                icon: Icon(
                  _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: _torchOn ? Colors.amberAccent : Colors.white,
                  size: 26,
                ),
                tooltip: _torchOn ? 'Matikan senter' : 'Nyalakan senter',
              ),
            ),
          ),

          // Area kontrol bawah: Galeri (kiri), Shutter/Rekam (tengah), Flip (kanan),
          // dan pengalih mode Video / Foto tepat di bawah tombol Shutter.
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPad + 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      // Bawah kiri: Galeri
                      _CameraControlBackdrop(
                        child: IconButton(
                          key: const ValueKey('camera-gallery-button'),
                          onPressed: _isRecording ? null : _pickFromGallery,
                          icon: const Icon(
                            Icons.photo_library_outlined,
                            color: Colors.white,
                            size: 30,
                          ),
                          tooltip: 'Pilih dari galeri',
                        ),
                      ),

                      // Bawah tengah: Tombol Shutter / Rekam
                      GestureDetector(
                        key: const ValueKey('camera-shutter-button'),
                        onTap: _onShutterPressed,
                        child: Container(
                          width: 76,
                          height: 76,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: isVideo ? Colors.redAccent : Colors.white,
                              borderRadius: BorderRadius.circular(
                                _isRecording ? 12 : 999,
                              ),
                            ),
                            margin: EdgeInsets.all(_isRecording ? 14 : 2),
                          ),
                        ),
                      ),

                      // Bawah kanan: Ganti kamera depan/belakang
                      _CameraControlBackdrop(
                        child: IconButton(
                          key: const ValueKey('camera-flip-button'),
                          onPressed: _isRecording ? null : _flipCamera,
                          icon: const Icon(
                            Icons.cameraswitch_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                          tooltip: 'Ganti kamera',
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Label mode di bawah Shutter:
                // Default: "Video" di kiri, "Foto" di tengah.
                // Saat "Video" diketuk: "Video" bergeser mulus ke tengah, "Foto" ke kanan.
                SizedBox(
                  height: 36,
                  width: 240,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        alignment: isVideo
                            ? Alignment.center
                            : const Alignment(-0.72, 0),
                        child: GestureDetector(
                          key: const ValueKey('camera-mode-video'),
                          behavior: HitTestBehavior.opaque,
                          onTap: _isRecording
                              ? null
                              : () => setState(
                                    () => _mode = CameraCaptureMode.video,
                                  ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Text(
                              'Video',
                              style: TextStyle(
                                fontSize: isVideo ? 15 : 13.5,
                                fontWeight:
                                    isVideo ? FontWeight.w700 : FontWeight.w500,
                                color: isVideo
                                    ? Colors.amberAccent
                                    : Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      ),
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        alignment: isVideo
                            ? const Alignment(0.72, 0)
                            : Alignment.center,
                        child: GestureDetector(
                          key: const ValueKey('camera-mode-photo'),
                          behavior: HitTestBehavior.opaque,
                          onTap: _isRecording
                              ? null
                              : () => setState(
                                    () => _mode = CameraCaptureMode.photo,
                                  ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Text(
                              'Foto',
                              style: TextStyle(
                                fontSize: !isVideo ? 15 : 13.5,
                                fontWeight: !isVideo
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: !isVideo
                                    ? Colors.amberAccent
                                    : Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraControlBackdrop extends StatelessWidget {
  const _CameraControlBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.58),
      shape: CircleBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
