part of '../online_prorab_redesign.dart';

class _MoreTab extends StatelessWidget {
  const _MoreTab({
    required this.project,
    required this.members,
    required this.onOpenTeam,
    required this.onOpenSubscription,
    required this.onOpenSupport,
    required this.onOpenReport,
    required this.onAddMember,
  });

  final RemoteProject project;
  final List<RemoteProjectMember> members;
  final VoidCallback onOpenTeam;
  final VoidCallback onOpenSubscription;
  final VoidCallback onOpenSupport;
  final VoidCallback onOpenReport;
  final VoidCallback? onAddMember;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
      children: [
        _PageHeader(title: 'Разделы', subtitle: project.name),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.groups_outlined,
          title: 'Команда',
          subtitle: '${members.length} участников',
          onTap: onOpenTeam,
          action: onAddMember == null
              ? null
              : TextButton.icon(
                  onPressed: onAddMember,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
                  label: const Text('Добавить'),
                ),
          children: members.isEmpty
              ? const [
                  Text(
                    'Участники пока не добавлены.',
                    style: TextStyle(color: _muted),
                  ),
                ]
              : members
                    .take(5)
                    .map(
                      (member) => _InfoRow(
                        icon: Icons.person_outline_rounded,
                        title: member.name.isEmpty ? member.phone : member.name,
                        subtitle: _roleLabel(member.role),
                      ),
                    )
                    .toList(),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          icon: Icons.workspace_premium_outlined,
          title: 'Подписка и доступ',
          subtitle: 'Владелец оплачивает доступ команды',
          onTap: onOpenSubscription,
          children: const [
            _InfoRow(
              icon: Icons.people_alt_outlined,
              title: 'Pro · до 5 участников + владелец',
              subtitle: 'MBANK, Optima Bank или QR-код',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          icon: Icons.support_agent_rounded,
          title: 'Техподдержка',
          subtitle: 'Написать в Telegram или WhatsApp',
          onTap: onOpenSupport,
          children: const [
            _InfoRow(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Связаться с поддержкой',
              subtitle:
                  'Обращение сохранится в системе и будет передано оператору',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          icon: Icons.picture_as_pdf_outlined,
          title: 'Отчёт расходов',
          subtitle: 'Предпросмотр PDF по текущим расходам',
          onTap: onOpenReport,
          children: const [
            _InfoRow(
              icon: Icons.picture_as_pdf_outlined,
              title: 'Открыть предпросмотр PDF',
              subtitle: 'Отправить или сохранить через меню предпросмотра',
            ),
          ],
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.onOpen, this.onDelete});

  final RemoteProjectFile file;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Icon(
                file.contentType.startsWith('image/')
                    ? Icons.image_outlined
                    : Icons.insert_drive_file_outlined,
                size: 21,
                color: _muted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.originalName.isEmpty ? 'Файл' : file.originalName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      _fileSize(file.sizeBytes),
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Удалить файл',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, color: _muted),
            ),
        ],
      ),
    );
  }
}

class _ExpenseSummaryCard extends StatelessWidget {
  const _ExpenseSummaryCard({required this.costs});
  final List<RemoteCostItem> costs;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final thisMonthItems = costs.where((item) {
      final date = DateTime.tryParse(item.spentAt);
      if (date == null || date.year != now.year || date.month != now.month) {
        return false;
      }
      return true;
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics_outlined, color: _brand),
                SizedBox(width: 10),
                Text(
                  'Сводка расходов',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              _moneyTotals(costs),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
            ),
            const Text('Всего потрачено', style: TextStyle(color: _muted)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SummaryValue(
                    label: 'Записей',
                    value: '${costs.length}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SummaryValue(
                    label: 'За этот месяц',
                    value: _moneyTotals(thisMonthItems),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.label, required this.value});

  final String label;
  final String value;

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
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, color: _ink),
          ),
        ],
      ),
    );
  }
}
