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
        _AnalyticsCard(costs: costs),
      ],
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({required this.costs});
  final List<RemoteCostItem> costs;

  @override
  Widget build(BuildContext context) {
    final total = costs.fold<double>(0, (sum, item) => sum + item.amount);
    final grouped = <String, double>{};
    for (final item in costs) {
      grouped.update(
        item.category,
        (value) => value + item.amount,
        ifAbsent: () => item.amount,
      );
    }
    final entries = grouped.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics_outlined, color: _brand),
                SizedBox(width: 10),
                Text(
                  'Аналитика расходов',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _money(total, costs.isEmpty ? 'KGS' : costs.first.currency),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const Text('Всего потрачено', style: TextStyle(color: _muted)),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              const Text(
                'Нет данных для аналитики.',
                style: TextStyle(color: _muted),
              )
            else
              ...entries.take(5).map((entry) {
                final ratio = total <= 0 ? 0.0 : entry.value / total;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _categoryLabel(entry.key),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${(ratio * 100).round()}%',
                            style: const TextStyle(color: _muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 7,
                          backgroundColor: _line,
                          color: _brand,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
