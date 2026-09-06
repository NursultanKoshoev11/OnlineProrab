part of '../online_prorab_redesign.dart';

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.project,
    required this.costs,
    required this.reports,
    required this.files,
    required this.members,
    required this.openTab,
  });

  final RemoteProject project;
  final List<RemoteCostItem> costs;
  final List<RemoteDailyReport> reports;
  final List<RemoteProjectFile> files;
  final List<RemoteProjectMember> members;
  final ValueChanged<int> openTab;

  @override
  Widget build(BuildContext context) {
    final parsedStartDate = DateTime.tryParse(project.startDate);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
      children: [
        const Text(
          'Объект',
          style: TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: .6,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          project.name.isEmpty ? 'Объект' : project.name,
          style: const TextStyle(
            fontSize: 27,
            height: 1.08,
            fontWeight: FontWeight.w900,
            color: Colors.black,
          ),
        ),
        if (project.address.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 18,
                color: _brand,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  project.address,
                  style: const TextStyle(color: _muted, fontSize: 14),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: _OverviewValue(
                    label: 'Потрачено',
                    value: _moneyTotals(costs),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OverviewValue(
                    label: 'Дата начала',
                    value: parsedStartDate == null
                        ? 'Не указана'
                        : _displayLongDate(parsedStartDate),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        const Text(
          'Разделы объекта',
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _OverviewSectionRow(
                icon: Icons.receipt_long_outlined,
                title: 'Расходы',
                subtitle: 'Все расходы по объекту',
                count: costs.length,
                onTap: () => openTab(1),
              ),
              const Divider(height: 1, color: _line),
              _OverviewSectionRow(
                icon: Icons.assignment_outlined,
                title: 'Отчёты',
                subtitle: 'Ежедневные отчёты со стройки',
                count: reports.length,
                onTap: () => openTab(2),
              ),
              const Divider(height: 1, color: _line),
              _OverviewSectionRow(
                icon: Icons.folder_open_outlined,
                title: 'Файлы',
                subtitle: 'Документы и фотографии объекта',
                count: files.length,
                onTap: () => openTab(3),
              ),
              const Divider(height: 1, color: _line),
              _OverviewSectionRow(
                icon: Icons.groups_outlined,
                title: 'Команда',
                subtitle: 'Участники и доступ к объекту',
                count: members.length,
                onTap: () => openTab(3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverviewSectionRow extends StatelessWidget {
  const _OverviewSectionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _brandSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _brand, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 7),
            const Icon(Icons.chevron_right_rounded, color: _muted),
          ],
        ),
      ],
    );
  }
}

class _OverviewValue extends StatelessWidget {
  const _OverviewValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
