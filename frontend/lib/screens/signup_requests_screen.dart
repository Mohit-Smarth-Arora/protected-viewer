import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../widgets/state_views.dart';

class _SignupRequest {
  _SignupRequest.fromJson(Map<String, dynamic> json)
      : id = json['id'] as int,
        email = json['email'] as String,
        displayName = json['display_name'] as String,
        createdAt = json['created_at'] as String;

  final int id;
  final String email;
  final String displayName;
  final String createdAt;
}

/// Any admin (not master-access-gated): approve or reject viewers who
/// registered without a referral code. Lower stakes than admin_requests
/// (which elevates someone to admin power), so any admin can decide.
class SignupRequestsScreen extends StatefulWidget {
  const SignupRequestsScreen({super.key});

  @override
  State<SignupRequestsScreen> createState() => _SignupRequestsScreenState();
}

class _SignupRequestsScreenState extends State<SignupRequestsScreen> {
  List<_SignupRequest>? _requests;
  String? _error;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.listSignupRequests();
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.error ?? 'Failed to load requests');
      return;
    }
    setState(() {
      _requests =
          (res.body['requests'] as List).map((r) => _SignupRequest.fromJson(r as Map<String, dynamic>)).toList();
      _error = null;
    });
  }

  Future<void> _approve(_SignupRequest request) async {
    final api = context.read<ApiClient>();
    final res = await api.approveSignupRequest(request.id);
    if (!mounted) return;
    if (res.ok) _load();
  }

  Future<void> _reject(_SignupRequest request) async {
    final api = context.read<ApiClient>();
    final res = await api.rejectSignupRequest(request.id);
    if (!mounted) return;
    if (res.ok) _load();
  }

  List<_SignupRequest> get _filteredRequests {
    if (_requests == null) return [];
    if (_query.isEmpty) return _requests!;
    return _requests!
        .where((r) => r.email.toLowerCase().contains(_query) || r.displayName.toLowerCase().contains(_query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signup requests')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name or email',
                isDense: true,
              ),
            ),
          ),
          Expanded(child: RefreshIndicator(onRefresh: _load, child: _buildBody())),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    if (_requests == null) return const LoadingState();
    final filtered = _filteredRequests;
    if (filtered.isEmpty) {
      return EmptyState(
        icon: Icons.how_to_reg_outlined,
        message: _requests!.isEmpty ? 'No pending signup requests.' : 'No matches.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final r = filtered[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.displayName, style: Theme.of(context).textTheme.titleMedium),
                Text(r.email),
                const SizedBox(height: 4),
                Text('Registered: ${r.createdAt}', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(onPressed: () => _reject(r), child: const Text('Reject')),
                    FilledButton(onPressed: () => _approve(r), child: const Text('Approve')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
