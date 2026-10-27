part of '../online_prorab_redesign.dart';

const _nativeOBankCheckoutRequested = bool.fromEnvironment(
  'OBANK_NATIVE_CHECKOUT_ENABLED',
  defaultValue: false,
);
const _obankStagingBuild = bool.fromEnvironment(
  'OBANK_STAGING_BUILD',
  defaultValue: false,
);

class _SubscriptionScreen extends StatefulWidget {
  const _SubscriptionScreen({
    this.project,
    this.members = const [],
    this.canManage = true,
    required this.apiClient,
  });

  final RemoteProject? project;
  final List<RemoteProjectMember> members;
  final bool canManage;
  final ApiClient apiClient;

  @override
  State<_SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<_SubscriptionScreen>
    with WidgetsBindingObserver {
  String _selectedPlan = 'trial';
  String _currentPlan = 'trial';
  String _currentStatus = 'trialing';
  String _selectedBillingPeriod = 'month';
  String _currentBillingPeriod = 'month';
  DateTime? _subscriptionEndsAt;
  bool _checkoutBusy = false;
  bool _statusBusy = false;
  String? _checkoutOrderID;
  String? _checkoutMessage;

  bool get _nativeOBankCheckoutEnabled {
    final apiBase = Uri.tryParse(ApiConfig.baseUrl);
    return _nativeOBankCheckoutRequested &&
        _obankStagingBuild &&
        kDebugMode &&
        apiBase != null &&
        apiBase.scheme == 'https' &&
        apiBase.host.isNotEmpty &&
        apiBase.host != 'api.stroy.com.kg';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadCurrentSubscription());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _checkoutOrderID != null) {
      unawaited(_refreshOBankPaymentStatus());
    }
  }

  Future<void> _startOBankCheckout() async {
    if (!_nativeOBankCheckoutEnabled ||
        _selectedPlan == 'trial' ||
        _checkoutBusy) {
      return;
    }
    setState(() {
      _checkoutBusy = true;
      _checkoutMessage = 'Создаём защищённый счёт O!Bank…';
    });

    try {
      final checkout = await widget.apiClient
          .postJson('/api/v1/subscriptions/checkout', {
            'plan_id': _selectedPlan,
            'billing_period': _selectedBillingPeriod,
            'idempotency_key': _newPaymentIdempotencyKey(),
          });
      if (!mounted) return;
      final orderID = checkout['order_id']?.toString() ?? '';
      final status = checkout['status']?.toString() ?? '';
      if (orderID.isEmpty) {
        throw const FormatException('Сервер не вернул номер счёта.');
      }

      if (status == 'paid') {
        await _loadCurrentSubscription();
        if (mounted) {
          setState(() {
            _checkoutOrderID = null;
            _checkoutMessage = 'Платёж уже подтверждён. Тариф обновлён.';
          });
        }
        return;
      }

      final appLink = checkout['app_link']?.toString() ?? '';
      if (!_isValidOBankAppLink(appLink)) {
        throw const FormatException(
          'O!Bank не вернул ссылку на счёт в приложении. Повтори попытку или обратись в поддержку.',
        );
      }

      setState(() {
        _checkoutOrderID = orderID;
        _checkoutMessage = 'Открываем счёт в O!Bank…';
      });
      final opened = await launchUrl(
        Uri.parse(appLink),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(() {
          _checkoutMessage =
              'Не удалось открыть O!Bank. Установи тестовое приложение банка и попробуй ещё раз.';
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _checkoutMessage = error.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => _checkoutMessage = error.message.toString());
    } catch (error) {
      if (mounted) setState(() => _checkoutMessage = error.toString());
    } finally {
      if (mounted) setState(() => _checkoutBusy = false);
    }
  }

  Future<void> _refreshOBankPaymentStatus() async {
    final orderID = _checkoutOrderID;
    if (orderID == null || _statusBusy) return;
    setState(() => _statusBusy = true);
    try {
      final response = await widget.apiClient.getJson(
        '/api/v1/subscriptions/checkout',
        {'order_id': orderID},
      );
      final status = response is Map
          ? response['status']?.toString() ?? ''
          : '';
      if (status == 'paid') {
        await _loadCurrentSubscription();
        if (mounted) {
          setState(() {
            _checkoutOrderID = null;
            _checkoutMessage = 'Оплата подтверждена. Тариф активирован.';
          });
        }
      } else if (status == 'canceled') {
        if (mounted) {
          setState(() {
            _checkoutOrderID = null;
            _checkoutMessage = 'Счёт отменён или истёк. Можно создать новый.';
          });
        }
      } else if (mounted) {
        setState(() {
          _checkoutMessage =
              'Банк ещё обрабатывает платёж. Проверь статус через несколько секунд.';
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _checkoutMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _checkoutMessage = 'Не удалось проверить статус платежа.',
        );
      }
    } finally {
      if (mounted) setState(() => _statusBusy = false);
    }
  }

  bool _isValidOBankAppLink(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'o.kg' &&
        uri.authority == 'o.kg' &&
        uri.path == '/l/a' &&
        uri.queryParameters['t'] == 'wl_unpbill' &&
        (uri.queryParameters['id']?.isNotEmpty ?? false) &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty;
  }

  String _newPaymentIdempotencyKey() {
    final random = Random.secure();
    return List<int>.generate(
      24,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _loadCurrentSubscription() async {
    try {
      final data = await widget.apiClient.getJson(
        '/api/v1/subscriptions/status',
      );
      if (!mounted || data is! Map) return;
      final plan = data['plan']?.toString();
      final period = data['billing_period']?.toString();
      final status = data['status']?.toString();
      final endsAt = DateTime.tryParse(data['ends_at']?.toString() ?? '');
      if (plan == 'trial' || plan == 'standard' || plan == 'max') {
        setState(() {
          _currentPlan = plan!;
          _selectedPlan = plan;
          _currentStatus = status ?? 'trialing';
          _currentBillingPeriod = period == 'year' ? 'year' : 'month';
          _selectedBillingPeriod = _currentBillingPeriod;
          _subscriptionEndsAt = endsAt;
        });
      }
    } catch (_) {
      // The trial default keeps the screen useful while offline or before login.
    }
  }

  int get _participantCount => widget.members
      .where((member) => member.role.trim().toLowerCase() != 'owner')
      .length;

  int _participantLimitFor(String plan) => switch (plan) {
    'trial' => 0,
    'max' => 20,
    _ => 5,
  };

  int get _currentParticipantLimit => _participantLimitFor(_currentPlan);

  int _priceFor(String plan, String billingPeriod) {
    if (plan == 'trial') return 0;
    final monthly = plan == 'max' ? 5_000 : 3_000;
    if (billingPeriod == 'year') {
      final discount = plan == 'max' ? 15 : 10;
      return monthly * 12 * (100 - discount) ~/ 100;
    }
    return monthly;
  }

  int _discountFor(String plan) => switch (plan) {
    'max' => 15,
    'standard' => 10,
    _ => 0,
  };

  int get _planPrice => _priceFor(_selectedPlan, _selectedBillingPeriod);

  String _formatPlanPrice(String plan) {
    if (plan == 'trial') return '0 сом';
    final suffix = _selectedBillingPeriod == 'year' ? 'год' : 'мес';
    return '${_formatMoney(_priceFor(plan, _selectedBillingPeriod))}/$suffix';
  }

  String _planTitle(String plan) => switch (plan) {
    'max' => 'Максимальный',
    'standard' => 'Стандартный',
    _ => 'Пробный период',
  };

  String _formatMoney(int value) {
    final raw = value.toString();
    final groups = <String>[];
    for (var end = raw.length; end > 0; end -= 3) {
      final start = end - 3 < 0 ? 0 : end - 3;
      groups.add(raw.substring(start, end));
    }
    return '${groups.reversed.join(' ')} сом';
  }

  String _formatDate(DateTime value) {
    final date = value.toLocal();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  int? get _daysRemaining {
    final endsAt = _subscriptionEndsAt;
    if (endsAt == null) return null;
    final seconds = endsAt.difference(DateTime.now()).inSeconds;
    if (seconds <= 0) return 0;
    return (seconds + Duration.secondsPerDay - 1) ~/ Duration.secondsPerDay;
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
            widget.project?.name.trim().isNotEmpty == true
                ? widget.project!.name
                : 'Подписка аккаунта',
            style: const TextStyle(
              color: _ink,
              fontSize: 26,
              fontWeight: FontWeight.w700,
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
                      Expanded(
                        child: Text(
                          _currentPlan == 'trial'
                              ? '30 дней бесплатно'
                              : _planTitle(_currentPlan),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (widget.project != null)
                        Text(
                          '$_participantCount/$_currentParticipantLimit',
                          style: const TextStyle(
                            color: _brand,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _currentPlan == 'trial'
                        ? 'Пробный период: 1 объект, только владелец.'
                        : 'Доступ команды включён в план «${_planTitle(_currentPlan)}».',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_subscriptionEndsAt != null)
                    Text(
                      _currentStatus == 'expired'
                          ? 'Подписка закончилась ${_formatDate(_subscriptionEndsAt!)}'
                          : 'Действует до ${_formatDate(_subscriptionEndsAt!)}',
                      style: TextStyle(
                        color: _currentStatus == 'expired'
                            ? Colors.redAccent
                            : _brand,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (_daysRemaining != null && _currentStatus != 'expired')
                    Text(
                      _daysRemaining == 0
                          ? 'Срок заканчивается сегодня'
                          : 'Осталось $_daysRemaining дн.',
                      style: const TextStyle(color: _muted, fontSize: 11),
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
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      _PlanChoice(
        name: 'Пробный',
        description: '1 объект · только владелец',
        price: '0 сом',
        selected: _selectedPlan == 'trial',
        current: _currentPlan == 'trial',
        onTap: () => setState(() {
          _selectedPlan = 'trial';
        }),
      ),
      const SizedBox(height: 9),
      _PlanChoice(
        name: 'Стандартный',
        description: '5 объектов · 5 участников на объект',
        price: _formatPlanPrice('standard'),
        selected: _selectedPlan == 'standard',
        current: _currentPlan == 'standard',
        recommended: true,
        onTap: () => setState(() {
          _selectedPlan = 'standard';
        }),
      ),
      const SizedBox(height: 9),
      _PlanChoice(
        name: 'Максимальный',
        description: '20 объектов · 20 участников на объект',
        price: _formatPlanPrice('max'),
        selected: _selectedPlan == 'max',
        current: _currentPlan == 'max',
        onTap: () => setState(() {
          _selectedPlan = 'max';
        }),
      ),
      if (_selectedPlan != 'trial') ...[
        const SizedBox(height: 16),
        const Text(
          'Период оплаты',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'month', label: Text('Ежемесячно')),
            ButtonSegment(value: 'year', label: Text('За год')),
          ],
          selected: {_selectedBillingPeriod},
          onSelectionChanged: (selection) {
            setState(() {
              _selectedBillingPeriod = selection.first;
            });
          },
        ),
        if (_selectedBillingPeriod == 'year')
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              'Скидка ${_discountFor(_selectedPlan)}% · экономия ${_formatMoney(_priceFor(_selectedPlan, 'month') * 12 - _planPrice)}',
              style: const TextStyle(color: _brand, fontSize: 12),
            ),
          ),
      ],
      const SizedBox(height: 20),
      if (_selectedPlan != 'trial') ...[
        const SizedBox(height: 20),
        _PaymentSummary(
          priceLabel: _formatMoney(_planPrice),
          billingPeriod: _selectedBillingPeriod,
          discountPercent: _discountFor(_selectedPlan),
        ),
        const SizedBox(height: 12),
        if (_nativeOBankCheckoutEnabled)
          _buildNativeOBankCheckoutControls()
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline_rounded, color: _brand),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Покупка в приложении недоступна',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Способ покупки цифровой подписки зависит от платформы, через которую установлено приложение. Здесь отображаются тариф и состояние аккаунта.',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ];
  }

  Widget _buildNativeOBankCheckoutControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _checkoutBusy ? null : _startOBankCheckout,
            icon: _checkoutBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.account_balance_rounded),
            label: Text(
              _checkoutBusy ? 'Готовим оплату…' : 'Оплатить через O!Bank',
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Тестовый сценарий: нужен staging-сервер и тестовое приложение O!Bank.',
          style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
        ),
        if (_checkoutMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _checkoutMessage!,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
        ],
        if (_checkoutOrderID != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _statusBusy ? null : _refreshOBankPaymentStatus,
              icon: _statusBusy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: const Text('Проверить статус платежа'),
            ),
          ),
      ],
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
    this.current = false,
  });

  final String name;
  final String description;
  final String price;
  final bool selected;
  final bool recommended;
  final bool current;
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
                  Wrap(
                    spacing: 7,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (recommended)
                        const Text(
                          'ПОПУЛЯРНЫЙ',
                          style: TextStyle(
                            color: _brand,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                  if (current) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Ваша текущая подписка',
                      style: TextStyle(
                        color: _brand,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                price,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentSummary extends StatelessWidget {
  const _PaymentSummary({
    required this.priceLabel,
    required this.billingPeriod,
    required this.discountPercent,
  });

  final String priceLabel;
  final String billingPeriod;
  final int discountPercent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  billingPeriod == 'year'
                      ? 'К оплате за 1 год'
                      : 'К оплате за 1 месяц',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ),
              Text(
                priceLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (billingPeriod == 'year')
            Text(
              'Годовая скидка: $discountPercent%',
              style: const TextStyle(color: _brand, fontSize: 11),
            ),
        ],
      ),
    );
  }
}
