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
  String _channel = 'telegram';
  bool _loadingChannels = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _loadChannels() async {
    try {
      final data = await widget.apiClient.getSupportChannels();
      final telegram = data['telegram'];
      final whatsapp = data['whatsapp'];
      final telegramEnabled = telegram is Map && telegram['enabled'] == true;
      final whatsappEnabled = whatsapp is Map && whatsapp['enabled'] == true;
      if (!mounted) return;
      setState(() {
        _loadingChannels = false;
        if (!telegramEnabled && whatsappEnabled) _channel = 'whatsapp';
      });
    } catch (_) {
      if (mounted) setState(() => _loadingChannels = false);
    }
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
        channel: _channel,
        subject: _subject.text.trim(),
        message: message,
      );
      if (!mounted) return;
      final status = result['delivery_status']?.toString();
      final text = status == 'sent'
          ? 'Сообщение отправлено в техподдержку'
          : 'Обращение сохранено. Канал будет подключён после настройки бота';
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
            subtitle: 'Опишите проблему — мы ответим через выбранный канал.',
          ),
          const SizedBox(height: 18),
          const Text(
            'Канал связи',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(
                value: 'telegram',
                label: Text('Telegram'),
                icon: Icon(Icons.send_rounded),
              ),
              ButtonSegment<String>(
                value: 'whatsapp',
                label: Text('WhatsApp'),
                icon: Icon(Icons.chat_rounded),
              ),
            ],
            selected: {_channel},
            onSelectionChanged: _sending
                ? null
                : (value) => setState(() => _channel = value.first),
          ),
          if (_loadingChannels)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Проверяем доступность каналов...',
                style: TextStyle(color: _muted),
              ),
            ),
          const SizedBox(height: 16),
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
              labelText: 'Сообщение',
              hintText: 'Опишите проблему подробнее',
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
            'Обращение сначала сохраняется в системе, поэтому оно не потеряется даже до подключения API-ключей ботов.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
