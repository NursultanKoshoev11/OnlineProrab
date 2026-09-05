part of '../online_prorab_redesign.dart';

class _ExpensesTab extends StatefulWidget {
  const _ExpensesTab({
    required this.project,
    required this.repository,
    required this.speechToText,
    required this.initial,
    required this.onChanged,
  });

  final RemoteProject project;
  final CostItemRepository repository;
  final stt.SpeechToText speechToText;
  final List<RemoteCostItem> initial;
  final ValueChanged<List<RemoteCostItem>> onChanged;

  @override
  State<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends State<_ExpensesTab> {
  final _search = TextEditingController();
  String _category = 'all';
  late List<RemoteCostItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.initial);
  }

  @override
  void didUpdateWidget(covariant _ExpensesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) _items = List.of(widget.initial);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<RemoteCostItem> get _filtered {
    final parsed = _parseExpenseSearchQuery(
      _search.text,
      now: DateTime.now(),
    );
    return _items.where((item) {
      final matchesQuery = parsed.matches(item);
      final matchesCategory =
          _category == 'all' || item.category.toLowerCase() == _category;
      return matchesQuery && matchesCategory;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final total = filtered.fold<double>(0, (sum, item) => sum + item.amount);
    final categories = _items
        .map((e) => e.category.toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .take(6)
        .toList();
    final currency = filtered.isEmpty
        ? (_items.isEmpty ? 'KGS' : _items.first.currency)
        : filtered.first.currency;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
            children: [
              const Text(
                'Расходы',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(widget.project.name, style: const TextStyle(color: _muted)),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Например: окна за май 2026',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(6),
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                      ),
                      tooltip: 'Голосовой поиск расходов',
                      onPressed: _voiceSearch,
                      icon: const Icon(Icons.mic_rounded),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'Все',
                      selected: _category == 'all',
                      onTap: () => setState(() => _category = 'all'),
                    ),
                    for (final category in categories) ...[
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: _categoryLabel(category),
                        selected: _category == category,
                        onTap: () => setState(() => _category = category),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Найдено по запросу',
                        style: TextStyle(color: _muted, fontSize: 13),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _money(total, currency),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${filtered.length} записей',
                        style: const TextStyle(color: _muted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                const _EmptyCard(
                  icon: Icons.receipt_long_outlined,
                  title: 'Расходы не найдены',
                  message: 'Измените запрос или добавьте расход.',
                )
              else
                ...filtered.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _CostDetails(item: item),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(13),
                          child: Row(
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: _brandSoft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _categoryIcon(item.category),
                                  color: _brand,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: _ink,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _categoryLabel(item.category),
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (item.vendor.isNotEmpty)
                                      Text(
                                        item.vendor,
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    if (item.spentAt.isNotEmpty)
                                      Text(
                                        item.spentAt,
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _money(item.amount, item.currency),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: FilledButton.icon(
            onPressed: _addExpense,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Добавить расход'),
          ),
        ),
      ],
    );
  }

  Future<void> _voiceSearch() async {
    bool available;
    try {
      available = await widget.speechToText.initialize(
        options: [stt.SpeechToText.androidNoBluetooth],
      );
    } catch (_) {
      available = false;
    }
    if (!mounted) return;
    if (!available) {
      _toast(
        context,
        'Распознавание речи недоступно. Проверьте разрешение микрофона и системный сервис речи.',
      );
      return;
    }

    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _VoiceExpenseSearchSheet(
        speechToText: widget.speechToText,
      ),
    );
    if (!mounted || value == null || value.trim().isEmpty) return;
    _search.text = value.trim();
    _search.selection = TextSelection.collapsed(offset: _search.text.length);
    setState(() => _category = 'all');
  }

  Future<void> _addExpense() async {
    final result = await showModalBottomSheet<RemoteCostItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CreateExpenseSheet(
        project: widget.project,
        repository: widget.repository,
      ),
    );
    if (result == null) return;
    setState(() => _items = [result, ..._items]);
    widget.onChanged(_items);
  }
}

class _VoiceExpenseSearchSheet extends StatefulWidget {
  const _VoiceExpenseSearchSheet({required this.speechToText});

  final stt.SpeechToText speechToText;

  @override
  State<_VoiceExpenseSearchSheet> createState() =>
      _VoiceExpenseSearchSheetState();
}

class _VoiceExpenseSearchSheetState extends State<_VoiceExpenseSearchSheet> {
  String _words = '';
  String? _error;
  bool _starting = true;

  bool get _listening => widget.speechToText.isListening;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startListening());
  }

  @override
  void dispose() {
    widget.speechToText.stop();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (!mounted) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await widget.speechToText.listen(
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
        onResult: (result) {
          if (!mounted) return;
          final recognized = result.recognizedWords.trim();
          setState(() {
            _words = recognized;
            _starting = false;
          });
          if (result.finalResult && recognized.isNotEmpty && mounted) {
            Navigator.of(context).pop(recognized);
          }
        },
        options: stt.SpeechListenOptions(
          cancelOnError: true,
          partialResults: true,
          listenMode: stt.ListenMode.confirmation,
        ),
      );
      if (mounted) setState(() => _starting = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'Не удалось запустить распознавание речи.';
      });
    }
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await widget.speechToText.stop();
      if (mounted) setState(() {});
    } else {
      await _startListening();
    }
  }

  Future<void> _useQuery() async {
    final value = _words.trim();
    if (value.isEmpty) return;
    await widget.speechToText.stop();
    if (mounted) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Голосовой поиск',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _error ??
                  (_listening || _starting
                      ? 'Говорите. Например: «Сколько потратили на окна за май 2026»'
                      : 'Нажмите на микрофон, чтобы повторить'),
              textAlign: TextAlign.center,
              style: TextStyle(color: _error == null ? _muted : Colors.red),
            ),
            const SizedBox(height: 22),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: _starting ? null : _toggleListening,
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _listening ? _brand : _brandSoft,
                  border: Border.all(
                    color: const Color(0xFFBFD8CC),
                    width: 8,
                  ),
                ),
                child: Icon(
                  _listening ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                  size: 48,
                  color: _listening ? Colors.white : _brand,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _line),
              ),
              child: Text(
                _words.isEmpty ? 'Распознанный запрос появится здесь' : _words,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _words.isEmpty ? _muted : _ink,
                  fontWeight: _words.isEmpty ? FontWeight.w400 : FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _words.trim().isEmpty ? null : _useQuery,
              icon: const Icon(Icons.search_rounded),
              label: const Text('Найти расходы'),
            ),
          ],
        ),
      ),
    );
  }
}
