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
//
// Order a fresh viewer moves through: signedOut -> needsEmailVerification
// -> (pendingApproval if no valid referral code was used) -> signedIn
// (needsAgreement is checked once email+approval are settled). Admins/owner
// skip needsEmailVerification/pendingApproval entirely — the backend's
// requireActiveAccount middleware exempts them (see git history).
enum AuthStatus {
  unknown,
  signedOut,
  needsEmailVerification,
  pendingApproval,
  signedInNeedsAgreement,
  signedIn,
}

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

  // Stashed from registration's response so the verification screen can
  // pass it back to /verify-email without asking the user to retype it.
  // Purely a client-side convenience — the server independently
  // re-validates the code at verification time regardless.
  String? _pendingReferralCode;

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
    await _refreshStatus();
  }

  Future<void> register(String email, String password, String displayName, {String? referralCode}) async {
    _lastError = null;
    final res = await api.register(
      email: email,
      password: password,
      displayName: displayName,
      referralCode: referralCode,
    );
    if (!res.ok) {
      _lastError = res.error ?? 'Registration failed';
      notifyListeners();
      return;
    }
    final token = res.body['token'] as String;
    final user = res.body['user'] as Map<String, dynamic>;
    _pendingReferralCode = res.body['pendingReferralCode'] as String?;
    api.setSessionToken(token);
    userId = user['id'] as int;
    userEmail = user['email'] as String;
    userDisplayName = user['displayName'] as String;
    await _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final meRes = await api.me();
    if (!meRes.ok) {
      status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    final userInfo = meRes.body['user'] as Map<String, dynamic>;
    role = userInfo['role'] as String? ?? 'viewer';
    hasMasterAccess = userInfo['has_master_access'] == 1 || userInfo['has_master_access'] == true;
    final emailVerified = userInfo['email_verified'] == 1 || userInfo['email_verified'] == true;
    final signupStatus = userInfo['signup_status'] as String? ?? 'active';
    final accepted = meRes.body['agreementAccepted'] == true;

    // Admins/owner skip the verification/approval gate entirely (mirrors
    // the backend's requireActiveAccount exemption).
    final isAdminOrOwner = role == 'admin' || role == 'owner';

    if (!isAdminOrOwner && !emailVerified) {
      status = AuthStatus.needsEmailVerification;
    } else if (!isAdminOrOwner && signupStatus != 'active') {
      status = AuthStatus.pendingApproval;
    } else if (!accepted) {
      status = AuthStatus.signedInNeedsAgreement;
    } else {
      status = AuthStatus.signedIn;
    }

    if (status == AuthStatus.signedIn) {
      _startHeartbeat();
    }
    notifyListeners();
  }

  Future<void> verifyEmail(String code) async {
    _lastError = null;
    final res = await api.verifyEmail(code: code, referralCode: _pendingReferralCode);
    if (!res.ok) {
      _lastError = res.error ?? 'Verification failed';
      notifyListeners();
      return;
    }
    _pendingReferralCode = null;
    await _refreshStatus();
  }

  Future<ApiResult> resendVerification() => api.resendVerification();

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
  Future<void> refreshUserInfo() => _refreshStatus();

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
    _pendingReferralCode = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopHeartbeat();
    super.dispose();
  }
}
