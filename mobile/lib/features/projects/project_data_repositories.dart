import 'package:online_prorab/services/api_client.dart';

class RemoteCostItem {
  const RemoteCostItem({required this.id, required this.projectId, required this.title, required this.amount, required this.category, required this.currency, required this.vendor});

  final String id;
  final String projectId;
  final String title;
  final double amount;
  final String category;
  final String currency;
  final String vendor;

  factory RemoteCostItem.fromJson(Map<String, dynamic> json) => RemoteCostItem(
        id: json['id']?.toString() ?? '',
        projectId: json['project_id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        category: json['category']?.toString() ?? 'other',
        currency: json['currency']?.toString() ?? 'KGS',
        vendor: json['vendor']?.toString() ?? '',
      );
}

class RemoteDailyReport {
  const RemoteDailyReport({required this.id, required this.projectId, required this.summary, required this.workersCount, required this.issues});

  final String id;
  final String projectId;
  final String summary;
  final int workersCount;
  final String issues;

  factory RemoteDailyReport.fromJson(Map<String, dynamic> json) => RemoteDailyReport(
        id: json['id']?.toString() ?? '',
        projectId: json['project_id']?.toString() ?? '',
        summary: json['summary']?.toString() ?? '',
        workersCount: (json['workers_count'] as num?)?.toInt() ?? 0,
        issues: json['issues']?.toString() ?? '',
      );
}

class RemoteTask {
  const RemoteTask({required this.id, required this.projectId, required this.title, required this.description, required this.status});

  final String id;
  final String projectId;
  final String title;
  final String description;
  final String status;

  factory RemoteTask.fromJson(Map<String, dynamic> json) => RemoteTask(
        id: json['id']?.toString() ?? '',
        projectId: json['project_id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        status: json['status']?.toString() ?? 'open',
      );
}

class RemoteProjectFile {
  const RemoteProjectFile({
    required this.id,
    required this.projectId,
    required this.kind,
    required this.originalName,
    required this.storagePath,
    required this.contentType,
    required this.sizeBytes,
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String kind;
  final String originalName;
  final String storagePath;
  final String contentType;
  final int sizeBytes;
  final String createdAt;

  factory RemoteProjectFile.fromJson(Map<String, dynamic> json) => RemoteProjectFile(
        id: json['id']?.toString() ?? '',
        projectId: json['project_id']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'document',
        originalName: json['original_name']?.toString() ?? '',
        storagePath: json['storage_path']?.toString() ?? '',
        contentType: json['content_type']?.toString() ?? '',
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        createdAt: json['created_at']?.toString() ?? '',
      );
}

class CostItemRepository {
  const CostItemRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<RemoteCostItem>> list(String projectId) async {
    final items = await _apiClient.listCostItems(projectId);
    return items.whereType<Map<String, dynamic>>().map(RemoteCostItem.fromJson).where((item) => item.id.isNotEmpty).toList();
  }

  Future<RemoteCostItem> create({required String projectId, required String title, required double amount, String category = 'other', String currency = 'KGS', String vendor = ''}) async {
    final data = await _apiClient.createCostItem(projectId: projectId, title: title, amount: amount, category: category, currency: currency, vendor: vendor);
    return RemoteCostItem.fromJson(data);
  }
}

class DailyReportRepository {
  const DailyReportRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<RemoteDailyReport>> list(String projectId) async {
    final items = await _apiClient.listDailyReports(projectId);
    return items.whereType<Map<String, dynamic>>().map(RemoteDailyReport.fromJson).where((item) => item.id.isNotEmpty).toList();
  }

  Future<RemoteDailyReport> create({required String projectId, required String summary, required int workersCount, String issues = ''}) async {
    final data = await _apiClient.createDailyReport(projectId: projectId, summary: summary, workersCount: workersCount, issues: issues);
    return RemoteDailyReport.fromJson(data);
  }
}

class TaskRepository {
  const TaskRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<RemoteTask>> list(String projectId) async {
    final items = await _apiClient.listTasks(projectId);
    return items.whereType<Map<String, dynamic>>().map(RemoteTask.fromJson).where((item) => item.id.isNotEmpty).toList();
  }

  Future<RemoteTask> create({required String projectId, required String title, String description = '', String status = 'open'}) async {
    final data = await _apiClient.createTask(projectId: projectId, title: title, description: description, status: status);
    return RemoteTask.fromJson(data);
  }

  Future<RemoteTask> markDone(RemoteTask task) async {
    final data = await _apiClient.updateTask(taskId: task.id, title: task.title, description: task.description, status: 'done');
    return RemoteTask.fromJson(data);
  }
}

class ProjectFileRepository {
  const ProjectFileRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<RemoteProjectFile>> list(String projectId) async {
    final items = await _apiClient.listFiles(projectId);
    return items.whereType<Map<String, dynamic>>().map(RemoteProjectFile.fromJson).where((item) => item.id.isNotEmpty).toList();
  }

  Future<RemoteProjectFile> createMetadata({
    required String projectId,
    required String kind,
    required String originalName,
    required String storagePath,
    required String contentType,
    required int sizeBytes,
  }) async {
    final data = await _apiClient.createFileMetadata(
      projectId: projectId,
      kind: kind,
      originalName: originalName,
      storagePath: storagePath,
      contentType: contentType,
      sizeBytes: sizeBytes,
    );
    return RemoteProjectFile.fromJson(data);
  }
}
