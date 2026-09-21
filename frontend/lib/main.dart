import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api/api_client.dart';
import 'state/session.dart';
import 'app.dart';

void main() {
  final api = ApiClient(
    // Defaults to the local backend for `flutter run` during development.
    // Deployed builds set this via --dart-define=BACKEND_URL=... (see
    // .github/workflows/deploy-frontend.yml).
    baseUrl: const String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'http://localhost:4000',
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<Session>(create: (_) => Session(api)),
      ],
      child: const ProtectedViewerApp(),
    ),
  );
}
