part of '../online_prorab_redesign.dart';

class _MoreTab extends StatelessWidget {
  const _MoreTab({
    required this.project,
    required this.reports,
    required this.files,
    required this.members,
    required this.costs,
  });

  final RemoteProject project;
  final List<RemoteDailyReport> reports;
  final List<RemoteProjectFile> files;
  final List<RemoteProjectMember> members;
  final List<RemoteCostItem> costs;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
      children: [
        const Text(
          'Ещё',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(project.name, style: const TextStyle(color: _muted)),
        const SizedBox(height: 18),
        _SectionCard(
          icon: Icons.groups_outlined,
          title: 'Команда',
          subtitle: '${members.length} участников',
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
          icon: Icons.assignment_outlined,
          title: 'Ежедневные отчёты',
          subtitle: '${reports.length} отчётов',
          children: reports.isEmpty
              ? const [
                  Text('Отчётов пока нет.', style: TextStyle(color: _muted)),
                ]
              : reports
                    .take(4)
                    .map(
                      (report) => _InfoRow(
                        icon: Icons.description_outlined,
                        title: report.summary.isEmpty
                            ? 'Отчёт'
                            : report.summary,
                        subtitle:
                            '${report.workersCount} работников${report.issues.isEmpty ? '' : ' • есть замечания'}',
                      ),
                    )
                    .toList(),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          icon: Icons.folder_outlined,
          title: 'Фото и документы',
          subtitle: '${files.length} файлов',
          children: files.isEmpty
              ? const [
                  Text(
                    'Файлы пока не загружены.',
                    style: TextStyle(color: _muted),
                  ),
                ]
              : files
                    .take(5)
                    .map(
                      (file) => _InfoRow(
                        icon: file.contentType.startsWith('image/')
                            ? Icons.image_outlined
                            : Icons.insert_drive_file_outlined,
                        title: file.originalName.isEmpty
                            ? 'Файл'
                            : file.originalName,
                        subtitle: _fileSize(file.sizeBytes),
                      ),
                    )
                    .toList(),
        ),
        const SizedBox(height: 12),
        _ExpenseSummaryCard(costs: costs),
      ],
    );
  }
}

class _ExpenseSummaryCard extends StatelessWidget {
  const _ExpenseSummaryCard({required this.costs});
  final List<RemoteCostItem> costs;

  @override
  Widget build(BuildContext context) {
    final total = costs.fold<double>(0, (sum, item) => sum + item.amount);
    final now = DateTime.now();
    final thisMonth = costs.fold<double>(0, (sum, item) {
      final date = DateTime.tryParse(item.spentAt);
      if (date == null || date.year != now.year || date.month != now.month) {
        return sum;
      }
      return sum + item.amount;
    });
    final currency = costs.isEmpty ? 'KGS' : costs.first.currency;

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
              _money(total, currency),
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
                    value: _money(thisMonth, currency),
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
