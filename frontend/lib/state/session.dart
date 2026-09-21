import 'package:flutter/foundation.dart';
import '../api/api_client.dart';

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
  String? userEmail;
  String? userDisplayName;
  String? _lastError;

  String? get lastError => _lastError;

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
    final accepted = meRes.body['agreementAccepted'] == true;
    status = accepted ? AuthStatus.signedIn : AuthStatus.signedInNeedsAgreement;
    notifyListeners();
  }

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
    api.setSessionToken(null);
    userEmail = null;
    userDisplayName = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }
}
