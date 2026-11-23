import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import 'miruro_resolver.dart';

/// flixcloud.cc stream decrypt — pure-Dart port of the community
/// reverse-engineering (Anivexa `extractors/flixcloud.js`, successor
/// of walterwhite-69/ReAnime.to-API `decrypt.mjs`).
///
/// The important discovery in that work: the rotating WASM payload
/// does NOT need a WASM runtime. Everything is statically derived:
///
/// 1. The embed page's SSR data block carries an
///    `obfuscation_seed`; SHA-256 chains of the seed name the
///    obfuscated fields (key fragment 1, IV, key fragment 2, token).
/// 2. `GET https://flixcloud.cc/api/m3u8/{token}` returns two base64
///    fields (named by sha256(token + "vid"/"key")[:10]).
/// 3. The WASM payload's DATA section hides a 64-byte segment whose
///    two 32-byte halves XOR to a playlist key, and its CODE section
///    holds a tiny byte-transform (a ~10-opcode stack machine) plus a
///    keystream step. A small interpreter replays it — no WASM
///    execution, so it works on-device in Dart.
/// 4. PBKDF2-SHA256 (1000 iters) over the transform output, XOR with
///    the seed chars, SHA-256, then AES-256-CBC decrypts the video
///    bytes into the real master.m3u8 URL.
///
/// Nothing here is faked: every step is verified against the JS
/// reference on a real flixcloud embed (see
/// test/flixcloud_decrypt_test.dart + test/fixtures/).
/// The one step the VM cannot verify live is the token API call
/// itself — flixcloud rejects datacenter IPs with 410
/// "invalid_or_used_token" (Anivexa's README documents the same
/// datacenter-IP block). On a phone (residential IP) it is the same
/// call the embed page's own JS makes. The phone test is the
/// authority for end-to-end playback.
class FlixcloudException implements Exception {
  const FlixcloudException(this.message);

  final String message;

  @override
  String toString() => 'FlixcloudException: $message';
}

/// Decrypted flixcloud stream.
class FlixcloudStream {
  const FlixcloudStream({
    required this.url,
    this.playlistKey,
    this.subtitles = const <SubtitleInfo>[],
    this.thumbnailsVtt,
    this.videoTitle,
    this.introChapter,
    this.outroChapter,
    this.videoId,
  });

  /// The real master.m3u8 URL.
  final String url;

  /// Playlist key from the WASM data section (base64, may be needed
  /// by the playlist fetcher; null when the payload had none).
  final String? playlistKey;

  final List<SubtitleInfo> subtitles;
  final String? thumbnailsVtt;
  final String? videoTitle;
  final dynamic introChapter;
  final dynamic outroChapter;
  final String? videoId;
}

/// Field names derived from the obfuscation seed.
class FlixFields {
  const FlixFields({
    required this.keyField,
    required this.ivField,
    required this.containerName,
    required this.arrayName,
    required this.objectName,
    required this.tokenField,
    required this.keyFrag2Field,
  });

  final String keyField;
  final String ivField;
  final String containerName;
  final String arrayName;
  final String objectName;
  final String tokenField;
  final String keyFrag2Field;
}

/// Derive the obfuscated field names from the embed's seed.
/// Pure — unit-tested against the JS reference.
FlixFields deriveFlixFields(String seed) {
  String first = seed;
  for (int i = 0; i < 3; i++) {
    first = sha256.convert(utf8.encode('$first$i')).toString();
  }
  String second = first;
  for (int i = 0; i < 3; i++) {
    second = sha256.convert(utf8.encode('$second$i')).toString();
  }
  return FlixFields(
    keyField: 'kf_${first.substring(8, 16)}',
    ivField: 'ivf_${first.substring(16, 24)}',
    containerName: 'cd_${first.substring(24, 32)}',
    arrayName: 'ad_${first.substring(32, 40)}',
    objectName: 'od_${first.substring(40, 48)}',
    tokenField: '${first.substring(48, 64)}_${first.substring(56, 64)}',
    keyFrag2Field:
        '${second.substring(0, 16)}_${second.substring(16, 24)}',
  );
}

