import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin wrapper around the backend HTTP API.
///
/// This client makes no security decisions of its own — it just carries the
/// session token and forwards requests. All watermarking, token scoping and
/// expiry, and access control happen server-side (see backend/README.md).
class ApiClient {
  ApiClient({this.baseUrl = 'http://localhost:4000'});

  final String baseUrl;
  String? _sessionToken;

  void setSessionToken(String? token) {
    _sessionToken = token;
  }

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_sessionToken != null) 'Authorization': 'Bearer $_sessionToken',
      };

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<ApiResult> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final res = await http.post(
      _uri('/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'displayName': displayName,
      }),
    );
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> login({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      _uri('/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> me() async {
    final res = await http.get(_uri('/api/auth/me'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> acceptAgreement() async {
    final res = await http.post(
      _uri('/api/auth/agreement/accept'),
      headers: _authHeaders,
    );
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> listAssets() async {
    final res = await http.get(_uri('/api/assets'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> requestAssetToken(String assetId) async {
    final res = await http.post(
      _uri('/api/assets/$assetId/token'),
      headers: _authHeaders,
    );
    return ApiResult.fromResponse(res);
  }

  /// Fetches the already-watermarked bytes for an asset using a short-lived
  /// asset token obtained from [requestAssetToken]. Returns raw PNG bytes on
  /// success — there is no unwatermarked version this client can ever reach.
  Future<http.Response> fetchAssetContent(String assetId, String assetToken) {
    return http.get(_uri('/api/assets/$assetId/content?token=$assetToken'));
  }
}

/// Uniform result wrapper so screens don't need to juggle http.Response
/// status codes and JSON decoding themselves.
class ApiResult {
  ApiResult({required this.statusCode, required this.body});

  factory ApiResult.fromResponse(http.Response res) {
    Map<String, dynamic> body;
    try {
      body = res.body.isEmpty
          ? {}
          : jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      body = {'error': 'Malformed response from server'};
    }
    return ApiResult(statusCode: res.statusCode, body: body);
  }

  final int statusCode;
  final Map<String, dynamic> body;

  bool get ok => statusCode >= 200 && statusCode < 300;
  String? get error => body['error'] as String?;
  String? get code => body['code'] as String?;
}
