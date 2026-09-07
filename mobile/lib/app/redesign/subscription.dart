part of '../online_prorab_redesign.dart';

class _SubscriptionScreen extends StatefulWidget {
  const _SubscriptionScreen({
    required this.project,
    required this.members,
    required this.canManage,
  });

  final RemoteProject project;
  final List<RemoteProjectMember> members;
  final bool canManage;

  @override
  State<_SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<_SubscriptionScreen> {
  String _selectedPlan = 'pro';
  String _selectedBank = 'mbank';
  bool _showQr = false;

  int get _participantCount => widget.members
      .where((member) => member.role.trim().toLowerCase() != 'owner')
      .length;

  int get _participantLimit => switch (_selectedPlan) {
    'free' => 3,
    'team' => 10,
    _ => 5,
  };

  int get _planPrice => switch (_selectedPlan) {
    'free' => 0,
    'team' => 2_990,
    _ => 990,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подписка'),
        actions: [
          IconButton(
            tooltip: 'Закрыть',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            widget.project.name.isEmpty ? 'Объект' : widget.project.name,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Владелец оплачивает доступ всей команды. Участники отдельно не платят.',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _brandSoft,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.workspace_premium_outlined,
                          color: _brand,
                        ),
                      ),
                      const SizedBox(width: 11),
                      const Expanded(
                        child: Text(
                          '30 дней Pro бесплатно',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '$_participantCount/$_participantLimit',
                        style: const TextStyle(
                          color: _brand,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Пробный период включает расходы, команду, чеки и PDF-предпросмотр.',
                    style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          ..._buildPaymentSection(),
        ],
      ),
    );
  }

  List<Widget> _buildPaymentSection() {
    if (!widget.canManage) {
      return [
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline_rounded, color: _brand),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Оплата доступна владельцу объекта. Ваш доступ уже включён в его подписку.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      const SizedBox(height: 20),
      const Text(
        'Выберите план',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      _PlanChoice(
        name: 'Free',
        description: '1 объект · 3 участника',
        price: '0 сом',
        selected: _selectedPlan == 'free',
        onTap: () => setState(() {
          _selectedPlan = 'free';
          _showQr = false;
        }),
      ),
      const SizedBox(height: 9),
      _PlanChoice(
        name: 'Pro',
        description: '5 объектов · 5 участников',
        price: '990 сом/мес',
        selected: _selectedPlan == 'pro',
        recommended: true,
        onTap: () => setState(() {
          _selectedPlan = 'pro';
          _showQr = false;
        }),
      ),
      const SizedBox(height: 9),
      _PlanChoice(
        name: 'Team',
        description: '10 объектов · 10 участников',
        price: '2 990 сом/мес',
        selected: _selectedPlan == 'team',
        onTap: () => setState(() {
          _selectedPlan = 'team';
          _showQr = false;
        }),
      ),
      const SizedBox(height: 20),
      const Text(
        'Способ оплаты',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 5),
      const Text(
        'Банковский SDK подключим после получения официальных доступов.',
        style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
      ),
      const SizedBox(height: 10),
      _BankChoice(
        name: 'MBANK',
        subtitle: 'Карта или QR-код',
        icon: 'M',
        selected: _selectedBank == 'mbank',
        onTap: () => setState(() {
          _selectedBank = 'mbank';
          _showQr = false;
        }),
      ),
      const SizedBox(height: 9),
      _BankChoice(
        name: 'Optima Bank',
        subtitle: 'Карта или QR-код',
        icon: 'O',
        selected: _selectedBank == 'optima',
        onTap: () => setState(() {
          _selectedBank = 'optima';
          _showQr = false;
        }),
      ),
      const SizedBox(height: 16),
      _PaymentSummary(price: _planPrice),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _planPrice == 0
            ? null
            : () => setState(() => _showQr = true),
        icon: const Icon(Icons.qr_code_2_rounded),
        label: Text(_showQr ? 'QR-код готов' : 'Показать QR-код'),
      ),
      if (_showQr) ...[
        const SizedBox(height: 14),
        _QrPaymentPreview(
          bankName: _selectedBank == 'mbank' ? 'MBANK' : 'Optima Bank',
          amount: _planPrice,
        ),
      ],
      const SizedBox(height: 10),
      const Text(
        'Сейчас это демонстрационный UI. Реальное подтверждение платежа появится после подключения backend и официального банковского доступа.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
      ),
    ];
  }
}

class _PlanChoice extends StatelessWidget {
  const _PlanChoice({
    required this.name,
    required this.description,
    required this.price,
    required this.selected,
    required this.onTap,
    this.recommended = false,
  });

  final String name;
  final String description;
  final String price;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected ? _brandSoft : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? _brand : _line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? _brand : _muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (recommended) ...[
                        const SizedBox(width: 7),
                        const Text(
                          'ПОПУЛЯРНЫЙ',
                          style: TextStyle(
                            color: _brand,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              price,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _BankChoice extends StatelessWidget {
  const _BankChoice({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String subtitle;
  final String icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? _brandSoft : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _brand : _line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? _brand : _brandSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                icon,
                style: TextStyle(
                  color: selected ? Colors.white : _brand,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? _brand : _muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentSummary extends StatelessWidget {
  const _PaymentSummary({required this.price});

  final int price;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'К оплате за 1 месяц',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ),
          Text(
            price == 0 ? 'Бесплатно' : '$price сом',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _QrPaymentPreview extends StatelessWidget {
  const _QrPaymentPreview({required this.bankName, required this.amount});

  final String bankName;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'QR для оплаты через $bankName',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              '$amount сом · STROY Pro',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 15),
            const _DemoQrCode(),
            const SizedBox(height: 12),
            const Text(
              'Демо QR-код. Он станет платёжным после подключения backend.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoQrCode extends StatelessWidget {
  const _DemoQrCode();

  static const _size = 15;

  bool _dark(int row, int column) {
    final finder = (row < 7 && column < 7) ||
        (row < 7 && column >= _size - 7) ||
        (row >= _size - 7 && column < 7);
    if (finder) {
      final top = row < 7 ? row : row - (_size - 7);
      final left = column < 7 ? column : column - (_size - 7);
      return top == 0 || top == 6 || left == 0 || left == 6 ||
          (top >= 2 && top <= 4 && left >= 2 && left <= 4);
    }
    return ((row * 7 + column * 11 + row * column) % 5) < 2;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 178,
      height: 178,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _size,
        ),
        itemCount: _size * _size,
        itemBuilder: (_, index) {
          final row = index ~/ _size;
          final column = index % _size;
          return ColoredBox(
            color: _dark(row, column) ? Colors.black : Colors.white,
          );
        },
      ),
    );
  }
}
