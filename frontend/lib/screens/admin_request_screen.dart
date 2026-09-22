import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';

/// Lets a signed-in viewer apply to become an admin. Reviewed later by the
/// owner (or a master-access admin) via AdminRequestsReviewScreen. See
/// backend/src/routes/auth.js admin-request route.
class AdminRequestScreen extends StatefulWidget {
  const AdminRequestScreen({super.key});

  @override
  State<AdminRequestScreen> createState() => _AdminRequestScreenState();
}

class _AdminRequestScreenState extends State<AdminRequestScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _orgController = TextEditingController();
  final _reasonController = TextEditingController();

  PlatformFile? _photo;
  bool _isSubmitting = false;
  String? _error;
  bool _submitted = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _orgController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true, // needed on web to get bytes directly
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _photo = result.files.first);
    }
  }

  Future<void> _submit() async {
    setState(() => _error = null);

    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty ||
        _reasonController.text.trim().isEmpty) {
      setState(() => _error = 'Full name, phone number, and reason are required');
      return;
    }
    if (_photo == null || _photo!.bytes == null) {
      setState(() => _error = 'Please select a passport-size photo');
      return;
    }

    setState(() => _isSubmitting = true);
    final api = context.read<ApiClient>();
    final res = await api.submitAdminRequest(
      fullLegalName: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      organization: _orgController.text.trim().isEmpty ? null : _orgController.text.trim(),
      reason: _reasonController.text.trim(),
      photoBytes: _photo!.bytes!,
      photoFilename: _photo!.name,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res.ok) {
      setState(() => _submitted = true);
    } else {
      setState(() => _error = res.error ?? 'Could not submit request');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request admin access')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _submitted ? _buildSubmittedState() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildSubmittedState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.hourglass_top, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Request submitted',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your request is pending review. You\'ll keep your current viewer '
          'access until it is approved.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Admin access lets you upload assets and control who can view them. '
          'Requests are reviewed manually.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Full legal name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneController,
          decoration: const InputDecoration(labelText: 'Phone number'),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _orgController,
          decoration: const InputDecoration(labelText: 'Organization / affiliation (optional)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _reasonController,
          decoration: const InputDecoration(labelText: 'Reason for admin access'),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _pickPhoto,
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(_photo == null ? 'Select passport-size photo' : _photo!.name),
        ),
        const SizedBox(height: 20),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
        ],
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Submit request'),
        ),
      ],
    );
  }
}