/// Extract + parse the SSR data object out of a flixcloud embed page.
/// Throws [FlixcloudException] when the block is missing/unparseable.
Map<String, dynamic> extractSsrData(String html) {
  final RegExpMatch? match =
      RegExp(r'\{type:"data",data:(\{)').firstMatch(html);
  if (match == null) {
    throw const FlixcloudException('SSR data block not found');
  }
  int depth = 0;
  final int start = html.indexOf('{', match.start + match[0]!.length - 1);
  for (int i = start; i < html.length; i++) {
    if (html[i] == '{') {
      depth++;
    } else if (html[i] == '}') {
      if (--depth == 0) {
        final dynamic parsed = parseJsLiteral(html.substring(start, i + 1));
        if (parsed is Map<String, dynamic>) return parsed;
        throw const FlixcloudException('SSR data is not an object');
      }
    }
  }
  throw const FlixcloudException('SSR brace matching failed');
}

/// Minimal JS-object-literal parser (the SSR block is JS, not JSON:
/// unquoted keys, single quotes, `!0`/`!1`, `undefined`).
/// Port of the reference `parseJsLiteral`. Pure — unit-tested.
dynamic parseJsLiteral(String source) {
  return _JsLiteralParser(source).parse();
}

class _JsLiteralParser {
  _JsLiteralParser(this._source);

  final String _source;
  int _index = 0;

  dynamic parse() => _value();

  void _whitespace() {
    while (_index < _source.length &&
        _source[_index].trim().isEmpty) {
      _index++;
    }
  }

  String _doubleString() {
    String out = '';
    _index++; // opening "
    while (_index < _source.length && _source[_index] != '"') {
      if (_source[_index] == '\\') {
        _index++;
        final String c = _source[_index];
        out += switch (c) {
          'n' => '\n',
          't' => '\t',
          'r' => '\r',
          '"' => '"',
          '\\' => '\\',
          _ => c,
        };
        _index++;
      } else {
        out += _source[_index++];
      }
    }
    _index++; // closing "
    return out;
  }

  String _singleString() {
    String out = '';
    _index++; // opening '
    while (_index < _source.length && _source[_index] != "'") {
      if (_source[_index] == '\\') {
        _index++;
        final String c = _source[_index];
        out += switch (c) {
          "'" => "'",
          'n' => '\n',
          't' => '\t',
          'r' => '\r',
          '\\' => '\\',
          _ => c,
        };
        _index++;
      } else {
        out += _source[_index++];
      }
    }
    _index++; // closing '
    return out;
  }

  String _key() {
    _whitespace();
    if (_source[_index] == '"') return _doubleString();
    if (_source[_index] == "'") return _singleString();
    final RegExpMatch? match = RegExp(
      r'^[a-zA-Z_$][a-zA-Z0-9_$]*',
    ).firstMatch(_source.substring(_index));
    if (match == null) {
      throw FlixcloudException(
        'Bad key at pos $_index: ${_source.substring(_index, _index + 20 > _source.length ? _source.length : _index + 20)}',
      );
    }
    _index += match[0]!.length;
    return match[0]!;
  }

  Map<String, dynamic> _object() {
    final Map<String, dynamic> out = <String, dynamic>{};
    _index++; // {
    _whitespace();
    while (_index < _source.length && _source[_index] != '}') {
      if (_source[_index] == ',') {
        _index++;
        _whitespace();
        continue;
      }
      final String property = _key();
      _whitespace();
      _index++; // :
      out[property] = _value();
      _whitespace();
    }
    _index++; // }
    return out;
  }

  List<dynamic> _array() {
    final List<dynamic> out = <dynamic>[];
    _index++; // [
    _whitespace();
    while (_index < _source.length && _source[_index] != ']') {
      if (_source[_index] == ',') {
        _index++;
        _whitespace();
        continue;
      }
      out.add(_value());
      _whitespace();
    }
    _index++; // ]
    return out;
  }

