part of '../online_prorab_redesign.dart';

class _ExpensesTab extends StatefulWidget {
  const _ExpensesTab({
    required this.project,
    required this.repository,
    required this.initial,
    required this.onChanged,
  });

  final RemoteProject project;
  final CostItemRepository repository;
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
    final q = _search.text.trim().toLowerCase();
    return _items.where((item) {
      final matchesQuery =
          q.isEmpty ||
          item.title.toLowerCase().contains(q) ||
          item.category.toLowerCase().contains(q) ||
          item.vendor.toLowerCase().contains(q);
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
        .take(4)
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
                  hintText: 'Поиск расходов...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(6),
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                      ),
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
    final examples = <String>[
      'Сколько мы потратили на окна?',
      'Покажи расходы на цемент',
      'Найди расходы на электрику',
      'Покажи расходы конкретного поставщика',
    ];
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
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
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Скажите, что вы хотите найти',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 22),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _brandSoft,
                  border: Border.all(color: const Color(0xFFBFD8CC), width: 8),
                ),
                child: const Icon(Icons.mic_rounded, size: 48, color: _brand),
              ),
              const SizedBox(height: 22),
              ...examples.map(
                (example) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(context).pop(example),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '«$example»',
                        style: const TextStyle(color: _muted),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (value == null) return;
    _search.text = _extractSearchTerm(value);
    setState(() {});
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
