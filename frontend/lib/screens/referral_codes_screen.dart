import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';

class _ReferralCode {
  _ReferralCode.fromJson(Map<String, dynamic> json)
      : code = json['code'] as String,
        isActive = json['is_active'] == 1 || json['is_active'] == true,
        usesCount = json['uses_count'] as int,
        createdByName = json['created_by_name'] as String;

  final String code;
  final bool isActive;
  final int usesCount;
  final String createdByName;
}

/// Master-access-only: create/deactivate/reactivate referral codes. A
/// valid active code lets registration skip the pending-approval step.
class ReferralCodesScreen extends StatefulWidget {
  const ReferralCodesScreen({super.key});

  @override
  State<ReferralCodesScreen> createState() => _ReferralCodesScreenState();
}

class _ReferralCodesScreenState extends State<ReferralCodesScreen> {
  List<_ReferralCode>? _codes;
  String? _error;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toUpperCase()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.listReferralCodes();
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.error ?? 'Failed to load referral codes');
      return;
    }
    setState(() {
      _codes = (res.body['codes'] as List).map((c) => _ReferralCode.fromJson(c as Map<String, dynamic>)).toList();
      _error = null;
    });
  }

  Future<void> _create() async {
    final api = context.read<ApiClient>();
    final res = await api.createReferralCode();
    if (!mounted) return;
    if (res.ok) {
      _load();
      final code = res.body['code'] as String;
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Referral code created'),
          content: SelectableText(code, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          actions: [
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Done')),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error ?? 'Could not create code')));
    }
  }

  Future<void> _toggle(_ReferralCode code) async {
    final api = context.read<ApiClient>();
    final res = code.isActive
        ? await api.deactivateReferralCode(code.code)
        : await api.reactivateReferralCode(code.code);
    if (!mounted) return;
    if (res.ok) _load();
  }

  List<_ReferralCode> get _filteredCodes {
    if (_codes == null) return [];
    if (_query.isEmpty) return _codes!;
    return _codes!.where((c) => c.code.contains(_query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Referral codes'),
        actions: [
          IconButton(icon: const Icon(Icons.add), tooltip: 'New code', onPressed: _create),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search codes',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(child: RefreshIndicator(onRefresh: _load, child: _buildBody())),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New code'),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) return ListView(children: [const SizedBox(height: 60), Center(child: Text(_error!))]);
    if (_codes == null) return const Center(child: CircularProgressIndicator());
    final filtered = _filteredCodes;
    if (filtered.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 60),
          Center(child: Text(_codes!.isEmpty ? 'No referral codes yet.' : 'No codes match your search.')),
        ],
      );
    }
    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final code = filtered[i];
        return ListTile(
          leading: Icon(code.isActive ? Icons.qr_code : Icons.qr_code_2_outlined),
          title: SelectableText(code.code, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
          subtitle: Text('${code.usesCount} use(s) • by ${code.createdByName}'),
          trailing: Switch(value: code.isActive, onChanged: (_) => _toggle(code)),
        );
      },
    );
  }
}
