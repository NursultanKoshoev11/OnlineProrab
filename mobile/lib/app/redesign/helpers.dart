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

String _extractSearchTerm(String query) {
  var result = query.toLowerCase();
  const noise = [
    'сколько мы потратили на ',
    'сколько потратили на ',
    'покажи расходы на ',
    'найди расходы на ',
    'покажи ',
    'найди ',
    'расходы ',
    'за май',
    '?',
  ];
  for (final part in noise) {
    result = result.replaceAll(part, '');
  }
  return result.trim();
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
