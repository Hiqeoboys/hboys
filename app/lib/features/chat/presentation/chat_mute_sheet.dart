import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../design/tokens.dart';
import '../../../infrastructure/notifications/push_notification_service.dart';
import '../../social/data/chat_mute_service.dart';
import 'chat_room_chrome.dart';

/// Mengembalikan label ringkas sisa waktu mute untuk subtitle menu, atau string
/// kosong bila notifikasi aktif.
String chatMuteStatusShortLabel(
  ChatMuteService service,
  String roomType,
  String roomId, {
  DateTime? nowUtc,
}) {
  final now = (nowUtc ?? DateTime.now()).toUtc();
  if (!service.isMuted(roomType, roomId, nowUtc: now)) return '';
  if (service.isMutedForever(roomType, roomId)) return 'Selamanya';
  final until = service.mutedUntil(roomType, roomId);
  if (until == null) return '';
  final diff = until.difference(now);
  if (diff.inDays >= 1) return '${diff.inDays} hari lagi';
  if (diff.inHours >= 1) return '${diff.inHours} jam lagi';
  return 'Aktif sementara';
}

enum _MuteChoice { off, oneDay, oneWeek, forever }

/// Menampilkan modal pilihan Liquid Glass dengan tepat 4 opsi mute notifikasi
/// per ruang obrolan (`Mati`, `1 hari`, `1 minggu`, `Selamanya`).
Future<void> showChatMuteSheet(
  BuildContext context, {
  required String roomType,
  required String roomId,
  required String roomName,
  ChatMuteService? muteService,
}) {
  final service = muteService ?? ChatMuteService.instance;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _ChatMuteSheetContent(
      roomType: roomType,
      roomId: roomId,
      roomName: roomName,
      service: service,
    ),
  );
}

class _ChatMuteSheetContent extends StatelessWidget {
  const _ChatMuteSheetContent({
    required this.roomType,
    required this.roomId,
    required this.roomName,
    required this.service,
  });

  final String roomType;
  final String roomId;
  final String roomName;
  final ChatMuteService service;

  _MuteChoice _currentChoice(DateTime nowUtc) {
    if (!service.isMuted(roomType, roomId, nowUtc: nowUtc)) {
      return _MuteChoice.off;
    }
    if (service.isMutedForever(roomType, roomId)) {
      return _MuteChoice.forever;
    }
    final until = service.mutedUntil(roomType, roomId);
    if (until != null && until.difference(nowUtc).inHours > 36) {
      return _MuteChoice.oneWeek;
    }
    return _MuteChoice.oneDay;
  }

  Future<void> _selectChoice(BuildContext context, _MuteChoice choice) async {
    unawaited(HapticFeedback.selectionClick());
    switch (choice) {
      case _MuteChoice.off:
        await service.unmute(roomType, roomId);
      case _MuteChoice.oneDay:
        await service.muteFor(roomType, roomId, const Duration(days: 1));
        await PushNotificationService.instance.clearRoomNotifications(
          type: roomType,
          id: roomId,
        );
      case _MuteChoice.oneWeek:
        await service.muteFor(roomType, roomId, const Duration(days: 7));
        await PushNotificationService.instance.clearRoomNotifications(
          type: roomType,
          id: roomId,
        );
      case _MuteChoice.forever:
        await service.muteForever(roomType, roomId);
        await PushNotificationService.instance.clearRoomNotifications(
          type: roomType,
          id: roomId,
        );
    }
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final nowUtc = DateTime.now().toUtc();
    final current = _currentChoice(nowUtc);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + safeBottom),
      child: HiqeoLiquidGlassSurface(
        key: const ValueKey<String>('chat-mute-modal-sheet'),
        borderRadius: 28,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ChatRoomPalette.textSecondary.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Bisukan notifikasi',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: ChatRoomPalette.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Atur notifikasi untuk "$roomName". Sinyal darurat SOS tetap masuk.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: ChatRoomPalette.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              _MuteOptionTile(
                tileKey: const ValueKey<String>('mute-option-off'),
                label: 'Mati',
                subtitle: 'Notifikasi aktif seperti biasa',
                selected: current == _MuteChoice.off,
                onTap: () => unawaited(_selectChoice(context, _MuteChoice.off)),
              ),
              const SizedBox(height: 8),
              _MuteOptionTile(
                tileKey: const ValueKey<String>('mute-option-1d'),
                label: '1 hari',
                subtitle: 'Bisukan selama 24 jam',
                selected: current == _MuteChoice.oneDay,
                onTap: () =>
                    unawaited(_selectChoice(context, _MuteChoice.oneDay)),
              ),
              const SizedBox(height: 8),
              _MuteOptionTile(
                tileKey: const ValueKey<String>('mute-option-1w'),
                label: '1 minggu',
                subtitle: 'Bisukan selama 7 hari',
                selected: current == _MuteChoice.oneWeek,
                onTap: () =>
                    unawaited(_selectChoice(context, _MuteChoice.oneWeek)),
              ),
              const SizedBox(height: 8),
              _MuteOptionTile(
                tileKey: const ValueKey<String>('mute-option-forever'),
                label: 'Selamanya',
                subtitle: 'Dibisukan sampai kamu mengubahnya kembali',
                selected: current == _MuteChoice.forever,
                onTap: () =>
                    unawaited(_selectChoice(context, _MuteChoice.forever)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MuteOptionTile extends StatelessWidget {
  const _MuteOptionTile({
    required this.tileKey,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final Key tileKey;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return InkWell(
      key: tileKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? colors.primary
                : Colors.white.withValues(alpha: 0.14),
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: ChatRoomPalette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ChatRoomPalette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 20,
              color: selected ? colors.primary : ChatRoomPalette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
