import 'package:flutter/material.dart';
import 'package:online_prorab/app/online_prorab_theme.dart';
import 'package:online_prorab/features/projects/project_team_repository.dart';

class ProjectTeamScreen extends StatefulWidget {
  const ProjectTeamScreen({
    required this.projectId,
    required this.repository,
    super.key,
  });

  final String projectId;
  final ProjectTeamRepository repository;

  @override
  State<ProjectTeamScreen> createState() => _ProjectTeamScreenState();
}

class _ProjectTeamScreenState extends State<ProjectTeamScreen> {
  late Future<List<RemoteProjectMember>> membersFuture;

  @override
  void initState() {
    super.initState();
    membersFuture = widget.repository.listMembers(widget.projectId);
  }

  Future<void> _refresh() async {
    final future = widget.repository.listMembers(widget.projectId);
    setState(() => membersFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Команда'),
        actions: [
          IconButton(
            tooltip: 'Принять приглашение',
            onPressed: _acceptInvite,
            icon: const Icon(Icons.mark_email_read_outlined),
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: FutureBuilder<List<RemoteProjectMember>>(
        future: membersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _TeamErrorState(
              message: _friendlyTeamError(snapshot.error),
              onRetry: _refresh,
            );
          }
          final members = snapshot.data ?? const <RemoteProjectMember>[];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
              children: [
                Text('Команда объекта',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(
                  '${members.length} ${_memberWord(members.length)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 22),
                if (members.isEmpty)
                  const _TeamEmptyState()
                else
                  ...members.map(
                    (member) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ProjectMemberCard(
                        member: member,
                        onChangeRole:
                            member.role == 'owner' ? null : () => _changeRole(member),
                        onRemove:
                            member.role == 'owner' ? null : () => _removeMember(member),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        elevation: 0,
        backgroundColor: OnlineProrabColors.primary,
        foregroundColor: Colors.white,
        onPressed: _inviteMember,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text(
          'Добавить участника',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> _inviteMember() async {
    final result = await showDialog<ProjectInviteInput>(
      context: context,
      builder: (_) => const ProjectInviteDialog(),
    );
    if (result == null) return;

    try {
      final invite = await widget.repository.invite(
        projectId: widget.projectId,
        phone: result.phone,
        role: result.role,
      );
      if (!mounted) return;
      final tokenMessage = invite.inviteToken.isEmpty
          ? ''
          : '\n\nТокен приглашения: ${invite.inviteToken}';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Приглашение создано'),
          content: Text(
            'Пользователь приглашён с ролью «${_roleLabel(result.role)}».$tokenMessage',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Готово'),
            ),
          ],
        ),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      _showTeamMessage(context, _friendlyTeamError(error));
    }
  }

  Future<void> _acceptInvite() async {
    final controller = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Принять приглашение'),
        content: TextField(
          controller: controller,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Токен приглашения',
            prefixIcon: Icon(Icons.vpn_key_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Принять'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (token == null || token.isEmpty) return;

    try {
      await widget.repository.acceptInvite(token);
      if (!mounted) return;
      _showTeamMessage(context, 'Приглашение принято.');
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      _showTeamMessage(context, _friendlyTeamError(error));
    }
  }

  Future<void> _changeRole(RemoteProjectMember member) async {
    final role = await showDialog<String>(
      context: context,
      builder: (_) => RoleSelectionDialog(currentRole: member.role),
    );
    if (role == null || role == member.role) return;
    try {
      await widget.repository.updateRole(
        projectId: widget.projectId,
        userId: member.userId,
        role: role,
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      _showTeamMessage(context, _friendlyTeamError(error));
    }
  }

  Future<void> _removeMember(RemoteProjectMember member) async {
    final name = member.name.isEmpty ? member.phone : member.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: Text('$name будет удалён из команды этого объекта.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.repository.removeMember(
        projectId: widget.projectId,
        userId: member.userId,
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      _showTeamMessage(context, _friendlyTeamError(error));
    }
  }
}

class ProjectInviteInput {
  const ProjectInviteInput({required this.phone, required this.role});

  final String phone;
  final String role;
}

class ProjectInviteDialog extends StatefulWidget {
  const ProjectInviteDialog({super.key});

  @override
  State<ProjectInviteDialog> createState() => _ProjectInviteDialogState();
}

class _ProjectInviteDialogState extends State<ProjectInviteDialog> {
  final phoneController = TextEditingController(text: '+996');
  String role = 'worker';
  String? error;

  @override
  void dispose() {
    phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Добавить участника'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Номер телефона',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: role,
            decoration: const InputDecoration(labelText: 'Роль'),
            items: const [
              DropdownMenuItem(value: 'manager', child: Text('Прораб / менеджер')),
              DropdownMenuItem(value: 'worker', child: Text('Рабочий')),
              DropdownMenuItem(value: 'viewer', child: Text('Наблюдатель')),
            ],
            onChanged: (value) => setState(() => role = value ?? 'worker'),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: Colors.redAccent)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final phone = phoneController.text.trim();
            if (phone.length < 9) {
              setState(() => error = 'Введите корректный номер телефона.');
              return;
            }
            Navigator.of(context).pop(ProjectInviteInput(phone: phone, role: role));
          },
          child: const Text('Пригласить'),
        ),
      ],
    );
  }
}

class RoleSelectionDialog extends StatefulWidget {
  const RoleSelectionDialog({required this.currentRole, super.key});

  final String currentRole;

  @override
  State<RoleSelectionDialog> createState() => _RoleSelectionDialogState();
}

class _RoleSelectionDialogState extends State<RoleSelectionDialog> {
  late String role;

  @override
  void initState() {
    super.initState();
    role = widget.currentRole;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Изменить роль'),
      content: DropdownButtonFormField<String>(
        initialValue: role,
        decoration: const InputDecoration(labelText: 'Роль'),
        items: const [
          DropdownMenuItem(value: 'manager', child: Text('Прораб / менеджер')),
          DropdownMenuItem(value: 'worker', child: Text('Рабочий')),
          DropdownMenuItem(value: 'viewer', child: Text('Наблюдатель')),
        ],
        onChanged: (value) => setState(() => role = value ?? role),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(role),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _ProjectMemberCard extends StatelessWidget {
  const _ProjectMemberCard({
    required this.member,
    required this.onChangeRole,
    required this.onRemove,
  });

  final RemoteProjectMember member;
  final VoidCallback? onChangeRole;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final name = member.name.isEmpty ? member.phone : member.name;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 23,
              backgroundColor: OnlineProrabColors.mint,
              child: Text(
                initial,
                style: const TextStyle(
                  color: OnlineProrabColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    member.name.isEmpty ? _roleLabel(member.role) : '${member.phone} • ${_roleLabel(member.role)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (onChangeRole != null || onRemove != null)
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'role') onChangeRole?.call();
                  if (value == 'remove') onRemove?.call();
                },
                itemBuilder: (_) => [
                  if (onChangeRole != null)
                    const PopupMenuItem(value: 'role', child: Text('Изменить роль')),
                  if (onRemove != null)
                    const PopupMenuItem(value: 'remove', child: Text('Удалить из команды')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _TeamEmptyState extends StatelessWidget {
  const _TeamEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
      decoration: BoxDecoration(
        color: OnlineProrabColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: OnlineProrabColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.groups_2_outlined, size: 46, color: OnlineProrabColors.primary),
          const SizedBox(height: 14),
          Text('Участников пока нет', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Добавьте прораба, рабочих или наблюдателей.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _TeamErrorState extends StatelessWidget {
  const _TeamErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: OnlineProrabColors.textMuted),
            const SizedBox(height: 14),
            Text('Не удалось загрузить команду', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 7),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

String _roleLabel(String role) {
  switch (role.toLowerCase()) {
    case 'owner':
      return 'Владелец';
    case 'manager':
      return 'Прораб / менеджер';
    case 'worker':
      return 'Рабочий';
    case 'viewer':
      return 'Наблюдатель';
    default:
      return role;
  }
}

String _memberWord(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 == 1 && mod100 != 11) return 'участник';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return 'участника';
  }
  return 'участников';
}

void _showTeamMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _friendlyTeamError(Object? error) {
  final text = error.toString();
  if (text.contains('401')) return 'Сессия истекла. Войдите снова.';
  if (text.contains('403')) return 'Недостаточно прав для управления командой.';
  if (text.contains('404')) return 'Участник или проект не найден.';
  if (text.contains('409')) return 'Пользователь уже добавлен или приглашён.';
  if (text.contains('Connection refused') || text.contains('ApiException(0)')) {
    return 'Не удалось подключиться к серверу.';
  }
  return text.replaceFirst('Exception: ', '');
}
