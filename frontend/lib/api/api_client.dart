import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// http.MultipartFile.fromBytes doesn't reliably infer a content-type from
/// the filename on its own (falls back to application/octet-stream, which
/// the backend's fileFilter then rejects even for genuinely valid files —
/// see git history for the admin-photo-upload bug this fixes). Setting
/// MediaType explicitly avoids depending on that inference at all.
MediaType? _mediaTypeForFilename(String filename) {
  final ext = filename.toLowerCase().split('.').last;
  return switch (ext) {
    'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
    'png' => MediaType('image', 'png'),
    'webp' => MediaType('image', 'webp'),
    'py' => MediaType('text', 'plain'),
    _ => null, // let http fall back to its own default rather than guess wrong
  };
}

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

  /// Pinged periodically while the app is open/foregrounded to power the
  /// admin "active now" view. Fire-and-forget from the caller's side is
  /// fine — a missed beat just means this user drops out of "online"
  /// after the server's freshness window.
  Future<ApiResult> heartbeat() async {
    final res = await http.post(_uri('/api/auth/heartbeat'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  /// Lists folders + assets inside [folderId] (or the root when null) that
  /// the current user can see — viewers only see what's been granted
  /// (directly or via a folder grant), admins/owner see everything.
  Future<ApiResult> listAssets({String? folderId}) async {
    final query = folderId != null ? '?folderId=$folderId' : '';
    final res = await http.get(_uri('/api/assets$query'), headers: _authHeaders);
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

  // ---- Admin request (viewer applying to become admin) -----------------

  Future<ApiResult> submitAdminRequest({
    required String fullLegalName,
    required String phoneNumber,
    String? organization,
    required String reason,
    required Uint8List photoBytes,
    required String photoFilename,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/api/auth/admin-request'))
      ..headers.addAll({if (_sessionToken != null) 'Authorization': 'Bearer $_sessionToken'})
      ..fields['fullLegalName'] = fullLegalName
      ..fields['phoneNumber'] = phoneNumber
      ..fields['reason'] = reason
      ..files.add(http.MultipartFile.fromBytes(
        'photo',
        photoBytes,
        filename: photoFilename,
        contentType: _mediaTypeForFilename(photoFilename),
      ));
    if (organization != null && organization.isNotEmpty) {
      request.fields['organization'] = organization;
    }

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return ApiResult.fromResponse(res);
  }

  // ---- Admin: reviewing requests / managing admins (master access) -----

  Future<ApiResult> listAdminRequests({String status = 'pending'}) async {
    final res = await http.get(
      _uri('/api/admin/admin-requests?status=$status'),
      headers: _authHeaders,
    );
    return ApiResult.fromResponse(res);
  }

  Future<http.Response> fetchAdminRequestPhoto(int requestId) {
    return http.get(_uri('/api/admin/admin-requests/$requestId/photo'), headers: _authHeaders);
  }

  Future<ApiResult> approveAdminRequest(int requestId, {required bool grantMasterAccess}) async {
    final res = await http.post(
      _uri('/api/admin/admin-requests/$requestId/approve'),
      headers: _authHeaders,
      body: jsonEncode({'grantMasterAccess': grantMasterAccess}),
    );
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> rejectAdminRequest(int requestId) async {
    final res = await http.post(
      _uri('/api/admin/admin-requests/$requestId/reject'),
      headers: _authHeaders,
    );
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> listAdmins() async {
    final res = await http.get(_uri('/api/admin/admins'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> setAdminMasterAccess(int userId, {required bool grant}) async {
    final res = await http.post(
      _uri('/api/admin/admins/$userId/master-access'),
      headers: _authHeaders,
      body: jsonEncode({'grant': grant}),
    );
    return ApiResult.fromResponse(res);
  }

  // ---- Admin: asset upload + grants (plain admin and up) ----------------

  Future<ApiResult> listAdminAssets() async {
    final res = await http.get(_uri('/api/admin/assets'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> uploadAsset({
    required String type,
    required String title,
    required Uint8List fileBytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/api/admin/assets'))
      ..headers.addAll({if (_sessionToken != null) 'Authorization': 'Bearer $_sessionToken'})
      ..fields['type'] = type
      ..fields['title'] = title
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: filename,
        contentType: _mediaTypeForFilename(filename),
      ));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> deleteAsset(String assetId) async {
    final res = await http.delete(_uri('/api/admin/assets/$assetId'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> listViewers() async {
    final res = await http.get(_uri('/api/admin/users'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> listAssetGrants(String assetId) async {
    final res = await http.get(_uri('/api/admin/assets/$assetId/grants'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> grantAsset(String assetId, int userId) async {
    final res = await http.post(
      _uri('/api/admin/assets/$assetId/grants'),
      headers: _authHeaders,
      body: jsonEncode({'userId': userId}),
    );
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> revokeAssetGrant(String assetId, int userId) async {
    final res = await http.delete(
      _uri('/api/admin/assets/$assetId/grants/$userId'),
      headers: _authHeaders,
    );
    return ApiResult.fromResponse(res);
  }

  // ---- Admin: folders (plain admin and up) -------------------------------

  Future<ApiResult> createFolder({required String name, String? parentId}) async {
    final res = await http.post(
      _uri('/api/admin/folders'),
      headers: _authHeaders,
      body: jsonEncode({'name': name, 'parentId': ?parentId}),
    );
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> renameFolder(String folderId, String name) async {
    final res = await http.patch(
      _uri('/api/admin/folders/$folderId'),
      headers: _authHeaders,
      body: jsonEncode({'name': name}),
    );
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> deleteFolder(String folderId) async {
    final res = await http.delete(_uri('/api/admin/folders/$folderId'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> listFolderGrants(String folderId) async {
    final res = await http.get(_uri('/api/admin/folders/$folderId/grants'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> grantFolder(String folderId, int userId) async {
    final res = await http.post(
      _uri('/api/admin/folders/$folderId/grants'),
      headers: _authHeaders,
      body: jsonEncode({'userId': userId}),
    );
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> revokeFolderGrant(String folderId, int userId) async {
    final res = await http.delete(
      _uri('/api/admin/folders/$folderId/grants/$userId'),
      headers: _authHeaders,
    );
    return ApiResult.fromResponse(res);
  }

  // ---- Admin: user activity (plain admin and up) -------------------------

  Future<ApiResult> listAccounts() async {
    final res = await http.get(_uri('/api/admin/activity/accounts'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> listLoginHistory({int limit = 100}) async {
    final res = await http.get(_uri('/api/admin/activity/logins?limit=$limit'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> listOnlineNow() async {
    final res = await http.get(_uri('/api/admin/activity/online'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  // ---- Chat: requests (viewer submits, admin reviews) --------------------

  Future<ApiResult> submitChatRequest({String? message}) async {
    final res = await http.post(
      _uri('/api/chat/requests'),
      headers: _authHeaders,
      body: jsonEncode({if (message != null && message.isNotEmpty) 'message': message}),
    );
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> listChatRequests() async {
    final res = await http.get(_uri('/api/chat/requests'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> approveChatRequest(int requestId) async {
    final res = await http.post(_uri('/api/chat/requests/$requestId/approve'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> rejectChatRequest(int requestId) async {
    final res = await http.post(_uri('/api/chat/requests/$requestId/reject'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  // ---- Chat: threads + messages -------------------------------------------

  Future<ApiResult> listChatThreads() async {
    final res = await http.get(_uri('/api/chat/threads'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> startDirectMessage(int viewerId, String body) async {
    final res = await http.post(
      _uri('/api/chat/direct/$viewerId'),
      headers: _authHeaders,
      body: jsonEncode({'body': body}),
    );
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> listThreadMessages(int threadId) async {
    final res = await http.get(_uri('/api/chat/threads/$threadId/messages'), headers: _authHeaders);
    return ApiResult.fromResponse(res);
  }

  Future<ApiResult> sendThreadMessage(int threadId, String body) async {
    final res = await http.post(
      _uri('/api/chat/threads/$threadId/messages'),
      headers: _authHeaders,
      body: jsonEncode({'body': body}),
    );
    return ApiResult.fromResponse(res);
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
