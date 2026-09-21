part of '../online_prorab_redesign.dart';

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.project,
    required this.costs,
    required this.members,
    required this.openTab,
    required this.onOpenTeam,
    required this.onAddMember,
  });

  final RemoteProject project;
  final List<RemoteCostItem> costs;
  final List<RemoteProjectMember> members;
  final ValueChanged<int> openTab;
  final VoidCallback onOpenTeam;
  final VoidCallback? onAddMember;

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
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        if (project.address.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 18, color: _brand),
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
        Container(
          decoration: BoxDecoration(
            color: _brandSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Всего потрачено',
                  style: TextStyle(color: _brand, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  _moneyTotals(costs),
                  style: const TextStyle(
                    color: _brand,
                    fontSize: 32,
                    height: 1.2,
                    letterSpacing: -1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${costs.length} ${_expenseWord(costs.length)} по объекту',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Divider(height: 1, color: Color(0xFFCDD8CE)),
                ),
                _DetailRow(
                  label: 'Дата начала',
                  value: parsedStartDate == null
                      ? 'Не указана'
                      : _displayLongDate(parsedStartDate),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        const Text(
          'Разделы объекта',
          style: TextStyle(
            color: _ink,
            fontSize: 16,
            fontWeight: FontWeight.w600,
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
                icon: Icons.picture_as_pdf_outlined,
                title: 'Отчёт',
                subtitle: 'Предпросмотр PDF по расходам',
                count: 1,
                onTap: () => openTab(2),
              ),
              const Divider(height: 1, color: _line),
              _OverviewSectionRow(
                icon: Icons.groups_outlined,
                title: 'Команда',
                subtitle: 'Участники и доступ к объекту',
                count: members.length,
                onTap: onOpenTeam,
                trailingAction: onAddMember,
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
    this.trailingAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final VoidCallback onTap;
  final VoidCallback? trailingAction;

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
                      color: _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _ink, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 7),
            if (trailingAction != null)
              IconButton(
                tooltip: 'Добавить участника',
                onPressed: trailingAction,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                visualDensity: VisualDensity.compact,
                color: _brand,
              ),
            const Icon(Icons.chevron_right_rounded, color: _muted),
          ],
        ),
      ),
    );
  }
}
