part of '../online_prorab_redesign.dart';

class _SubscriptionScreen extends StatefulWidget {
  const _SubscriptionScreen({
    this.project,
    this.members = const [],
    this.requiredRenewal = false,
    this.onSubscriptionRenewed,
    required this.apiClient,
  });

  final RemoteProject? project;
  final List<RemoteProjectMember> members;
  final bool requiredRenewal;
  final VoidCallback? onSubscriptionRenewed;
  final ApiClient apiClient;

  @override
  State<_SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<_SubscriptionScreen>
    with WidgetsBindingObserver {
  String _currentPlan = 'trial';
  String _currentStatus = 'trialing';
  DateTime? _subscriptionEndsAt;

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
    if (state == AppLifecycleState.resumed) {
      // The account can be paid in the browser while this screen is open.
      // Refresh from the backend when the app returns to the foreground.
      unawaited(_loadCurrentSubscription());
    }
  }

  Future<void> _loadCurrentSubscription() async {
    try {
      final data = await widget.apiClient.getJson(
        '/api/v1/subscriptions/status',
      );
      if (!mounted || data is! Map) return;
      final plan = data['plan']?.toString();
      final status = data['status']?.toString();
      final endsAt = DateTime.tryParse(data['ends_at']?.toString() ?? '');
      if (plan == 'trial' || plan == 'standard' || plan == 'max') {
        setState(() {
          _currentPlan = plan!;
          _currentStatus = status ?? 'trialing';
          _subscriptionEndsAt = endsAt;
        });
        if (widget.requiredRenewal &&
            (status == 'active' || status == 'trialing')) {
          widget.onSubscriptionRenewed?.call();
        }
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

  String _planTitle(String plan) => switch (plan) {
    'max' => 'Максимальный',
    'standard' => 'Стандартный',
    _ => 'Пробный период',
  };

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
        title: Text(widget.requiredRenewal ? 'Доступ к аккаунту' : 'Подписка'),
        actions: widget.requiredRenewal
            ? const []
            : [
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
          Text(
            widget.requiredRenewal
                ? 'Срок действия подписки закончился. Доступ к рабочему пространству приостановлен.'
                : 'Текущий статус подписки и доступ команды.',
            style: const TextStyle(color: _muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 18),
          _buildCurrentSubscriptionCard(),
        ],
      ),
    );
  }

  Widget _buildCurrentSubscriptionCard() {
    return Card(
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
                    _currentStatus == 'expired'
                        ? 'Подписка не активна'
                        : _currentPlan == 'trial'
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
              _currentStatus == 'expired'
                  ? 'Доступ к функциям рабочего пространства временно ограничен.'
                  : _currentPlan == 'trial'
                  ? 'Пробный период: 1 объект, только владелец.'
                  : 'Доступ команды включён в план «${_planTitle(_currentPlan)}».',
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.4),
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
    );
  }
}
