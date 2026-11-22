import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/infrastructure/storage/r2_uploader.dart';

void main() {
  final bytes = Uint8List.fromList(<int>[1, 2, 3]);

  test('meminta izin lalu PUT dengan header yang ditandatangani', () async {
    Map<String, dynamic>? asked;
    Map<String, String>? sentHeaders;
    final uploader = R2Uploader(
      presign: (body) async {
        asked = body;
        return <String, dynamic>{
          'uploadUrl': 'https://r2.example/avatars/u.webp?sig=1',
          'publicUrl': 'https://cdn.example/avatars/u.webp?v=1',
          'headers': <String, String>{'content-type': 'image/webp'},
        };
      },
      put: (url, headers, data) async {
        sentHeaders = headers;
        return 200;
      },
    );
    final url = await uploader.upload(
      kind: R2Kind.avatar,
      bytes: bytes,
      contentType: 'image/webp',
    );
    expect(url, 'https://cdn.example/avatars/u.webp?v=1');
    expect(asked, <String, dynamic>{
      'kind': 'avatar',
      'contentType': 'image/webp',
      'size': 3,
    });
    expect(sentHeaders, <String, String>{'content-type': 'image/webp'});
  });

  test('melempar error bila R2 menolak PUT', () async {
    final uploader = R2Uploader(
      presign: (_) async => <String, dynamic>{
        'uploadUrl': 'https://r2.example/x',
        'publicUrl': 'https://cdn.example/x',
      },
      put: (_, __, ___) async => 403,
    );
    expect(
      () => uploader.upload(
        kind: R2Kind.communityMedia,
        bytes: bytes,
        contentType: 'video/mp4',
        communityId: 'c',
      ),
      throwsStateError,
    );
  });
}
