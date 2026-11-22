import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../infrastructure/cache/public_profile_cache_service.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../social/data/friends_service.dart';
import '../domain/emergency_contact.dart';
import '../domain/safety_repository.dart';

@immutable
class IncomingEmergencyContactRequest {
  const IncomingEmergencyContactRequest({
    required this.id,
    required this.requesterUserId,
    required this.requesterUsername,
    this.requesterName,
    required this.createdAtUtc,
  });

  final String id;
  final String requesterUserId;
  final String requesterUsername;
  final String? requesterName;
  final DateTime createdAtUtc;

  String get label =>
      (requesterName != null && requesterName!.trim().isNotEmpty)
          ? requesterName!.trim()
          : '@$requesterUsername';
}

/// Sinkronisasi kontak darurat dengan akun Hiqeo lain (permintaan persetujuan
/// via Supabase + notifikasi in-app Realtime & push FCM lewat webhook DB).
class EmergencyContactSyncService extends ChangeNotifier {
  EmergencyContactSyncService._();

  static final EmergencyContactSyncService instance =
      EmergencyContactSyncService._();

  final StreamController<IncomingEmergencyContactRequest> _incomingCtrl =
      StreamController<IncomingEmergencyContactRequest>.broadcast();

  Stream<IncomingEmergencyContactRequest> get onIncomingRequest =>
      _incomingCtrl.stream;

  List<IncomingEmergencyContactRequest> _incomingRequests =
      const <IncomingEmergencyContactRequest>[];
  List<IncomingEmergencyContactRequest> get incomingRequests =>
      _incomingRequests;

  RealtimeChannel? _channel;
  String? _subscribedUserId;

  void ensureRealtimeSubscribed() {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    if (_subscribedUserId == user.id && _channel != null) return;
    unawaited(disposeChannel());
    _subscribedUserId = user.id;

    _channel = client
        .channel('hiqeo_emergency_contacts_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'emergency_contacts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'contact_user_id',
            value: user.id,
          ),
          callback: (payload) async {
            await refreshIncomingRequests();
            final rowId = payload.newRecord['id']?.toString();
            if (rowId != null) {
              for (final req in _incomingRequests) {
                if (req.id == rowId) {
                  _incomingCtrl.add(req);
                  break;
                }
              }
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'emergency_contacts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'contact_user_id',
            value: user.id,
          ),
          callback: (_) => unawaited(refreshIncomingRequests()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'emergency_contacts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'contact_user_id',
            value: user.id,
          ),
          callback: (_) => unawaited(refreshIncomingRequests()),
        )
        .subscribe();
  }

  Future<void> disposeChannel() async {
    final ch = _channel;
    _channel = null;
    _subscribedUserId = null;
    if (ch != null) {
      try {
        await SupabaseServices.clientOrNull?.removeChannel(ch);
      } catch (_) {}
    }
  }

