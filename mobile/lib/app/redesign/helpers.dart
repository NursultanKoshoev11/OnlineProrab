part of '../online_prorab_redesign.dart';

String _normalizePhone(String value) => value.replaceAll(RegExp(r'\D'), '');

// ignore: unused_element
String _auditLogTitle(RemoteAuditLog log) {
  final action = _auditActionLabel(log.action);
  final entity = _auditEntityLabel(log.entityType);
  return '$action: $entity';
}

String _auditActionLabel(String value) {
  switch (value.toLowerCase()) {
    case 'create':
      return 'Создание';
    case 'update':
      return 'Изменение';
    case 'delete':
      return 'Удаление';
    case 'upload':
      return 'Загрузка';
    case 'archive':
      return 'Архивирование';
    case 'invite':
      return 'Приглашение';
    case 'accept_invite':
      return 'Принятие приглашения';
    case 'update_role':
      return 'Изменение роли';
    default:
      return value.isEmpty ? 'Действие' : value;
  }
}

String _auditEntityLabel(String value) {
  switch (value.toLowerCase()) {
    case 'project':
      return 'объект';
    case 'cost_item':
      return 'расход';
    case 'daily_report':
      return 'отчёт';
    case 'file':
      return 'файл';
    case 'project_member':
      return 'участник';
    default:
      return value.isEmpty ? 'запись' : value;
  }
}

String _projectStatusLabel(String value) {
  switch (value.toLowerCase()) {
    case 'active':
      return 'В работе';
    case 'planning':
      return 'Планирование';
    case 'paused':
      return 'Пауза';
    case 'done':
    case 'completed':
      return 'Завершён';
    case 'archived':
      return 'В архиве';
    default:
      return value.isEmpty ? 'Статус не указан' : value;
  }
}

String _roleLabel(String role) {
  switch (role.toLowerCase()) {
    case 'owner':
      return 'Владелец';
    case 'foreman':
      return 'Участник';
    case 'manager':
      return 'Менеджер';
    case 'worker':
      return 'Мастер';
    case 'viewer':
      return 'Наблюдатель';
    default:
      return role;
  }
}

class ExpenseSearchQuery {
  const ExpenseSearchQuery({required this.term, this.month, this.year});

  final String term;
  final int? month;
  final int? year;

  bool matches(RemoteCostItem item) {
    final normalizedTerm = term.trim().toLowerCase();
    final matchesText =
        normalizedTerm.isEmpty ||
        item.title.toLowerCase().contains(normalizedTerm) ||
        item.description.toLowerCase().contains(normalizedTerm) ||
        item.vendor.toLowerCase().contains(normalizedTerm);
    if (!matchesText) return false;
    if (month == null && year == null) return true;

    final spentAt = DateTime.tryParse(item.spentAt);
    if (spentAt == null) return false;
    if (month != null && spentAt.month != month) return false;
    if (year != null && spentAt.year != year) return false;
    return true;
  }
}

