import 'package:online_prorab/services/api_client.dart';

class RemoteCostItem {
  const RemoteCostItem({
    required this.id,
    required this.projectId,
    required this.title,
    required this.amount,
    required this.category,
    required this.currency,
    required this.vendor,
    required this.spentAt,
    this.receiptFileId = '',
    this.createdAt = '',
  });

  final String id;
  final String projectId;
  final String title;
  final double amount;
  final String category;
  final String currency;
  final String vendor;
  final String spentAt;
  final String receiptFileId;
  final String createdAt;

  factory RemoteCostItem.fromJson(Map<String, dynamic> json) => RemoteCostItem(
    id: json['id']?.toString() ?? '',
    projectId: json['project_id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    category: json['category']?.toString() ?? 'other',
    currency: json['currency']?.toString() ?? 'KGS',
    vendor: json['vendor']?.toString() ?? '',
    spentAt: json['spent_at']?.toString() ?? '',
    receiptFileId: json['receipt_file_id']?.toString() ?? '',
    createdAt: json['created_at']?.toString() ?? '',
  );
}

class RemoteDailyReport {
  const RemoteDailyReport({
    required this.id,
    required this.projectId,
    required this.summary,
    required this.workersCount,
    required this.issues,
    this.reportDate = '',
    this.createdAt = '',
  });

  final String id;
  final String projectId;
  final String summary;
  final int workersCount;
  final String issues;
  final String reportDate;
  final String createdAt;

  factory RemoteDailyReport.fromJson(Map<String, dynamic> json) =>
      RemoteDailyReport(
        id: json['id']?.toString() ?? '',
        projectId: json['project_id']?.toString() ?? '',
        summary: json['summary']?.toString() ?? '',
        workersCount: (json['workers_count'] as num?)?.toInt() ?? 0,
        issues: json['issues']?.toString() ?? '',
        reportDate: json['report_date']?.toString() ?? '',
        createdAt: json['created_at']?.toString() ?? '',
      );
}

class RemoteTask {
  const RemoteTask({
    required this.id,
    required this.projectId,
    required this.title,
    required this.description,
    required this.status,
    this.dueDate = '',
    this.createdAt = '',
  });

  final String id;
  final String projectId;
  final String title;
  final String description;
  final String status;
  final String dueDate;
  final String createdAt;

