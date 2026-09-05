part of '../online_prorab_redesign.dart';

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.project,
    required this.costs,
    required this.files,
    required this.members,
    required this.openTab,
  });

  final RemoteProject project;
  final List<RemoteCostItem> costs;
  final List<RemoteProjectFile> files;
  final List<RemoteProjectMember> members;
  final ValueChanged<int> openTab;

  @override
  Widget build(BuildContext context) {
    final spent = costs.fold<double>(0, (sum, item) => sum + item.amount);
    final photos = files
        .where(
          (file) =>
              file.kind.toLowerCase().contains('photo') ||
              file.contentType.toLowerCase().startsWith('image/'),
        )
        .length;
    final currency = costs.isEmpty ? 'KGS' : costs.first.currency;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
      children: [
        Container(
          height: 190,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Color(0xFFDCE9E3), Color(0xFFABC7BA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              const Positioned(
                right: 22,
                bottom: 10,
                child: Icon(
                  Icons.house_siding_rounded,
                  size: 125,
                  color: Color(0x55315F4D),
                ),
              ),
              Positioned(
                left: 18,
                top: 18,
                child: _StatusPill(status: project.status),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          project.name.isEmpty ? 'Объект' : project.name,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        if (project.address.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 18, color: _muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  project.address,
                  style: const TextStyle(color: _muted),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => openTab(1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _brandSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: _brand,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Потрачено на объект',
                          style: TextStyle(color: _muted, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _money(spent, currency),
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        Text(
                          '${costs.length} записей расходов',
                          style: const TextStyle(color: _muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: _muted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.groups_outlined,
                label: 'Команда',
                value: '${members.length}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                icon: Icons.photo_library_outlined,
                label: 'Фото',
                value: '$photos',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Быстрый доступ',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickAction(
                icon: Icons.receipt_long_outlined,
                label: 'Расходы',
                onTap: () => openTab(1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickAction(
                icon: Icons.groups_outlined,
                label: 'Команда',
                onTap: () => openTab(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickAction(
                icon: Icons.photo_camera_outlined,
                label: 'Фото',
                onTap: () => openTab(2),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
