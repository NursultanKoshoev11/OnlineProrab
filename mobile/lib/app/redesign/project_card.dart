part of '../online_prorab_redesign.dart';

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});

  final RemoteProject project;
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
              Container(
                width: 104,
                height: 92,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFDDE8E2), Color(0xFFB8CEC2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.cottage_rounded,
                  color: _brand,
                  size: 46,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            project.name.isEmpty
                                ? 'Без названия'
                                : project.name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                            ),
                          ),
                        ),
                        const Icon(Icons.more_horiz_rounded, color: _muted),
                      ],
                    ),
                    const SizedBox(height: 7),
                    if (project.address.isNotEmpty)
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
                              style: const TextStyle(color: _muted),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 10),
                    _StatusPill(status: project.status),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