  dynamic _value() {
    _whitespace();
    if (_source[_index] == '{') return _object();
    if (_source[_index] == '[') return _array();
    if (_source[_index] == '"') return _doubleString();
    if (_source[_index] == "'") return _singleString();
    if (_source.startsWith('true', _index)) {
      _index += 4;
      return true;
    }
    if (_source.startsWith('false', _index)) {
      _index += 5;
      return false;
    }
    if (_source.startsWith('null', _index)) {
      _index += 4;
      return null;
    }
    if (_source.startsWith('undefined', _index)) {
      _index += 9;
      return null;
    }
    if (_source.startsWith('!0', _index)) {
      _index += 2;
      return true;
    }
    if (_source.startsWith('!1', _index)) {
      _index += 2;
      return false;
    }
    final RegExpMatch? match = RegExp(
      r'^-?[\d.]+([eE][+-]?\d+)?',
    ).firstMatch(_source.substring(_index));
    if (match != null) {
      _index += match[0]!.length;
      return double.parse(match[0]!);
    }
    throw FlixcloudException(
      'JS parse error at pos $_index: ...${_source.substring(_index, _index + 20 > _source.length ? _source.length : _index + 20)}',
    );
  }
}

/// Read one unsigned LEB128 value starting at [position].
/// Returns (value, nextPosition).
(int, int) _readLeb(Uint8List bytes, int position) {
  int value = 0;
  int shift = 0;
  int next;
  do {
    next = bytes[position++];
    value |= (next & 127) << shift;
    shift += 7;
  } while ((next & 128) != 0);
  return (value, position);
}

/// Base64 decode tolerant of missing padding / URL-safe alphabet.
Uint8List _b64(String value) {
  final String normalized =
      value.replaceAll('-', '+').replaceAll('_', '/');
  final String padded =
      normalized + '=' * ((4 - normalized.length % 4) % 4);
  return base64Decode(padded);
}

/// Playlist key hidden in the WASM payload's data section (section
/// 11): the first >= 64-byte segment, first 32 bytes XOR next 32.
/// Returns base64, or null when no such segment exists.
String? extractPlaylistKey(Uint8List wasmBytes) {
  int position = 8;
  while (position < wasmBytes.length) {
    final int section = wasmBytes[position++];
    final (int size, int nextPosition) = _readLeb(wasmBytes, position);
    position = nextPosition;
    if (section == 11) {
      final int end = position + size;
      int dataPosition = position;
      final (int count, int countPosition) =
          _readLeb(wasmBytes, dataPosition);
      dataPosition = countPosition;
      for (int i = 0; i < count && dataPosition < end; i++) {
        final (_, int flagsPosition) = _readLeb(wasmBytes, dataPosition);
        dataPosition = flagsPosition;
        if (wasmBytes[dataPosition] != 65) break;
        dataPosition++;
        final (_, int offsetPosition) = _readLeb(wasmBytes, dataPosition);
        dataPosition = offsetPosition;
        if (wasmBytes[dataPosition] == 11) dataPosition++;
        final (int dataLength, int lengthPosition) =
            _readLeb(wasmBytes, dataPosition);
        dataPosition = lengthPosition;
        final Uint8List segment = wasmBytes.sublist(
          dataPosition,
          dataPosition + dataLength,
        );
        dataPosition += dataLength;
        if (segment.length >= 64) {
          final Uint8List out = Uint8List(32);
          for (int j = 0; j < 32; j++) {
            out[j] = segment[j] ^ segment[j + 32];
          }
          return base64Encode(out);
        }
      }
    }
    position += size;
  }
  return null;
}

/// The byte-transform extracted from the WASM code section: a tiny
/// stack machine over ~10 opcodes plus a keystream step. Port of the
/// reference `parseWasmDecrypt`.
class FlixWasmTransform {
  FlixWasmTransform(this.step, this._code);

  final int step;
  final Uint8List _code;