ExpenseSearchQuery parseExpenseSearchQuery(
  String query, {
  required DateTime now,
}) {
  var normalized = query.toLowerCase().replaceAll('ё', 'е').trim();
  normalized = normalized.replaceAll(RegExp(r'[?!,.;:]'), ' ');
  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

  const months = <String, int>{
    'январь': 1,
    'января': 1,
    'январе': 1,
    'февраль': 2,
    'февраля': 2,
    'феврале': 2,
    'март': 3,
    'марта': 3,
    'марте': 3,
    'апрель': 4,
    'апреля': 4,
    'апреле': 4,
    'май': 5,
    'мая': 5,
    'мае': 5,
    'июнь': 6,
    'июня': 6,
    'июне': 6,
    'июль': 7,
    'июля': 7,
    'июле': 7,
    'август': 8,
    'августа': 8,
    'августе': 8,
    'сентябрь': 9,
    'сентября': 9,
    'сентябре': 9,
    'октябрь': 10,
    'октября': 10,
    'октябре': 10,
    'ноябрь': 11,
    'ноября': 11,
    'ноябре': 11,
    'декабрь': 12,
    'декабря': 12,
    'декабре': 12,
  };

  var tokens = normalized
      .split(' ')
      .where((token) => token.isNotEmpty)
      .toList();
  int? month;
  for (final token in List<String>.of(tokens)) {
    final parsedMonth = months[token];
    if (parsedMonth != null) {
      month = parsedMonth;
      tokens.remove(token);
      break;
    }
  }

  int? year;
  for (final token in List<String>.of(tokens)) {
    final value = int.tryParse(token);
    if (value != null && value >= 2000 && value <= 2100) {
      year = value;
      tokens.remove(token);
      break;
    }
  }
  if (year == null && month != null) year = now.year;

  normalized = tokens.join(' ');
  const noisePhrases = <String>[
    'сколько мы потратили',
    'сколько потратили',
    'сколько было потрачено',
    'сколько потрачено',
    'какие были расходы',
    'покажи расходы',
    'найди расходы',
    'покажи траты',
    'найди траты',
    'расходы',
    'траты',
    'покажи',
    'найди',
  ];
  for (final phrase in noisePhrases) {
    normalized = normalized.replaceAll(phrase, ' ');
  }

  const stopWords = <String>{'за', 'в', 'на', 'по', 'этот', 'эту', 'этом'};
  normalized = normalized
      .split(' ')
      .where((token) => token.isNotEmpty && !stopWords.contains(token))
      .join(' ')
      .trim();

  return ExpenseSearchQuery(term: normalized, month: month, year: year);
}

String _displayDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}

String _displayLongDate(DateTime value) {
  const months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

String _apiDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _displayIsoDate(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null ? value : _displayDate(parsed);
}

String _projectDurationText(String startDate, {DateTime? now}) {
  final start = DateTime.tryParse(startDate);
  if (start == null) return 'Срок не указан';
  final current = now ?? DateTime.now();
  final from = DateTime(start.year, start.month, start.day);
  final to = DateTime(current.year, current.month, current.day);
  final days = to.difference(from).inDays;
  if (days <= 0) return 'Начат сегодня';
  if (days < 31) return 'Строится $days ${_dayWord(days)}';

  var months = (to.year - from.year) * 12 + to.month - from.month;
  if (to.day < from.day) months--;
  if (months < 12) return 'Строится $months мес.';

  final years = months ~/ 12;
  final remainingMonths = months % 12;
  if (remainingMonths == 0) return 'Строится $years г.';
  return 'Строится $years г. $remainingMonths мес.';
}

String _dayWord(int value) {
  final lastTwo = value % 100;
  if (lastTwo >= 11 && lastTwo <= 14) return 'дней';
  switch (value % 10) {
    case 1:
      return 'день';
    case 2:
    case 3:
    case 4:
      return 'дня';
    default:
      return 'дней';
  }
}

String _money(double value, String currency) {
  final safeValue = value.isFinite ? value : 0;
  final negative = safeValue < 0;
  final cents = (safeValue.abs() * 100).round();
  final whole = (cents ~/ 100).toString();
  final fraction = cents % 100;
  final chars = whole.split('').reversed.toList();
  final buffer = StringBuffer();
  for (var i = 0; i < chars.length; i++) {
    if (i > 0 && i % 3 == 0) buffer.write(' ');
    buffer.write(chars[i]);
  }
  final formattedWhole = buffer.toString().split('').reversed.join();
  final formatted = fraction == 0
      ? formattedWhole
      : '$formattedWhole.${fraction.toString().padLeft(2, '0')}';
  final suffix = currency.toUpperCase() == 'KGS' ? 'сом' : currency;
  return '${negative ? '-' : ''}$formatted $suffix';
}

const _maxMoneyAmount = 999999999999.99;

bool _isValidMoney(double value, {bool allowZero = true}) {
  if (!value.isFinite || value < 0 || (!allowZero && value == 0)) {
    return false;
  }
  return value <= _maxMoneyAmount &&
      ((value * 100).round() / 100) <= _maxMoneyAmount;
}

Map<String, double> _totalsByCurrency(Iterable<RemoteCostItem> items) {
  final totals = <String, double>{};
  for (final item in items) {
    final currency = item.currency.trim().toUpperCase().isEmpty
        ? 'KGS'
        : item.currency.trim().toUpperCase();
    totals[currency] = (totals[currency] ?? 0) + item.amount;
  }
  return totals;
}

String _moneyTotals(Iterable<RemoteCostItem> items) {
  final totals = _totalsByCurrency(items);
  if (totals.isEmpty) return _money(0, 'KGS');
  return totals.entries
      .map((entry) => _money(entry.value, entry.key))
      .join(' • ');
}

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
}

