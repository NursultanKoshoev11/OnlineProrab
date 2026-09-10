part of '../online_prorab_redesign.dart';

class _SubscriptionScreen extends StatefulWidget {
  const _SubscriptionScreen({
    required this.project,
    required this.members,
    required this.canManage,
    required this.apiClient,
  });

  final RemoteProject project;
  final List<RemoteProjectMember> members;
  final bool canManage;
  final ApiClient apiClient;

  @override
  State<_SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<_SubscriptionScreen>
    with WidgetsBindingObserver {
  String _selectedPlan = 'pro';
  String _selectedBank = 'optima';
  bool _busy = false;
  String? _orderId;
  String? _paymentStatus;
  String? _paymentError;
  bool _testMode = false;

  int get _participantCount => widget.members
      .where((member) => member.role.trim().toLowerCase() != 'owner')
      .length;

  int get _participantLimit => switch (_selectedPlan) {
    'free' => 3,
    'business' => 10,
    _ => 5,
  };

  int get _planPrice => switch (_selectedPlan) {
    'free' => 0,
    'business' => 2_990,
    _ => 990,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _orderId != null) {
      _refreshPayment();
    }
  }

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
          _clearPaymentState();
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
          _clearPaymentState();
        }),
      ),
      const SizedBox(height: 9),
      _PlanChoice(
        name: 'Team',
        description: '10 объектов · 10 участников',
        price: '2 990 сом/мес',
        selected: _selectedPlan == 'business',
        onTap: () => setState(() {
          _selectedPlan = 'business';
          _clearPaymentState();
        }),
      ),
      const SizedBox(height: 20),
      const Text(
        'Способ оплаты',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 5),
      const Text(
        'Сервер создаёт защищённый заказ. Данные карты вводятся только на стороне банка.',
        style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
      ),
      const SizedBox(height: 10),
      _BankChoice(
        name: 'MBANK',
        subtitle: 'Пока недоступно',
        icon: 'M',
        selected: _selectedBank == 'mbank',
        onTap: () => setState(() {
          _selectedBank = 'mbank';
          _clearPaymentState();
        }),
      ),
      const SizedBox(height: 9),
      _BankChoice(
        name: 'Optima Bank',
        subtitle: 'Интернет-эквайринг',
        icon: 'O',
        selected: _selectedBank == 'optima',
        onTap: () => setState(() {
          _selectedBank = 'optima';
          _clearPaymentState();
        }),
      ),
      const SizedBox(height: 16),
      _PaymentSummary(price: _planPrice),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _planPrice == 0 || _busy ? null : _startPayment,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.lock_open_rounded),
        label: Text(
          _selectedBank == 'optima'
              ? 'Оплатить через Optima Bank'
              : 'Оплатить через MBANK',
        ),
      ),
      if (_paymentError != null) ...[
        const SizedBox(height: 14),
        _PaymentMessage(
          icon: Icons.info_outline_rounded,
          message: _paymentError!,
          color: _warning,
        ),
      ],
      if (_orderId != null) ...[
        const SizedBox(height: 14),
        _PaymentStatusCard(
          orderId: _orderId!,
          status: _paymentStatus ?? 'pending',
          testMode: _testMode,
          busy: _busy,
          onRefresh: _refreshPayment,
          onCompleteTest: _completeTestPayment,
        ),
      ],
    ];
  }

  void _clearPaymentState() {
    _orderId = null;
    _paymentStatus = null;
    _paymentError = null;
    _testMode = false;
  }

  Future<void> _startPayment() async {
    if (_selectedBank != 'optima') {
      setState(() {
        _paymentError = 'MBANK пока не подключён. Выберите Optima Bank.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _paymentError = null;
      _orderId = null;
      _paymentStatus = null;
    });
    try {
      final response = await widget.apiClient.createSubscriptionCheckout(
        planCode: _selectedPlan,
        provider: _selectedBank,
      );
      final orderId = response['order_id']?.toString() ?? '';
      final paymentUrl = response['payment_url']?.toString() ?? '';
      if (orderId.isEmpty) {
        throw const ApiException(500, 'Сервер не вернул номер заказа');
      }
      if (!mounted) return;
      setState(() {
        _orderId = orderId;
        _paymentStatus = response['status']?.toString() ?? 'pending';
        _testMode = response['test_mode'] == true;
      });
      if (paymentUrl.isNotEmpty) {
        final launched = await launchUrl(
          Uri.parse(paymentUrl),
          mode: LaunchMode.externalApplication,
        );
        if (!launched && mounted) {
          setState(() {
            _paymentError = 'Не удалось открыть страницу Optima.';
          });
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _paymentError = _paymentErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshPayment() async {
    final orderId = _orderId;
    if (orderId == null || _busy) return;
    setState(() => _busy = true);
    try {
      final response = await widget.apiClient.getSubscriptionPaymentStatus(
        orderId,
      );
      if (!mounted) return;
      setState(() {
        _paymentStatus = response['status']?.toString() ?? 'pending';
      });
    } catch (error) {
      if (mounted) setState(() => _paymentError = _paymentErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeTestPayment() async {
    final orderId = _orderId;
    if (orderId == null || !_testMode || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.apiClient.completeTestSubscriptionPayment(orderId);
      if (mounted) setState(() => _paymentStatus = 'paid');
    } catch (error) {
      if (mounted) setState(() => _paymentError = _paymentErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _paymentErrorText(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 503) {
        return 'Optima ещё не подключён на сервере. Нужны официальные API-доступы банка.';
      }
      return error.message;
    }
    return 'Не удалось создать платёж. Проверьте соединение.';
  }
}

class _PaymentMessage extends StatelessWidget {
  const _PaymentMessage({required this.icon, required this.message, required this.color});

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _warningSoft,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 9),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12, height: 1.35))),
        ],
      ),
    );
  }
}

class _PaymentStatusCard extends StatelessWidget {
  const _PaymentStatusCard({
    required this.orderId,
    required this.status,
    required this.testMode,
    required this.busy,
    required this.onRefresh,
    required this.onCompleteTest,
  });

  final String orderId;
  final String status;
  final bool testMode;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onCompleteTest;

  @override
  Widget build(BuildContext context) {
    final paid = status == 'paid';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  paid ? Icons.check_circle_outline : Icons.schedule,
                  color: paid ? _brand : _warning,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    paid ? 'Оплата подтверждена' : 'Ожидаем подтверждение оплаты',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Проверить',
                  onPressed: busy ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            Text(
              'Заказ: $orderId',
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
            if (testMode && !paid) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: busy ? null : onCompleteTest,
                icon: const Icon(Icons.science_outlined),
                label: const Text('Завершить тестовую оплату'),
              ),
            ],
          ],
        ),
      ),
    );
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

