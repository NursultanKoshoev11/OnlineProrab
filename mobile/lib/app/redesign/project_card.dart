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

  bool get _canEdit =>
      const {'owner', 'manager'}.contains(project.role.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: showDivider ? 16 : 0),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _StatusPill(status: project.status),
                    const Spacer(),
                    if (_canEdit && onEdit != null)
                      IconButton(
                        tooltip: 'Изменить объект',
                        onPressed: onEdit,
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 19,
                          color: _muted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name.isEmpty
                                ? 'Без названия'
                                : project.name,
                            style: const TextStyle(
                              fontSize: 21,
                              height: 1.2,
                              letterSpacing: -.4,
                              fontWeight: FontWeight.w600,
                              color: _ink,
                            ),
                          ),
                          if (project.address.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              project.address,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: _muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (project.coverFileId.isNotEmpty) ...[
                      const SizedBox(width: 16),
                      _ProjectCoverImage(
                        apiClient: apiClient,
                        fileId: project.coverFileId,
                        width: 64,
                        height: 64,
                        borderRadius: 6,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 22),
                const Divider(height: 1, color: _line),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 15,
                      color: _muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        project.startDate.isEmpty
                            ? 'Дата начала не указана'
                            : _projectDurationText(project.startDate),
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: _brand,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
