part of '../online_prorab_redesign.dart';

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
    default:
      return value.isEmpty ? 'Статус не указан' : value;
  }
}

String _categoryLabel(String value) {
  switch (value.toLowerCase()) {
    case 'materials':
    case 'material':
      return 'Материалы';
    case 'work':
    case 'works':
    case 'labor':
      return 'Работы';
    case 'equipment':
    case 'technique':
      return 'Техника';
    case 'delivery':
    case 'transport':
      return 'Доставка';
    case 'windows':
      return 'Окна';
    case 'electricity':
      return 'Электрика';
    case 'other':
      return 'Прочее';
    default:
      return value.isEmpty ? 'Прочее' : value;
  }
}

IconData _categoryIcon(String value) {
  switch (value.toLowerCase()) {
    case 'materials':
    case 'material':
      return Icons.inventory_2_outlined;
    case 'work':
    case 'works':
    case 'labor':
      return Icons.handyman_outlined;
    case 'equipment':
    case 'technique':
      return Icons.precision_manufacturing_outlined;
    case 'delivery':
    case 'transport':
      return Icons.local_shipping_outlined;
    case 'windows':
      return Icons.window_outlined;
    case 'electricity':
      return Icons.electrical_services_outlined;
    default:
      return Icons.receipt_long_outlined;
  }
}

String _roleLabel(String role) {
  switch (role.toLowerCase()) {
    case 'owner':
      return 'Владелец';
    case 'foreman':
      return 'Прораб';
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
  const ExpenseSearchQuery({
    required this.term,
    this.category,
    this.month,
    this.year,
  });

  final String term;
  final String? category;
  final int? month;
  final int? year;

  bool matches(RemoteCostItem item) {
    final normalizedTerm = term.trim().toLowerCase();
    final matchesText =
        normalizedTerm.isEmpty ||
        item.title.toLowerCase().contains(normalizedTerm) ||
        item.vendor.toLowerCase().contains(normalizedTerm) ||
        item.category.toLowerCase().contains(normalizedTerm) ||
        _categoryLabel(item.category).toLowerCase().contains(normalizedTerm);

    final matchesCategory =
        category == null || item.category.toLowerCase() == category;

    if (!matchesText || !matchesCategory) return false;
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

  int? month;
  for (final entry in months.entries) {
    if (RegExp('(^|\\s)${entry.key}(\\s|\$)').hasMatch(normalized)) {
      month = entry.value;
      normalized = normalized.replaceAll(entry.key, ' ');
      break;
    }
  }

  int? year;
  final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(normalized);
  if (yearMatch != null) {
    year = int.tryParse(yearMatch.group(1)!);
    normalized = normalized.replaceFirst(yearMatch.group(0)!, ' ');
  } else if (month != null) {
    year = now.year;
  }

  String? category;
  final categoryPatterns = <String, List<RegExp>>{
    'windows': [RegExp(r'\bокна?\b'), RegExp(r'\bокон\b')],
    'electricity': [RegExp(r'\bэлектрик\w*\b'), RegExp(r'\bэлектрич\w*\b')],
    'materials': [RegExp(r'\bматериал\w*\b')],
    'work': [RegExp(r'\bработ\w*\b'), RegExp(r'\bтруд\w*\b')],
    'equipment': [RegExp(r'\bтехник\w*\b'), RegExp(r'\bоборудован\w*\b')],
    'delivery': [RegExp(r'\bдоставк\w*\b'), RegExp(r'\bтранспорт\w*\b')],
  };
  for (final entry in categoryPatterns.entries) {
    if (entry.value.any((pattern) => pattern.hasMatch(normalized))) {
      category = entry.key;
      for (final pattern in entry.value) {
        normalized = normalized.replaceAll(pattern, ' ');
      }
      break;
    }
  }

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

  normalized = normalized.replaceAll(
    RegExp(r'\b(за|в|на|по|за этот|за эту)\b'),
    ' ',
  );
  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

  return ExpenseSearchQuery(
    term: normalized,
    category: category,
    month: month,
    year: year,
  );
}

String _money(double value, String currency) {
  final rounded = value.round().toString();
  final chars = rounded.split('').reversed.toList();
  final buffer = StringBuffer();
  for (var i = 0; i < chars.length; i++) {
    if (i > 0 && i % 3 == 0) buffer.write(' ');
    buffer.write(chars[i]);
  }
  final formatted = buffer.toString().split('').reversed.join();
  final suffix = currency.toUpperCase() == 'KGS' ? 'сом' : currency;
  return '$formatted $suffix';
}

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
}

String _errorText(Object? error) {
  if (error is ApiException) return error.message;
  if (error is AuthException) return error.message;
  return 'Не удалось выполнить запрос. Проверьте соединение и повторите.';
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}
