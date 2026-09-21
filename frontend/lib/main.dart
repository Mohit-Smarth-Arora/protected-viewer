import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api/api_client.dart';
import 'state/session.dart';
import 'app.dart';

void main() {
  final api = ApiClient(
    // Points at the local backend from backend/README.md. Move this to a
    // build-time config (--dart-define) before deploying anywhere real.
    baseUrl: 'http://localhost:4000',
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
