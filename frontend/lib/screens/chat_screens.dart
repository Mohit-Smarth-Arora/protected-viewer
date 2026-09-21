import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../state/session.dart';

// ---- Viewer: request a chat ----------------------------------------------

/// Viewer-only: submit a request to chat with an admin. Mirrors the
/// admin-request flow's shape (submit → pending — wait for review) but
/// much lighter weight — just an optional message, no identity verification.
class RequestChatScreen extends StatefulWidget {
  const RequestChatScreen({super.key});

  @override
  State<RequestChatScreen> createState() => _RequestChatScreenState();
}

class _RequestChatScreenState extends State<RequestChatScreen> {
  final _messageController = TextEditingController();
  bool _isSubmitting = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    final res = await api.submitChatRequest(message: _messageController.text.trim());
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
      appBar: AppBar(title: const Text('Message an admin')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _submitted ? _buildSubmitted() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitted() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.hourglass_top, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text('Request sent', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('An admin will review it and can start a conversation with you.', textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Let an admin know what you need. They\'ll review your request and can open a chat with you.'),
        const SizedBox(height: 16),
        TextField(
          controller: _messageController,
          decoration: const InputDecoration(labelText: 'Message (optional)'),
          maxLines: 4,
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
        ],
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send request'),
        ),
      ],
    );
  }
}

// ---- Admin: review pending chat requests ---------------------------------

class ChatRequestsScreen extends StatefulWidget {
  const ChatRequestsScreen({super.key});

  @override
  State<ChatRequestsScreen> createState() => _ChatRequestsScreenState();
}

class _ChatRequestsScreenState extends State<ChatRequestsScreen> {
  List<Map<String, dynamic>>? _requests;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.listChatRequests();
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.error ?? 'Failed to load requests');
      return;
    }
    setState(() {
      _requests = (res.body['requests'] as List).cast<Map<String, dynamic>>();
      _error = null;
    });
  }

  Future<void> _approve(Map<String, dynamic> request) async {
    final api = context.read<ApiClient>();
    final res = await api.approveChatRequest(request['id'] as int);
    if (!mounted) return;
    if (res.ok) {
      final threadId = res.body['threadId'] as int;
      _load();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            threadId: threadId,
            otherPartyName: request['display_name'] as String,
          ),
        ),
      );
    }
  }

  Future<void> _reject(Map<String, dynamic> request) async {
    final api = context.read<ApiClient>();
    await api.rejectChatRequest(request['id'] as int);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat requests')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) return Center(child: Text(_error!));
    if (_requests == null) return const Center(child: CircularProgressIndicator());
    if (_requests!.isEmpty) {
      return ListView(
        children: const [SizedBox(height: 60), Center(child: Text('No pending chat requests.'))],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _requests!.length,
      itemBuilder: (context, i) {
        final r = _requests![i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r['display_name'] as String, style: Theme.of(context).textTheme.titleMedium),
                Text(r['email'] as String),
                if ((r['message'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(r['message'] as String),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(onPressed: () => _reject(r), child: const Text('Reject')),
                    FilledButton(onPressed: () => _approve(r), child: const Text('Approve & open chat')),
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

// ---- Thread list (both admins and viewers use this) ----------------------

class ChatThreadsScreen extends StatefulWidget {
  const ChatThreadsScreen({super.key});

  @override
  State<ChatThreadsScreen> createState() => _ChatThreadsScreenState();
}

class _ChatThreadsScreenState extends State<ChatThreadsScreen> {
  List<Map<String, dynamic>>? _threads;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.listChatThreads();
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.error ?? 'Failed to load messages');
      return;
    }
    setState(() {
      _threads = (res.body['threads'] as List).cast<Map<String, dynamic>>();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) return Center(child: Text(_error!));
    if (_threads == null) return const Center(child: CircularProgressIndicator());
    if (_threads!.isEmpty) {
      return ListView(
        children: const [SizedBox(height: 60), Center(child: Text('No conversations yet.'))],
      );
    }
    return ListView.separated(
      itemCount: _threads!.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final t = _threads![i];
        return ListTile(
          leading: const Icon(Icons.chat_bubble_outline),
          title: Text(t['display_name'] as String),
          subtitle: Text(t['email'] as String),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatThreadScreen(
                  threadId: t['id'] as int,
                  otherPartyName: t['display_name'] as String,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---- A single conversation -------------------------------------------------

class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({super.key, required this.threadId, required this.otherPartyName});

  final int threadId;
  final String otherPartyName;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _bodyController = TextEditingController();
  List<Map<String, dynamic>>? _messages;
  String? _error;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.listThreadMessages(widget.threadId);
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.error ?? 'Failed to load messages');
      return;
    }
    setState(() {
      _messages = (res.body['messages'] as List).cast<Map<String, dynamic>>();
      _error = null;
    });
  }

  Future<void> _send() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty) return;
    setState(() => _isSending = true);
    final api = context.read<ApiClient>();
    final res = await api.sendThreadMessage(widget.threadId, body);
    if (!mounted) return;
    setState(() => _isSending = false);
    if (res.ok) {
      _bodyController.clear();
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'Could not send message')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.otherPartyName)),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_error != null) return Center(child: Text(_error!));
    if (_messages == null) return const Center(child: CircularProgressIndicator());
    if (_messages!.isEmpty) {
      return const Center(child: Text('No messages yet — say hello.'));
    }
    final myUserId = context.watch<Session>().userId;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        reverse: false,
        padding: const EdgeInsets.all(12),
        itemCount: _messages!.length,
        itemBuilder: (context, i) {
          final m = _messages![i];
          final isMine = m['sender_id'] == myUserId;
          return Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
              decoration: BoxDecoration(
                color: isMine
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(m['body'] as String),
                  const SizedBox(height: 4),
                  Text(
                    m['created_at'] as String,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _bodyController,
                decoration: const InputDecoration(hintText: 'Message'),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              icon: _isSending
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              onPressed: _isSending ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}
