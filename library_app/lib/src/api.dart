import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

typedef Doc = Map<String, dynamic>;

class LibraryApi {
  final http.Client client;
  final String baseUrl;
  LibraryApi({
    http.Client? client,
    this.baseUrl = const String.fromEnvironment(
      'API_URL',
      defaultValue: 'http://localhost:8080',
    ),
  }) : client = client ?? http.Client();
  Future<dynamic> request(String method, String path, [Doc? data]) async {
    try {
      final req = http.Request(method, Uri.parse('$baseUrl/$path'));
      req.headers.addAll({
        'Content-Type': 'application/json',
        'X-API-Key': const String.fromEnvironment('API_KEY'),
      });
      if (data != null) req.body = jsonEncode(data);
      final streamed = await client
          .send(req)
          .timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode >= 400) {
        throw ApiException(decoded['message'] ?? 'Không xử lý được yêu cầu.');
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(
        'Kết nối quá thời gian. Tải lại dữ liệu để kiểm tra kết quả trước khi thử lại.',
      );
    } catch (_) {
      throw ApiException(
        'Không kết nối được API tại $baseUrl. Hãy khởi động server và kiểm tra API_URL.',
      );
    }
  }

  Future<Doc> snapshot() async => (await request('GET', 'snapshot')) as Doc;
  Future<List<Doc>> books({
    String query = '',
    String category = '',
    String sort = 'title',
    String order = 'asc',
  }) async {
    final uri = Uri(
      path: 'books',
      queryParameters: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (category.isNotEmpty) 'category': category,
        'sort': sort,
        'order': order,
      },
    );
    return (await request('GET', uri.toString()) as List).cast<Doc>();
  }

  Future<void> save(String collection, Doc data, String? code) async {
    await request(
      code == null ? 'POST' : 'PUT',
      '$collection${code == null ? '' : '/${Uri.encodeComponent(code)}'}',
      data,
    );
  }

  Future<void> delete(String collection, String code) async {
    await request('DELETE', '$collection/${Uri.encodeComponent(code)}');
  }

  void close() => client.close();
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