  int transform(int inputByte) {
    int local = inputByte & 255;
    final List<int> stack = <int>[];
    int index = 0;
    while (index < _code.length) {
      final int opcode = _code[index++];
      if (opcode == 32) {
        // local.get
        final (int localIndex, int nextIndex) = _readLeb(_code, index);
        index = nextIndex;
        stack.add(localIndex == 6 ? local : 0);
      } else if (opcode == 33) {
        // local.set
        final (int localIndex, int nextIndex) = _readLeb(_code, index);
        index = nextIndex;
        final int value = stack.removeLast();
        if (localIndex == 6) local = value & 255;
      } else if (opcode == 65) {
        // i32.const
        final (int value, int nextIndex) = _readLeb(_code, index);
        index = nextIndex;
        stack.add(value);
      } else if (opcode == 106) {
        // i32.add
        final int right = stack.removeLast();
        final int left = stack.removeLast();
        stack.add((left + right) & 255);
      } else if (opcode == 107) {
        // i32.sub
        final int right = stack.removeLast();
        final int left = stack.removeLast();
        stack.add((left - right + 256) & 255);
      } else if (opcode == 113) {
        // i32.and
        final int right = stack.removeLast();
        final int left = stack.removeLast();
        stack.add((left & right) & 255);
      } else if (opcode == 114) {
        // i32.or
        final int right = stack.removeLast();
        final int left = stack.removeLast();
        stack.add((left | right) & 255);
      } else if (opcode == 115) {
        // i32.xor
        final int right = stack.removeLast();
        final int left = stack.removeLast();
        stack.add((left ^ right) & 255);
      } else if (opcode == 116) {
        // i32.shl
        final int right = stack.removeLast();
        final int left = stack.removeLast();
        stack.add((left << (right & 7)) & 255);
      } else if (opcode == 118) {
        // i32.shr_u
        final int right = stack.removeLast();
        final int left = stack.removeLast();
        stack.add((left >> (right & 7)) & 255);
      }
      // Any other opcode is ignored, exactly like the reference
      // interpreter (unknown opcodes fall through).
    }
    return local;
  }
}

/// Parse the WASM code section and extract the transform + keystream
/// step. The transform lives in the second function body: the code
/// section's first function is skipped, the second is scanned for
/// the XOR-transform signature `[32,2,32,5,106,45,0,0,115,33,6]`.
FlixWasmTransform parseWasmTransform(Uint8List bytes) {
  int position = 8;
  while (position < bytes.length) {
    final int section = bytes[position++];
    final (int size, int nextPosition) = _readLeb(bytes, position);
    position = nextPosition;
    if (section == 10) {
      // Code section: one count byte, then skip the first function.
      position++;
      final (int bodySize, int bodyPosition) = _readLeb(bytes, position);
      position = bodyPosition + bodySize;
      break;
    }
    position += size;
  }
  final (int functionSize, int functionPosition) =
      _readLeb(bytes, position);
  position = functionPosition;
  final Uint8List body = bytes.sublist(position, position + functionSize);

  const List<int> xorEnd = <int>[32, 2, 32, 5, 106, 45, 0, 0, 115, 33, 6];
  int transformStart = -1;
  outer:
  for (int i = 0; i < body.length - xorEnd.length; i++) {
    for (int j = 0; j < xorEnd.length; j++) {
      if (body[i + j] != xorEnd[j]) continue outer;
    }
    transformStart = i + xorEnd.length;
    break;
  }
  if (transformStart < 0) {
    throw const FlixcloudException('WASM: transform start not found');
  }
  int transformEnd = -1;
  int step = 36;
  for (int i = transformStart; i < body.length - 4; i++) {
    if (body[i] == 32 && body[i + 1] == 5 && body[i + 2] == 65) {
      final (int value, int nextIndex) = _readLeb(body, i + 3);
      if (body[nextIndex] == 108) {
        transformEnd = i;
        step = value;
        break;
      }
    }
  }
  if (transformEnd < 0) {
    throw const FlixcloudException('WASM: keystream not found');
  }
  final Uint8List code = body.sublist(transformStart, transformEnd);
  return FlixWasmTransform(step, code);
}

