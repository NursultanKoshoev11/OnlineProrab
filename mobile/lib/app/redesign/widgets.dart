part of '../online_prorab_redesign.dart';

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _brand,
        borderRadius: BorderRadius.circular(size * .24),
      ),
      child: Icon(
        Icons.home_work_rounded,
        size: size * .58,
        color: Colors.white,
      ),
    );
  }
}

class _BrandWordmark extends StatelessWidget {
  const _BrandWordmark();
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _BrandMark(size: 36),
        SizedBox(width: 9),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Online',
                style: TextStyle(color: _ink),
              ),
              TextSpan(
                text: 'PRorab',
                style: TextStyle(color: _brand),
              ),
            ],
          ),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final active = status.toLowerCase() == 'active';
    final background = active ? _brandSoft : _warningSoft;
    final foreground = active ? _brand : _warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle_rounded : Icons.archive_outlined,
            size: 14,
            color: foreground,
          ),
          const SizedBox(width: 4),
          Text(
            _projectStatusLabel(status),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _brand, size: 22),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: _brand),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _brandSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: _brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(color: _muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 21, color: _muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: _muted)),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 34),
        child: Column(
          children: [
            Icon(icon, size: 48, color: _brand),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.retry});
  final String message;
  final Future<void> Function() retry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 52, color: _muted),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted),
            ),
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: retry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, this.size = 48});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: _brandSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _brand, size: size * .45),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE6F1EA), Color(0xFFC6DDD0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.cottage_rounded, size: 54, color: _brand),
      ),
    );
  }
}

class _ProjectCoverImage extends StatelessWidget {
  const _ProjectCoverImage({
    required this.apiClient,
    required this.fileId,
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  final ApiClient apiClient;
  final String fileId;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    if (fileId.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: SizedBox(
          width: width,
          height: height,
          child: const _CoverPlaceholder(),
        ),
      );
    }

    final token = apiClient.accessToken;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: Image.network(
          ApiConfig.endpoint('/api/v1/files/download', {
            'file_id': fileId,
          }).toString(),
          headers: {
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => const _CoverPlaceholder(),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              color: _brandSoft,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: _brand),
              ),
            );
          },
        ),
      ),
    );
  }
}
