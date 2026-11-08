import 'dart:convert';
import 'dart:io';

class ArrivioApi {
  static const users =
      'https://nc17cjkref.execute-api.us-east-1.amazonaws.com/DEV/users';
  static const merchants =
      'https://rx6jfxhhfc.execute-api.us-east-1.amazonaws.com/merchants';
  static const signup =
      'https://nc17cjkref.execute-api.us-east-1.amazonaws.com/signup';
  static const geocode =
      'https://h7pimzshgb.execute-api.us-east-1.amazonaws.com/geocode';
  static const distance =
      'https://g6gvqy5ue6.execute-api.us-east-1.amazonaws.com/distance';
  static const merchantDeals =
      'https://s49qvomd5k.execute-api.us-east-1.amazonaws.com/merchant-deals';
  static const merchantCoupons =
      'https://s49qvomd5k.execute-api.us-east-1.amazonaws.com/merchant-coupons';
  static const saveDeal =
      'https://ntiwthmtz2.execute-api.us-east-1.amazonaws.com/deals';
  static const saveCoupon =
      'https://bzv39kd4g2.execute-api.us-east-1.amazonaws.com/coupons';

  Future<dynamic> request(String url, {Map<String, dynamic>? body}) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(url);
      final request = body == null
          ? await client.getUrl(uri)
          : await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final text = await utf8.decoder.bind(response).join();
      final dynamic result = text.isEmpty ? null : jsonDecode(text);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = result is Map
            ? result['message'] ?? result['error']
            : null;
        throw Exception(message ?? 'Request failed (${response.statusCode})');
      }
      if (result is Map && result['body'] != null) {
        final dynamic nested = result['body'] is String
            ? jsonDecode(result['body'] as String)
            : result['body'];
        if (nested is Map) return {...result, ...nested};
      }
      return result;
    } finally {
      client.close();
    }
  }

  Future<List<Map<String, dynamic>>> list(String url) async {
    final result = await request(url);
    final dynamic data = result is Map ? result['data'] : result;
    if (data is! List) throw const FormatException('Unexpected list response');
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }
}