/// The WASM's key-derivation step, replayed in Dart: each byte is
/// `transform(fragment[i] ^ keyFragment[i] ^ tokenBytes[i])` XOR the
/// keystream `(i * step + seed) & 255`. Pure — unit-tested against
/// the JS reference on real embed data.
Uint8List runWasmDecrypt({
  required Uint8List wasmBytes,
  required Uint8List fragment,
  required Uint8List keyFragment,
  required Uint8List tokenBytes,
  required int seed,
}) {
  if (fragment.length != keyFragment.length ||
      fragment.length != tokenBytes.length) {
    throw const FlixcloudException(
      'WASM inputs must all be the same length',
    );
  }
  final FlixWasmTransform parsed = parseWasmTransform(wasmBytes);
  final Uint8List out = Uint8List(fragment.length);
  for (int i = 0; i < fragment.length; i++) {
    final int value =
        (fragment[i] ^ keyFragment[i] ^ tokenBytes[i]) & 255;
    out[i] = parsed.transform(value) ^ (((i * parsed.step + seed) & 255));
  }
  return out;
}

/// PBKDF2-SHA256 (1000 iters) over [wasmOut] with the seed as salt,
/// XOR with the seed chars, SHA-256, then AES-256-CBC decrypt of
/// [videoBytes] with [iv]. Returns the plaintext URL string.
String decryptFlixVideoUrl({
  required Uint8List wasmOut,
  required String seed,
  required Uint8List iv,
  required Uint8List videoBytes,
}) {
  final PBKDF2KeyDerivator derivator =
      PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  derivator.init(
    Pbkdf2Parameters(Uint8List.fromList(utf8.encode(seed)), 1000, 32),
  );
  final Uint8List derived = derivator.process(wasmOut);
  for (int i = 0; i < 32; i++) {
    derived[i] ^= seed.codeUnitAt(i % seed.length);
  }
  final Uint8List aesKeyBytes =
      Uint8List.fromList(sha256.convert(derived).bytes);
  final PaddedBlockCipherImpl cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  );
  cipher.init(
    false,
    PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
      ParametersWithIV<KeyParameter>(KeyParameter(aesKeyBytes), iv),
      null,
    ),
  );
  final Uint8List plain = cipher.process(videoBytes);
  return utf8
      .decode(plain)
      .trim()
      .replaceAll(RegExp(r'\x00+$'), '');
}

