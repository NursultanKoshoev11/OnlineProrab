part of '../online_prorab_redesign.dart';

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.deps});

  final _Dependencies deps;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _phone = TextEditingController(text: '+996');
  final _code = TextEditingController();
  bool _requested = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 42, 24, 24),
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: _BrandMark(size: 72),
                ),
                const SizedBox(height: 30),
                const Text(
                  'Стройка под контролем',
                  style: TextStyle(
                    fontSize: 34,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Объекты, расходы, задачи, команда и отчёты — в одном приложении.',
                  style: TextStyle(fontSize: 16, height: 1.45, color: _muted),
                ),
                const SizedBox(height: 34),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Номер телефона',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                if (_requested) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Код из SMS',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_requested ? 'Войти' : 'Получить код'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim();
    if (phone.length < 9) {
      setState(() => _error = 'Введите корректный номер телефона');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_requested) {
        await widget.deps.authRepository.requestCode(phone);
        if (!mounted) return;
        setState(() => _requested = true);
        return;
      }
      if (_code.text.trim().length != 6) {
        setState(() => _error = 'Введите 6-значный код');
        return;
      }
      final session = await widget.deps.authRepository.verifyCode(
        phone,
        _code.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => _ProjectsScreen(session: session, deps: widget.deps),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
