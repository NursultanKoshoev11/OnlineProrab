part of '../online_prorab_redesign.dart';

String _expenseWord(int count) {
  final lastTwo = count % 100;
  final last = count % 10;
  if (lastTwo >= 11 && lastTwo <= 14) return 'расходов';
  if (last == 1) return 'расход';
  if (last >= 2 && last <= 4) return 'расхода';
  return 'расходов';
}

class _ExpensesTab extends StatefulWidget {
  const _ExpensesTab({
    required this.project,
    required this.repository,
    required this.fileRepository,
    required this.onOpenFile,
    required this.speechToText,
    required this.initial,
    required this.onChanged,
    required this.canContribute,
    required this.canManage,
  });

  final RemoteProject project;
  final CostItemRepository repository;
  final ProjectFileRepository fileRepository;
  final ValueChanged<RemoteProjectFile> onOpenFile;
  final stt.SpeechToText speechToText;
  final List<RemoteCostItem> initial;
  final ValueChanged<List<RemoteCostItem>> onChanged;
  final bool canContribute;
  final bool canManage;

  @override
  State<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends State<_ExpensesTab> {
  final _search = TextEditingController();
  late List<RemoteCostItem> _items;
  RemoteExpenseAiResult? _aiResult;
  bool _aiLoading = false;
  bool _aiReportOpen = false;
  String? _aiError;

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
    // The AI result is an additional mini-report. It must not replace the
    // ordinary expense report or make its total depend on the voice query.
    if (_aiReportOpen) return List<RemoteCostItem>.of(_items);
    final parsed = parseExpenseSearchQuery(_search.text, now: DateTime.now());
    return _items.where(parsed.matches).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
            children: [
              const Text(
                'РАСХОДЫ',
                style: TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                widget.project.name.isEmpty ? 'Объект' : widget.project.name,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 27,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (widget.project.address.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: _brand,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        widget.project.address,
                        style: const TextStyle(color: _muted, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: _search,
                onChanged: (_) {
                  setState(() {
                    // A manually edited query starts the normal local search
                    // again and closes the previous AI mini-report.
                    _aiReportOpen = false;
                    _aiResult = null;
                    _aiError = null;
                  });
                },
                onSubmitted: _runAiSearch,
                decoration: InputDecoration(
                  hintText: 'Поиск расходов',
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
              if (_aiLoading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 3),
              ],
              if (_aiError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _aiError!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
              if (_aiResult != null) ...[
                const SizedBox(height: 12),
                _AiExpenseResultCard(
                  result: _aiResult!,
                  onClose: _closeAiReport,
                ),
              ],
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Всего потрачено',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _moneyTotals(filtered),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${filtered.length} ${_expenseWord(filtered.length)}',
                        style: const TextStyle(color: _muted, fontSize: 13),
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
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _openDetails(item),
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
                                child: const Icon(
                                  Icons.receipt_long_outlined,
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
                                        color: Colors.black,
                                      ),
                                    ),
                                    if (item.spentAt.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _displayIsoDate(item.spentAt),
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                    if (item.description.trim().isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        item.description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _money(item.amount, item.currency),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
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
        if (widget.canContribute)
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
      builder: (context) =>
          _VoiceExpenseSearchSheet(speechToText: widget.speechToText),
    );
    if (!mounted || value == null || value.trim().isEmpty) return;
    _search.text = value.trim();
    _search.selection = TextSelection.collapsed(offset: _search.text.length);
    setState(() {});
    await _runAiSearch(value.trim());
  }

  Future<void> _runAiSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _aiLoading = true;
      _aiError = null;
      _aiResult = null;
      _aiReportOpen = true;
    });
    try {
      final result = await widget.repository.searchWithAI(
        projectId: widget.project.id,
        query: query.trim(),
      );
      if (!mounted) return;
      setState(() {
        _aiResult = result;
        _aiLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _aiLoading = false;
        _aiError = _errorText(error);
      });
    }
  }

  void _closeAiReport() {
    setState(() {
      _aiResult = null;
      _aiLoading = false;
      _aiError = null;
      _aiReportOpen = false;
      _search.clear();
    });
  }

  Future<void> _openDetails(RemoteCostItem item) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => _CostDetails(
          item: item,
          repository: widget.repository,
          fileRepository: widget.fileRepository,
          onOpenFile: widget.onOpenFile,
          canContribute: widget.canContribute,
          canManage: widget.canManage,
        ),
      ),
    );
    if (!mounted) return;
    if (result is RemoteCostItem) {
      final next = _items
          .map((candidate) => candidate.id == result.id ? result : candidate)
          .toList();
      setState(() => _items = next);
      widget.onChanged(next);
      return;
    }
    if (result == true) {
      final next = _items
          .where((candidate) => candidate.id != item.id)
          .toList();
      setState(() => _items = next);
      widget.onChanged(next);
    }
  }

  Future<void> _addExpense() async {
    final result = await showModalBottomSheet<RemoteCostItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CreateExpenseSheet(
        projectId: widget.project.id,
        repository: widget.repository,
        fileRepository: widget.fileRepository,
      ),
    );
    if (result == null) return;
    setState(() => _items = [result, ..._items]);
    widget.onChanged(_items);
  }
}