  Future<void> refreshIncomingRequests() async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      _incomingRequests = const <IncomingEmergencyContactRequest>[];
      notifyListeners();
      return;
    }
    try {
      final rows = await client
          .from('emergency_contacts')
          .select('id, user_id, created_at')
          .eq('contact_user_id', user.id)
          .eq('contact_kind', 'hiqeo_account')
          .eq('consent_status', 'pending')
          .order('created_at', ascending: false);

      final requesterIds = <String>{
        for (final r in rows)
          if ((r['user_id']?.toString() ?? '').isNotEmpty)
            r['user_id'].toString(),
      };
      final profs = requesterIds.isNotEmpty
          ? await PublicProfileCacheService.instance.fetchProfiles(
              requesterIds,
              forceRefresh: true,
            )
          : const <String, PublicProfile>{};

      _incomingRequests = rows.map((r) {
        final reqId = r['user_id']?.toString() ?? '';
        final prof = profs[reqId];
        return IncomingEmergencyContactRequest(
          id: r['id']?.toString() ?? '',
          requesterUserId: reqId,
          requesterUsername: prof?.username ?? 'pendaki',
          requesterName: prof?.fullName,
          createdAtUtc:
              DateTime.tryParse(r['created_at']?.toString() ?? '')?.toUtc() ??
                  DateTime.now().toUtc(),
        );
      }).where((r) => r.id.isNotEmpty).toList(growable: false);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> respondToRequest(
    String requestId, {
    required bool accept,
  }) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null) return;
    await client.from('emergency_contacts').update(<String, dynamic>{
      'consent_status': accept ? 'granted' : 'revoked',
      'consent_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', requestId);
    await refreshIncomingRequests();
  }

  Future<EmergencyContact> sendHiqeoAccountRequest({
    required UserSearchResult target,
    required SafetyRepository localRepo,
  }) async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError(
        'Masuk akun dan sambungkan internet untuk mengundang akun Hiqeo.',
      );
    }
    if (target.userId == user.id) {
      throw StateError('Tidak dapat menambahkan diri sendiri.');
    }

    final existing = await client
        .from('emergency_contacts')
        .select('id, consent_status')
        .eq('user_id', user.id)
        .eq('contact_kind', 'hiqeo_account')
        .eq('contact_user_id', target.userId)
        .maybeSingle();
    if (existing != null) {
      final status = existing['consent_status']?.toString();
      if (status == 'granted') {
        throw StateError('@${target.username} sudah aktif sebagai kontak darurat.');
      }
      if (status == 'pending') {
        throw StateError('Permintaan ke @${target.username} masih menunggu.');
      }
      await client
          .from('emergency_contacts')
          .delete()
          .eq('id', existing['id']);
    }

    final inserted = await client
        .from('emergency_contacts')
        .insert(<String, dynamic>{
          'user_id': user.id,
          'name': target.label,
          'contact_kind': 'hiqeo_account',
          'contact_user_id': target.userId,
          'contact_username': target.username,
          'consent_status': 'pending',
        })
        .select('id, created_at')
        .single();

    final contact = EmergencyContact(
      id: inserted['id'].toString(),
      userId: user.id,
      name: target.label,
      phoneE164: '',
      linkedUserId: target.userId,
      linkedUsername: target.username,
      consentStatus: EmergencyContactConsentStatus.pending,
      createdAtUtc:
          DateTime.tryParse(inserted['created_at']?.toString() ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
    );
    await localRepo.saveContact(contact);
    return contact;
  }

  Future<void> syncOutgoingContacts(
    SafetyRepository localRepo,
    String ownerUserId,
  ) async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null || user.id != ownerUserId) return;
    try {
      final rows = await client
          .from('emergency_contacts')
          .select(
            'id, name, contact_user_id, contact_username, consent_status, consent_at, created_at',
          )
          .eq('user_id', user.id)
          .eq('contact_kind', 'hiqeo_account');

      for (final r in rows) {
        final id = r['id']?.toString() ?? '';
        final targetUid = r['contact_user_id']?.toString() ?? '';
        if (id.isEmpty || targetUid.isEmpty) continue;
        final statusStr = r['consent_status']?.toString() ?? 'pending';
        final status = switch (statusStr) {
          'granted' => EmergencyContactConsentStatus.granted,
          'revoked' => EmergencyContactConsentStatus.revoked,
          _ => EmergencyContactConsentStatus.pending,
        };
        await localRepo.saveContact(
          EmergencyContact(
            id: id,
            userId: ownerUserId,
            name: r['name']?.toString() ?? '@${r['contact_username'] ?? 'pendaki'}',
            phoneE164: '',
            linkedUserId: targetUid,
            linkedUsername: r['contact_username']?.toString() ?? 'pendaki',
            consentStatus: status,
            consentAtUtc: DateTime.tryParse(r['consent_at']?.toString() ?? '')
                ?.toUtc(),
            createdAtUtc: DateTime.tryParse(r['created_at']?.toString() ?? '')
                    ?.toUtc() ??
                DateTime.now().toUtc(),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> mirrorPhoneContactToRemote(EmergencyContact contact) async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null || contact.isHiqeoAccount) return;
    try {
      await client.from('emergency_contacts').insert(<String, dynamic>{
        'user_id': user.id,
        'name': contact.name,
        'phone_e164': contact.phoneE164,
        'channel': contact.channel.name,
        'contact_kind': 'phone',
        'consent_status': 'granted',
        'consent_at':
            (contact.consentAtUtc ?? DateTime.now().toUtc()).toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> syncDeleteRemote(String contactId) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null || client.auth.currentUser == null) return;
    // Lewati id lokal non-UUID ('ec-...')
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(contactId)) return;
    try {
      await client.from('emergency_contacts').delete().eq('id', contactId);
    } catch (_) {}
  }
}
