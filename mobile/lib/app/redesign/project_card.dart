part of '../online_prorab_redesign.dart';

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.apiClient,
    required this.onTap,
  });

  final RemoteProject project;
  final ApiClient apiClient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProjectCoverImage(
                apiClient: apiClient,
                fileId: project.coverFileId,
                width: 112,
                height: 112,
                borderRadius: 16,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name.isEmpty ? 'Без названия' : project.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.18,
                          fontWeight: FontWeight.w900,
                          color: _ink,
                        ),
                      ),
                      if (project.address.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 16,
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
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (project.startDate.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 15,
                              color: _muted,
                            ),
                            const SizedBox(width: 5),
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
                      const SizedBox(height: 9),
                      _StatusPill(status: project.status),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 42),
                child: Icon(Icons.chevron_right_rounded, color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
