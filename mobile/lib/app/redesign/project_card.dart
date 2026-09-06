part of '../online_prorab_redesign.dart';

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.apiClient,
    required this.onTap,
    required this.onEdit,
    this.showDivider = true,
  });

  final RemoteProject project;
  final ApiClient apiClient;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final bool showDivider;

  bool get _canEdit {
    final role = project.role.trim().toLowerCase();
    return role == 'owner' || role == 'manager';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: showDivider
              ? const Border(bottom: BorderSide(color: _line))
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProjectCoverImage(
              apiClient: apiClient,
              fileId: project.coverFileId,
              width: 70,
              height: 70,
              borderRadius: 10,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name.isEmpty ? 'Без названия' : project.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.18,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                      ),
                    ),
                    if (project.address.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 15,
                            color: _muted,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              project.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (project.startDate.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: _muted,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _projectDurationText(project.startDate),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 7),
                    _StatusPill(status: project.status),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),
            Column(
              children: [
                if (_canEdit && onEdit != null)
                  IconButton(
                    tooltip: 'Изменить объект',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, color: _muted),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Icon(Icons.chevron_right_rounded, color: _muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