// ignore: unused_element
String _displayDateTime(String value) {
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed == null) return value.isEmpty ? 'Дата неизвестна' : value;
  String pad(int number) => number.toString().padLeft(2, '0');
  return '${pad(parsed.day)}.${pad(parsed.month)}.${parsed.year} '
      '${pad(parsed.hour)}:${pad(parsed.minute)}';
}

String _errorText(Object? error) {
  if (error is ApiException) {
    return _localizedErrorMessage(
      statusCode: error.statusCode,
      message: error.message,
    );
  }
  if (error is AuthException) {
    return _localizedErrorMessage(message: error.message);
  }
  return _localizedErrorMessage(message: error?.toString() ?? '');
}

String _localizedErrorMessage({int? statusCode, required String message}) {
  const generic =
      'Не удалось выполнить запрос. Проверьте соединение и повторите.';
  final normalized = message
      .replaceFirst(
        RegExp(r'^(ApiException|AuthException|FormatException|Exception):?\s*'),
        '',
      )
      .trim();
  final lower = normalized.toLowerCase();

  if (statusCode == 0 ||
      statusCode == 408 ||
      lower.contains('timeout') ||
      lower.contains('timed out') ||
      lower.contains('connection') ||
      lower.contains('network') ||
      lower.contains('clientexception')) {
    return 'Не удалось подключиться к серверу. Проверьте интернет и повторите.';
  }
  if (statusCode == 401 ||
      lower.contains('session expired') ||
      lower.contains('unauthorized') ||
      lower.contains('access token')) {
    return 'Сессия истекла. Войдите снова.';
  }
  if (lower.contains('subscription') && lower.contains('expired')) {
    return 'Срок подписки истёк. Продлите подписку, чтобы продолжить.';
  }
  if (statusCode == 403 ||
      lower.contains('subscription') ||
      lower.contains('forbidden')) {
    return 'Доступ ограничен. Проверьте подписку или права доступа.';
  }
  if (statusCode == 404 || lower.contains('not found')) {
    return 'Запрашиваемые данные не найдены.';
  }
  if (statusCode == 413 ||
      lower.contains('too large') ||
      lower.contains('payload')) {
    return 'Файл слишком большой. Выберите файл меньшего размера.';
  }
  if (statusCode == 429 || lower.contains('too many')) {
    return 'Слишком много запросов. Повторите попытку позже.';
  }
  // Backend responses may be localized already. Keep those messages, but
  // never expose an unlocalized English implementation detail to the user.
  if (RegExp(r'[А-Яа-яЁё]').hasMatch(normalized)) return normalized;
  if (lower.contains('sms') && lower.contains('unavailable')) {
    return 'Сервис SMS временно недоступен. Повторите попытку позже.';
  }
  if (lower.contains('sms') || lower.contains('code')) {
    return 'Не удалось отправить или проверить код. Повторите попытку позже.';
  }
  if (statusCode != null && statusCode >= 500) {
    return 'На сервере произошла ошибка. Повторите попытку позже.';
  }
  if (lower.contains('invalid json') ||
      lower.contains('invalid project') ||
      lower.contains('support channels') ||
      lower.contains('refresh token') ||
      lower.contains('request failed') ||
      lower.contains('backend returned') ||
      lower.contains('backend did not return') ||
      lower.contains('failed')) {
    return generic;
  }
  return generic;
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}
