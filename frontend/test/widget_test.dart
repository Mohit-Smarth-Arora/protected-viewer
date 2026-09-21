// Basic smoke test: a signed-out session should render the login screen.
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/api/api_client.dart';
import 'package:frontend/state/session.dart';
import 'package:frontend/app.dart';

void main() {
  testWidgets('shows login screen when signed out', (WidgetTester tester) async {
    final api = ApiClient();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<Session>(create: (_) => Session(api)),
        ],
        child: const ProtectedViewerApp(),
      ),
    );

    expect(find.text('Protected Viewer'), findsWidgets);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