  factory RemoteTask.fromJson(Map<String, dynamic> json) => RemoteTask(
    id: json['id']?.toString() ?? '',
    projectId: json['project_id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    status: json['status']?.toString() ?? 'open',
    dueDate: json['due_date']?.toString() ?? '',
    createdAt: json['created_at']?.toString() ?? '',
  );
}

class RemoteProjectFile {
  const RemoteProjectFile({
    required this.id,
    required this.projectId,
    required this.kind,
    required this.originalName,
    required this.contentType,
    required this.sizeBytes,
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String kind;
  final String originalName;
  final String contentType;
  final int sizeBytes;
  final String createdAt;

  factory RemoteProjectFile.fromJson(Map<String, dynamic> json) =>
      RemoteProjectFile(
        id: json['id']?.toString() ?? '',
        projectId: json['project_id']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'document',
        originalName: json['original_name']?.toString() ?? '',
        contentType: json['content_type']?.toString() ?? '',
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        createdAt: json['created_at']?.toString() ?? '',
      );
}

class RemoteAuditLog {
  const RemoteAuditLog({
    required this.id,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.createdAt,
  });

  final String id;
  final String action;
  final String entityType;
  final String entityId;
  final String createdAt;

  factory RemoteAuditLog.fromJson(Map<String, dynamic> json) => RemoteAuditLog(
    id: json['id']?.toString() ?? '',
    action: json['action']?.toString() ?? '',
    entityType: json['entity_type']?.toString() ?? '',
    entityId: json['entity_id']?.toString() ?? '',
    createdAt: json['created_at']?.toString() ?? '',
  );
}

class CostItemRepository {
  const CostItemRepository({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<RemoteCostItem>> list(String projectId) async {
    final items = await _apiClient.listCostItems(projectId);
    return items
        .whereType<Map<String, dynamic>>()
        .map(RemoteCostItem.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Future<RemoteCostItem> create({
    required String projectId,
    required String title,
    required double amount,
    required String spentAt,
    String category = 'other',
    String currency = 'KGS',
    String vendor = '',
    String? receiptFileId,
  }) async {
    final data = await _apiClient.createCostItem(
      projectId: projectId,
      title: title,
      amount: amount,
      category: category,
      currency: currency,
      vendor: vendor,
      spentAt: spentAt,
      receiptFileId: receiptFileId,
    );
    return RemoteCostItem.fromJson(data);
  }

  Future<RemoteCostItem> update({
    required String costItemId,
    required String title,
    required double amount,
    required String spentAt,
    String category = 'other',
    String currency = 'KGS',
    String vendor = '',
    String? receiptFileId,
  }) async {
    final data = await _apiClient.updateCostItem(
      costItemId: costItemId,
      title: title,
      amount: amount,
      category: category,
      currency: currency,
      vendor: vendor,
      spentAt: spentAt,
      receiptFileId: receiptFileId,
    );
    return RemoteCostItem.fromJson(data);
  }

  Future<void> delete(String costItemId) =>
      _apiClient.deleteCostItem(costItemId);
}

class DailyReportRepository {
  const DailyReportRepository({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<RemoteDailyReport>> list(String projectId) async {
    final items = await _apiClient.listDailyReports(projectId);
    return items
        .whereType<Map<String, dynamic>>()
        .map(RemoteDailyReport.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Future<RemoteDailyReport> create({
    required String projectId,
    required String summary,
    required int workersCount,
    String issues = '',
    String? reportDate,
  }) async {
    final data = await _apiClient.createDailyReport(
      projectId: projectId,
      summary: summary,
      workersCount: workersCount,
      issues: issues,
      reportDate: reportDate,
    );
    return RemoteDailyReport.fromJson(data);
  }

  Future<RemoteDailyReport> update({
    required String reportId,
    required String summary,
    required int workersCount,
    String issues = '',
    String? reportDate,
  }) async {
    final data = await _apiClient.updateDailyReport(
      reportId: reportId,
      summary: summary,
      workersCount: workersCount,
      issues: issues,
      reportDate: reportDate,
    );
    return RemoteDailyReport.fromJson(data);
  }

  Future<void> delete(String reportId) =>
      _apiClient.deleteDailyReport(reportId);
}

class TaskRepository {
  const TaskRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<RemoteTask>> list(String projectId) async {
    final items = await _apiClient.listTasks(projectId);
    return items
        .whereType<Map<String, dynamic>>()
        .map(RemoteTask.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Future<RemoteTask> create({
    required String projectId,
    required String title,
    String description = '',
    String status = 'open',
    String? dueDate,
  }) async {
    final data = await _apiClient.createTask(
      projectId: projectId,
      title: title,
      description: description,
      status: status,
      dueDate: dueDate,
    );
    return RemoteTask.fromJson(data);
  }

  Future<RemoteTask> update({
    required String taskId,
    required String title,
    String description = '',
    String status = 'open',
    String? dueDate,
  }) async {
    final data = await _apiClient.updateTask(
      taskId: taskId,
      title: title,
      description: description,
      status: status,
      dueDate: dueDate,
    );
    return RemoteTask.fromJson(data);
  }

  Future<RemoteTask> markDone(RemoteTask task) async {
    final data = await _apiClient.updateTask(
      taskId: task.id,
      title: task.title,
      description: task.description,
      status: 'done',
      dueDate: task.dueDate,
    );
    return RemoteTask.fromJson(data);
  }

  Future<void> delete(String taskId) => _apiClient.deleteTask(taskId);
}

class ProjectFileRepository {
  const ProjectFileRepository({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<RemoteProjectFile>> list(String projectId) async {
    final items = await _apiClient.listFiles(projectId);
    return items
        .whereType<Map<String, dynamic>>()
        .map(RemoteProjectFile.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Future<RemoteProjectFile> upload({
    required String projectId,
    required String kind,
    required String filePath,
    required String fileName,
  }) async {
    final data = await _apiClient.uploadProjectFile(
      projectId: projectId,
      kind: kind,
      filePath: filePath,
      fileName: fileName,
    );
    return RemoteProjectFile.fromJson(data);
  }

  Future<void> delete(String fileId) => _apiClient.deleteFile(fileId);

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

class AuditLogRepository {
  const AuditLogRepository({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<RemoteAuditLog>> list(String projectId) async {
    final items = await _apiClient.listAuditLogs(projectId);
    return items
        .whereType<Map<String, dynamic>>()
        .map(RemoteAuditLog.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }
}
