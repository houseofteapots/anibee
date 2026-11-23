import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anibee/services/flixcloud_decrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.2.11: the flixcloud decrypt (ReAnime) ported from Anivexa's JS
/// extractor to pure Dart — verified against the golden fixture the
/// JS reference produced from a REAL flixcloud embed page. The
/// fixture's token API response is mocked (the live token call 410s
/// from datacenter IPs — on the phone it is the same call the embed
/// page's own JS makes).
void main() {
  late Map<String, dynamic> golden;
  late String embedHtml;

  setUpAll(() {
    golden =
        jsonDecode(
              File('test/fixtures/flixcloud_golden.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    embedHtml = File(
      'test/fixtures/flixcloud_embed.html',
    ).readAsStringSync();
  });

  Uint8List b64(String s) => base64Decode(s);

  test('deriveFlixFields matches the JS reference', () {
    final FlixFields fields = deriveFlixFields(golden['seed'] as String);
    expect(fields.keyField, golden['keyField']);
    expect(fields.ivField, golden['ivField']);
    expect(fields.containerName, golden['containerName']);
    expect(fields.arrayName, golden['arrayName']);
    expect(fields.objectName, golden['objectName']);
    expect(fields.tokenField, golden['tokenField']);
    expect(fields.keyFrag2Field, golden['keyFrag2Field']);
  });

  test('extractSsrData finds the seed + token + wasm payload', () {
    final Map<String, dynamic> data = extractSsrData(embedHtml);
    expect(data['obfuscation_seed'], golden['seed']);
    final FlixFields fields = deriveFlixFields(golden['seed'] as String);
    expect(data[fields.tokenField], golden['token']);
    expect(data['w_payload'], isNotNull);
  });

  test('extractPlaylistKey + WASM transform reproduce the golden', () {
    final Map<String, dynamic> data = extractSsrData(embedHtml);
    final Uint8List wasmPayload = b64(data['w_payload'] as String);
    expect(extractPlaylistKey(wasmPayload), golden['playlistKey']);

    final String token = golden['token'] as String;
    final String tokenKey =
        sha256.convert(utf8.encode('${token}key')).toString().substring(0, 10);
    final Map<String, dynamic> tokenData =
        golden['tokenData'] as Map<String, dynamic>;
    final int seedNumber =
        int.parse((golden['seed'] as String).substring(0, 8), radix: 16);
    final Uint8List wasmOut = runWasmDecrypt(
      wasmBytes: wasmPayload,
      fragment: b64(golden['fragmentB64'] as String),
      keyFragment: b64(golden['keyFragmentB64'] as String),
      tokenBytes: b64(tokenData[tokenKey] as String),
      seed: seedNumber,
    );
    final String hex = wasmOut
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    expect(hex, golden['wasmOutHex']);
    expect(parseWasmTransform(wasmPayload).step, golden['step']);
  });

  test('decryptFlixcloudEmbed end-to-end with mocked token API', () async {
    final Map<String, dynamic> tokenData =
        golden['tokenData'] as Map<String, dynamic>;
    final FlixcloudStream stream = await decryptFlixcloudEmbed(
      embedHtml: embedHtml,
      fetchTokenJson: (String token) async {
        expect(token, golden['token']);
        return tokenData;
      },
    );
    expect(stream.url, golden['expectedUrl']);
    expect(stream.playlistKey, golden['playlistKey']);
  });

  test('decryptFlixVideoUrl throws nothing on garbage, embeds throw', () {
    expect(
      () => extractSsrData('<html>no ssr data here</html>'),
      throwsA(isA<FlixcloudException>()),
    );
    expect(
      () async => decryptFlixcloudEmbed(
        embedHtml: '<html>no ssr data here</html>',
        fetchTokenJson: (String _) async => <String, dynamic>{},
      ),
      throwsA(isA<FlixcloudException>()),
    );
  });
}
