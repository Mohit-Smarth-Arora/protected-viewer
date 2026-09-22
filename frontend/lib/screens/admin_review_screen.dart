import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../util/ist_time.dart';
import '../widgets/state_views.dart';

class AdminRequestSummary {
  AdminRequestSummary.fromJson(Map<String, dynamic> json)
      : id = json['id'] as int,
        fullLegalName = json['full_legal_name'] as String,
        phoneNumber = json['phone_number'] as String,
        organization = json['organization'] as String?,
        reason = json['reason'] as String,
        email = json['email'] as String,
        displayName = json['display_name'] as String,
        createdAt = json['created_at'] as String;

  final int id;
  final String fullLegalName;
  final String phoneNumber;
  final String? organization;
  final String reason;
  final String email;
  final String displayName;
  final String createdAt;
}

/// Owner/master-access-only screen: review pending admin requests (with
/// verification photo), approve (optionally with master access) or reject.
/// Gated server-side by requireMasterAccess — this screen just shouldn't
/// be reachable in the UI for anyone without effectiveMasterAccess, but the
/// real enforcement is the backend's 403 either way.
class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({super.key});

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen> {
  List<AdminRequestSummary>? _requests;
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

  List<AdminRequestSummary> get _filteredRequests {
    if (_requests == null) return [];
    if (_query.isEmpty) return _requests!;
    return _requests!
        .where((r) =>
            r.fullLegalName.toLowerCase().contains(_query) ||
            r.email.toLowerCase().contains(_query) ||
            r.displayName.toLowerCase().contains(_query))
        .toList();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.listAdminRequests(status: 'pending');
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.error ?? 'Failed to load requests');
      return;
    }
    final list = (res.body['requests'] as List)
        .map((r) => AdminRequestSummary.fromJson(r as Map<String, dynamic>))
        .toList();
    setState(() {
      _requests = list;
      _error = null;
    });
  }

  Future<void> _decide(AdminRequestSummary request, {required bool approve, bool grantMaster = false}) async {
    final api = context.read<ApiClient>();
    final res = approve
        ? await api.approveAdminRequest(request.id, grantMasterAccess: grantMaster)
        : await api.rejectAdminRequest(request.id);
    if (!mounted) return;
    if (res.ok) {
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'Action failed')),
      );
    }
  }

  Future<void> _showPhoto(AdminRequestSummary request) async {
    final api = context.read<ApiClient>();
    final response = await api.fetchAdminRequestPhoto(request.id);
    if (!mounted) return;
    if (response.statusCode != 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load photo')),
      );
      return;
    }
    final bytes = response.bodyBytes;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.memory(Uint8List.fromList(bytes)),
        ),
      ),
    );
  }

  Future<void> _confirmApprove(AdminRequestSummary request) async {
    final grantMaster = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Approve ${request.displayName}?'),
        content: const Text('Grant full master access (owner-level powers) to this admin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Approve (plain admin)'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Approve with master access'),
          ),
        ],
      ),
    );
    if (grantMaster == null) return; // cancelled
    _decide(request, approve: true, grantMaster: grantMaster);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pending admin requests')),
      body: Column(
        children: [
          if ((_requests?.length ?? 0) > 5)
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
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (_requests == null) {
      return const LoadingState();
    }
    if (_requests!.isEmpty) {
      return const EmptyState(icon: Icons.fact_check_outlined, message: 'No pending requests.');
    }
    final filtered = _filteredRequests;
    if (filtered.isEmpty) {
      return const EmptyState(icon: Icons.search_off, message: 'No matches.');
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
                Text(r.fullLegalName, style: Theme.of(context).textTheme.titleMedium),
                Text('Account: ${r.displayName} (${r.email})'),
                Text('Phone: ${r.phoneNumber}'),
                if (r.organization != null && r.organization!.isNotEmpty)
                  Text('Organization: ${r.organization}'),
                const SizedBox(height: 8),
                Text('Reason: ${r.reason}'),
                const SizedBox(height: 8),
                Text(
                  'Submitted: ${formatIst(r.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showPhoto(r),
                      icon: const Icon(Icons.photo_outlined),
                      label: const Text('View photo'),
                    ),
                    OutlinedButton(
                      onPressed: () => _decide(r, approve: false),
                      child: const Text('Reject'),
                    ),
                    FilledButton(
                      onPressed: () => _confirmApprove(r),
                      child: const Text('Approve'),
                    ),
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
