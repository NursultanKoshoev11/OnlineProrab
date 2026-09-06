part of '../online_prorab_redesign.dart';

class _MoreTab extends StatelessWidget {
  const _MoreTab({
    required this.project,
    required this.reports,
    required this.files,
    required this.members,
    required this.costs,
    required this.auditLogs,
    required this.onOpenTeam,
    required this.onAddFile,
    required this.onOpenFile,
    required this.onDeleteFile,
  });

  final RemoteProject project;
  final List<RemoteDailyReport> reports;
  final List<RemoteProjectFile> files;
  final List<RemoteProjectMember> members;
  final List<RemoteCostItem> costs;
  final List<RemoteAuditLog> auditLogs;
  final VoidCallback onOpenTeam;
  final VoidCallback? onAddFile;
  final ValueChanged<RemoteProjectFile> onOpenFile;
  final ValueChanged<RemoteProjectFile>? onDeleteFile;

  @override
  Widget build(BuildContext context) {
    final visibleAuditLogs = auditLogs
        .where((log) => log.entityType.toLowerCase() != 'task')
        .toList();

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
                        subtitle: [
                          if (report.reportDate.isNotEmpty)
                            _displayIsoDate(report.reportDate),
                          '${report.workersCount} работников',
                          if (report.issues.isNotEmpty) 'есть замечания',
                        ].join(' • '),
                      ),
                    )
                    .toList(),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          icon: Icons.folder_outlined,
          title: 'Фото и документы',
          subtitle: '${files.length} файлов',
          action: onAddFile == null
              ? null
              : TextButton.icon(
                  onPressed: onAddFile,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Добавить'),
                ),
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
                      (file) => _FileRow(
                        file: file,
                        onOpen: () => onOpenFile(file),
                        onDelete: onDeleteFile == null
                            ? null
                            : () => onDeleteFile!(file),
                      ),
                    )
                    .toList(),
        ),
        const SizedBox(height: 12),
        _ExpenseSummaryCard(costs: costs),
        const SizedBox(height: 12),
        _SectionCard(
          icon: Icons.history_rounded,
          title: 'Журнал действий',
          subtitle: '${visibleAuditLogs.length} событий',
          children: visibleAuditLogs.isEmpty
              ? const [
                  Text(
                    'Действий пока нет.',
                    style: TextStyle(color: _muted),
                  ),
                ]
              : visibleAuditLogs
                    .take(6)
                    .map(
                      (log) => _InfoRow(
                        icon: Icons.bolt_outlined,
                        title: _auditLogTitle(log),
                        subtitle: _displayDateTime(log.createdAt),
                      ),
                    )
                    .toList(),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.onOpen,
    this.onDelete,
  });

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
