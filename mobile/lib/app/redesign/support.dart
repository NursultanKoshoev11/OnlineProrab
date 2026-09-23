part of '../online_prorab_redesign.dart';

class _SupportScreen extends StatefulWidget {
  const _SupportScreen({required this.apiClient});

  final ApiClient apiClient;

  @override
  State<_SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<_SupportScreen> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _message.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Напишите сообщение');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await widget.apiClient.createSupportTicket(
        subject: _subject.text.trim(),
        message: message,
      );
      if (!mounted) return;
      final status = result['delivery_status']?.toString();
      final text = status == 'sent'
          ? 'Сообщение отправлено в техподдержку'
          : 'Обращение сохранено на сервере. Мы обработаем его в техподдержке';
      _message.clear();
      _subject.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Техподдержка')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const _PageHeader(
            title: 'Помощь',
            subtitle: 'Опишите проблему — обращение отправится в техподдержку.',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _subject,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Тема',
              hintText: 'Например: не сохраняется расход',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _message,
            minLines: 6,
            maxLines: 10,
            maxLength: 4000,
            decoration: const InputDecoration(
              labelText: 'Описание',
              hintText: 'Опишите, что произошло',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(_sending ? 'Отправка...' : 'Отправить обращение'),
          ),
          const SizedBox(height: 10),
          const Text(
            'Обращение сохраняется на сервере и передаётся в техподдержку.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
