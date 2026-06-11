import 'package:flutter/material.dart';
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
    setState(() {
      membersFuture = widget.repository.listMembers(widget.projectId);
    });
    await membersFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Project team'),
        actions: [
          IconButton(
            tooltip: 'Accept invitation',
            onPressed: _acceptInvite,
            icon: const Icon(Icons.mark_email_read_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<RemoteProjectMember>>(
        future: membersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return TeamErrorState(
              message: _friendlyTeamError(snapshot.error),
              onRetry: _refresh,
            );
          }
          final members = snapshot.data ?? const <RemoteProjectMember>[];
          if (members.isEmpty) {
            return const Center(child: Text('No project members found'));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: members.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final member = members[index];
                return ProjectMemberCard(
                  member: member,
                  onChangeRole: member.role == 'owner'
                      ? null
                      : () => _changeRole(member),
                  onRemove: member.role == 'owner'
                      ? null
                      : () => _removeMember(member),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _inviteMember,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Invite'),
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
          : '\nDevelopment invite token: ${invite.inviteToken}';
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Invitation created'),
          content: Text(
            'The user was invited as ${result.role}.$tokenMessage',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
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
        title: const Text('Accept invitation'),
        content: TextField(
          controller: controller,
          autocorrect: false,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Invite token',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              controller.text.trim(),
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (token == null || token.isEmpty) return;

    try {
      await widget.repository.acceptInvite(token);
      if (!mounted) return;
      _showTeamMessage(context, 'Invitation accepted');
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove project member?'),
        content: Text(
          'Remove ${member.name.isEmpty ? member.phone : member.name} from this project?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
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
      title: const Text('Invite project member'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Phone number',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: role,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Role',
            ),
            items: const [
              DropdownMenuItem(value: 'manager', child: Text('Manager')),
              DropdownMenuItem(value: 'worker', child: Text('Worker')),
              DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
            ],
            onChanged: (value) => setState(() => role = value ?? 'worker'),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final phone = phoneController.text.trim();
            if (phone.length < 9) {
              setState(() => error = 'Enter a valid phone number');
              return;
            }
            Navigator.of(context).pop(
              ProjectInviteInput(phone: phone, role: role),
            );
          },
          child: const Text('Invite'),
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
      title: const Text('Change role'),
      content: DropdownButtonFormField<String>(
        value: role,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Role',
        ),
        items: const [
          DropdownMenuItem(value: 'manager', child: Text('Manager')),
          DropdownMenuItem(value: 'worker', child: Text('Worker')),
          DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
        ],
        onChanged: (value) => setState(() => role = value ?? role),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(role),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class ProjectMemberCard extends StatelessWidget {
  const ProjectMemberCard({
    required this.member,
    required this.onChangeRole,
    required this.onRemove,
    super.key,
  });

  final RemoteProjectMember member;
  final VoidCallback? onChangeRole;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final title = member.name.isEmpty ? member.phone : member.name;
    final subtitleParts = <String>[
      if (member.name.isNotEmpty && member.phone.isNotEmpty) member.phone,
      member.role,
    ];
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(title.isEmpty ? '?' : title.characters.first.toUpperCase()),
        ),
        title: Text(title.isEmpty ? 'Project member' : title),
        subtitle: Text(subtitleParts.join(' • ')),
        trailing: member.role == 'owner'
            ? const Chip(label: Text('Owner'))
            : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'role') onChangeRole?.call();
                  if (value == 'remove') onRemove?.call();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'role', child: Text('Change role')),
                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
              ),
      ),
    );
  }
}

class TeamErrorState extends StatelessWidget {
  const TeamErrorState({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_off_outlined, size: 56),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

void _showTeamMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _friendlyTeamError(Object? error) {
  final text = error.toString();
  if (text.contains('403')) return 'You do not have permission for this action.';
  if (text.contains('409')) return 'This user is already a project member.';
  if (text.contains('401')) return 'Your session expired. Sign in again.';
  if (text.contains('408') || text.contains('timed out')) return 'Server timeout.';
  return text.replaceFirst('Exception: ', '');
}