class _AiExpenseResultCard extends StatelessWidget {
  const _AiExpenseResultCard({required this.result, required this.onClose});

  final RemoteExpenseAiResult result;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final entries = result.totals.entries.toList();
    return Card(
      color: _brandSoft,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: _brand),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Мини-отчёт по запросу',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${result.matchedCount} ${_expenseWord(result.matchedCount)}',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(width: 2),
                IconButton(
                  tooltip: 'Закрыть мини-отчёт',
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              result.summary,
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const Text(
                '0 сом',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              )
            else
              ...entries.map(
                (entry) => Text(
                  _money(entry.value, entry.key),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            if (result.items.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...result.items.take(4).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _money(item.amount, item.currency),
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (result.note.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                result.note,
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
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
  String _committedWords = '';
  String _activeWords = '';
  String? _error;
  bool _starting = true;
  bool _keepListening = true;
  Timer? _restartTimer;

  bool get _listening => widget.speechToText.isListening;

  @override
  void initState() {
    super.initState();
    _restartTimer = Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => _ensureListening(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startListening());
  }

  @override
  void dispose() {
    _keepListening = false;
    _restartTimer?.cancel();
    widget.speechToText.stop();
    super.dispose();
  }

  void _ensureListening() {
    if (!mounted || !_keepListening || _starting || _listening) return;
    if (_activeWords.trim().isNotEmpty) {
      _committedWords = [_committedWords, _activeWords]
          .where((part) => part.trim().isNotEmpty)
          .join(' ');
      _activeWords = '';
    }
    _startListening();
  }

  Future<void> _startListening() async {
    if (!mounted) return;
    _keepListening = true;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await widget.speechToText.listen(
        onResult: (result) {
          if (!mounted) return;
          final recognized = result.recognizedWords.trim();
          if (recognized.isEmpty) return;
          _activeWords = recognized;
          final combined = [
            _committedWords,
            _activeWords,
          ].where((part) => part.trim().isNotEmpty).join(' ');
          setState(() {
            _words = combined;
            _starting = false;
          });
          if (result.finalResult) {
            _committedWords = combined;
            _activeWords = '';
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(seconds: 45),
          cancelOnError: false,
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
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
      _keepListening = false;
      await widget.speechToText.stop();
      if (mounted) setState(() {});
    } else {
      _keepListening = true;
      await _startListening();
    }
  }

  Future<void> _useQuery() async {
    final value = _words.trim();
    if (value.isEmpty) return;
    _keepListening = false;
    _restartTimer?.cancel();
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
                  border: Border.all(color: const Color(0xFFBFD8CC), width: 8),
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
                  fontWeight: _words.isEmpty
                      ? FontWeight.w400
                      : FontWeight.w700,
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