/// Full decrypt of one flixcloud embed page.
///
/// [fetchTokenJson] is called with the token from the SSR data and
/// must return the decoded JSON of
/// `GET https://flixcloud.cc/api/m3u8/{token}` (the resolver supplies
/// the real HTTP call; tests supply the golden fixture).
/// Throws [FlixcloudException] on any failure — never returns a
/// fake URL.
Future<FlixcloudStream> decryptFlixcloudEmbed({
  required String embedHtml,
  required Future<Map<String, dynamic>> Function(String token)
  fetchTokenJson,
}) async {
  final Map<String, dynamic> data = extractSsrData(embedHtml);
  final String? seed = data['obfuscation_seed'] as String?;
  if (seed == null || seed.isEmpty) {
    throw const FlixcloudException('obfuscation_seed missing');
  }
  final FlixFields fields = deriveFlixFields(seed);
  final Map<String, dynamic>? cryptoData =
      data['obfuscated_crypto_data'] as Map<String, dynamic>?;
  if (cryptoData == null) {
    throw const FlixcloudException('obfuscated_crypto_data missing');
  }
  final Map<String, dynamic>? container =
      cryptoData[fields.containerName] as Map<String, dynamic>?;
  if (container == null) {
    throw FlixcloudException(
      'container "${fields.containerName}" not in ocd',
    );
  }
  final List<dynamic>? array =
      container[fields.arrayName] as List<dynamic>?;
  if (array == null || array.isEmpty) {
    throw FlixcloudException(
      'array "${fields.arrayName}" not in container',
    );
  }
  final Map<String, dynamic>? object =
      (array[0] as Map<String, dynamic>?)?[fields.objectName]
          as Map<String, dynamic>?;
  if (object == null) {
    throw FlixcloudException(
      'object "${fields.objectName}" not in arr[0]',
    );
  }
  final String? keyFieldValue = object[fields.keyField] as String?;
  final String? ivFieldValue = object[fields.ivField] as String?;
  if (keyFieldValue == null || ivFieldValue == null) {
    throw const FlixcloudException('key/iv field missing from embed data');
  }
  final Uint8List fragment = _b64(keyFieldValue);
  final Uint8List iv = _b64(ivFieldValue);
  final String? keyFragmentRaw = data[fields.keyFrag2Field] as String?;
  if (keyFragmentRaw == null) {
    throw FlixcloudException(
      'kf2 field "${fields.keyFrag2Field}" not in data',
    );
  }
  final Uint8List keyFragment = _b64(keyFragmentRaw);
  final String? token = data[fields.tokenField] as String?;
  if (token == null || token.isEmpty) {
    throw FlixcloudException(
      'token field "${fields.tokenField}" missing',
    );
  }
  final Map<String, dynamic> tokenData = await fetchTokenJson(token);
  final String videoKey =
      sha256.convert(utf8.encode('${token}vid')).toString().substring(0, 10);
  final String tokenKey =
      sha256.convert(utf8.encode('${token}key')).toString().substring(0, 10);
  final String? videoB64 = tokenData[videoKey] as String?;
  final String? tokenB64 = tokenData[tokenKey] as String?;
  if (videoB64 == null ||
      videoB64.isEmpty ||
      tokenB64 == null ||
      tokenB64.isEmpty) {
    throw FlixcloudException(
      'Token fields missing. vidKey="$videoKey" keyKey="$tokenKey"',
    );
  }
  final Uint8List videoBytes = _b64(videoB64);
  final Uint8List tokenBytes = _b64(tokenB64);
  final int seedNumber = int.parse(seed.substring(0, 8), radix: 16);
  final String? wasmB64 = data['w_payload'] as String?;
  if (wasmB64 == null || wasmB64.isEmpty) {
    throw const FlixcloudException('w_payload missing from embed data');
  }
  final Uint8List wasmPayload = _b64(wasmB64);
  final String? playlistKey = extractPlaylistKey(wasmPayload);
  final Uint8List wasmOut = runWasmDecrypt(
    wasmBytes: wasmPayload,
    fragment: fragment,
    keyFragment: keyFragment,
    tokenBytes: tokenBytes,
    seed: seedNumber,
  );
  final String url = decryptFlixVideoUrl(
    wasmOut: wasmOut,
    seed: seed,
    iv: iv,
    videoBytes: videoBytes,
  );
  if (!url.startsWith('http')) {
    throw FlixcloudException(
      'Unexpected decrypted value: ${url.substring(0, url.length > 60 ? 60 : url.length)}',
    );
  }
  final List<SubtitleInfo> subtitles = <SubtitleInfo>[];
  final List<dynamic> rawSubs =
      data['subtitles'] as List<dynamic>? ?? <dynamic>[];
  for (final dynamic s in rawSubs) {
    final Map<String, dynamic> sub = s as Map<String, dynamic>;
    final String? file = sub['url'] as String?;
    if (file == null || file.isEmpty) continue;
    subtitles.add(
      SubtitleInfo(
        label: sub['language'] as String? ?? 'Unknown',
        url: file,
      ),
    );
  }
  return FlixcloudStream(
    url: url,
    playlistKey: playlistKey,
    subtitles: subtitles,
    thumbnailsVtt: data['thumbnails_vtt'] as String?,
    videoTitle: data['video_title'] as String?,
    introChapter: data['intro_chapter'],
    outroChapter: data['outro_chapter'],
    videoId: data['video_id'] as String?,
  );
}
