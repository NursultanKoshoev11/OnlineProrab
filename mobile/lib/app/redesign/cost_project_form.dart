part of '../online_prorab_redesign.dart';

class _CostDetails extends StatelessWidget {
  const _CostDetails({required this.item});
  final RemoteCostItem item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Расход',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            height: 190,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [Color(0xFFDCE9E3), Color(0xFFABC7BA)],
              ),
            ),
            child: Icon(_categoryIcon(item.category), size: 84, color: _brand),
          ),
          const SizedBox(height: 18),
          Text(
            item.title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            _money(item.amount, item.currency),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _brand,
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _DetailRow(
                    label: 'Категория',
                    value: _categoryLabel(item.category),
                  ),
                  if (item.vendor.isNotEmpty) ...[
                    const Divider(height: 24),
                    _DetailRow(label: 'Поставщик', value: item.vendor),
                  ],
                  const Divider(height: 24),
                  _DetailRow(label: 'Валюта', value: item.currency),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectForm extends StatefulWidget {
  const _ProjectForm({required this.repository});
  final ProjectRepository repository;

  @override
  State<_ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<_ProjectForm> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Новый объект',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Название объекта',
              prefixIcon: Icon(Icons.home_work_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            decoration: const InputDecoration(
              labelText: 'Адрес',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Создать объект'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Введите название объекта');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createProject(
        name: _name.text.trim(),
        address: _address.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
