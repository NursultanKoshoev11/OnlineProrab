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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              children: [
                const Center(child: _BrandMark(size: 78)),
                const SizedBox(height: 18),
                const Text(
                  'OnlinePRorab',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: _brand,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _requested ? 'Введите код из SMS' : 'Строительство под контролем',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _requested
                      ? 'Мы отправили 6-значный код на указанный номер.'
                      : 'Объекты и расходы — просто и понятно.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, height: 1.4, color: _muted),
                ),
                const SizedBox(height: 38),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  enabled: !_busy && !_requested,
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
                    autofocus: true,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Код из SMS',
                      counterText: '',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
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
                if (_requested) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _requested = false;
                            _code.clear();
                            _error = null;
                          }),
                    child: const Text('Изменить номер'),
                  ),
                ],
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
