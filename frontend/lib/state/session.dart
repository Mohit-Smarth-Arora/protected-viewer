import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';

// How often to ping the server while signed in, to power the admin
// "active now" view (backend/src/routes/admin.js ONLINE_WINDOW_MINUTES).
// Comfortably shorter than that window so a normal session never drops out
// of "online" between heartbeats.
const _heartbeatInterval = Duration(seconds: 45);

// `unknown` is reserved for when session restoration (e.g. "remember me")
// is added — it would be the "checking stored token" transient state.
// Not used yet since sessions are in-memory only (see class doc below).
enum AuthStatus { unknown, signedOut, signedInNeedsAgreement, signedIn }

/// Holds the current session (auth token, user info, agreement status) and
/// notifies listeners on change. Session token lives only in memory for now
/// (lost on page refresh on web) — intentional for this phase: we're not
/// yet persisting anything client-side, matching the "server decides, client
/// just renders" principle. Persisted "remember me" can be added later via a
/// dedicated secure-storage package once the security tradeoffs are decided
/// deliberately, not as a default.
class Session extends ChangeNotifier {
  Session(this.api);

  final ApiClient api;

  AuthStatus status = AuthStatus.signedOut;
  int? userId;
  String? userEmail;
  String? userDisplayName;
  String role = 'viewer'; // 'viewer' | 'admin' | 'owner', set from /me
  bool hasMasterAccess = false;
  String? _lastError;
  Timer? _heartbeatTimer;

  String? get lastError => _lastError;
  bool get isAdmin => role == 'admin' || role == 'owner';
  bool get isOwner => role == 'owner';
  // Owner always has effective master access, regardless of the raw flag
  // (which only stores meaningfully for role='admin' server-side).
  bool get effectiveMasterAccess => role == 'owner' || hasMasterAccess;

  Future<void> login(String email, String password) async {
    _lastError = null;
    final res = await api.login(email: email, password: password);
    if (!res.ok) {
      _lastError = res.error ?? 'Login failed';
      notifyListeners();
      return;
    }
    final token = res.body['token'] as String;
    final user = res.body['user'] as Map<String, dynamic>;
    api.setSessionToken(token);
    userId = user['id'] as int;
    userEmail = user['email'] as String;
    userDisplayName = user['displayName'] as String;
    await _refreshAgreementStatus();
  }

  Future<void> register(String email, String password, String displayName) async {
    _lastError = null;
    final res = await api.register(
      email: email,
      password: password,
      displayName: displayName,
    );
    if (!res.ok) {
      _lastError = res.error ?? 'Registration failed';
      notifyListeners();
      return;
    }
    final token = res.body['token'] as String;
    final user = res.body['user'] as Map<String, dynamic>;
    api.setSessionToken(token);
    userId = user['id'] as int;
    userEmail = user['email'] as String;
    userDisplayName = user['displayName'] as String;
    await _refreshAgreementStatus();
  }

  Future<void> _refreshAgreementStatus() async {
    final meRes = await api.me();
    if (!meRes.ok) {
      status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    final userInfo = meRes.body['user'] as Map<String, dynamic>;
    role = userInfo['role'] as String? ?? 'viewer';
    hasMasterAccess = userInfo['has_master_access'] == 1 || userInfo['has_master_access'] == true;

    final accepted = meRes.body['agreementAccepted'] == true;
    status = accepted ? AuthStatus.signedIn : AuthStatus.signedInNeedsAgreement;
    if (status == AuthStatus.signedIn) {
      _startHeartbeat();
    }
    notifyListeners();
  }

  void _startHeartbeat() {
    if (_heartbeatTimer != null) return; // already running
    api.heartbeat(); // fire immediately, then on the interval
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => api.heartbeat());
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Re-pulls /me without changing auth flow state — used after actions
  /// that might change role/master-access (e.g. own admin request outcome).
  Future<void> refreshUserInfo() => _refreshAgreementStatus();

  Future<void> acceptAgreement() async {
    final res = await api.acceptAgreement();
    if (res.ok) {
      status = AuthStatus.signedIn;
      notifyListeners();
    } else {
      _lastError = res.error ?? 'Could not record agreement';
      notifyListeners();
    }
  }

  void signOut() {
    _stopHeartbeat();
    api.setSessionToken(null);
    userId = null;
    userEmail = null;
    userDisplayName = null;
    role = 'viewer';
    hasMasterAccess = false;
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopHeartbeat();
    super.dispose();
  }
}
