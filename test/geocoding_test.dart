import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ecommerce_app/services/geocoding.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.respond);
  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request) respond;
  Uri? lastUrl;
  Map<String, String>? lastHeaders;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastUrl = request.url;
    lastHeaders = request.headers;
    return respond(request);
  }
}

http.StreamedResponse _json(Object body, {int status = 200}) => http.StreamedResponse(
  Stream.value(utf8.encode(jsonEncode(body))),
  status,
);

void main() {
  test('search builds the expected Nominatim URL and User-Agent header', () async {
    final client = _FakeClient((_) async => _json([]));
    final geocoder = NominatimGeocoder(client: client);
    await geocoder.search('MG Road Bengaluru');
    expect(client.lastUrl?.host, 'nominatim.openstreetmap.org');
    expect(client.lastUrl?.path, '/search');
    expect(client.lastUrl?.queryParameters['q'], 'MG Road Bengaluru');
    expect(client.lastUrl?.queryParameters['format'], 'json');
    expect(client.lastHeaders?['User-Agent'], isNotNull);
    expect(client.lastHeaders?['User-Agent'], isNotEmpty);
  });

  test('search parses valid results and skips malformed ones', () async {
    final client = _FakeClient(
      (_) async => _json([
        {'display_name': 'MG Road, Bengaluru', 'lat': '12.9716', 'lon': '77.5946'},
        {'display_name': 'Missing coordinates'},
        {'lat': '1', 'lon': '2'}, // missing display_name
      ]),
    );
    final results = await NominatimGeocoder(client: client).search('MG Road');
    expect(results, hasLength(1));
    expect(results.single.displayName, 'MG Road, Bengaluru');
    expect(results.single.latitude, 12.9716);
    expect(results.single.longitude, 77.5946);
  });

  test('a blank query short-circuits without a network call', () async {
    var called = false;
    final client = _FakeClient((_) async {
      called = true;
      return _json([]);
    });
    final results = await NominatimGeocoder(client: client).search('   ');
    expect(results, isEmpty);
    expect(called, isFalse);
  });

  test('a non-200 response throws a friendly error', () async {
    final client = _FakeClient((_) async => _json({}, status: 500));
    await expectLater(
      NominatimGeocoder(client: client).search('anywhere'),
      throwsA(isA<StateError>()),
    );
  });
}
