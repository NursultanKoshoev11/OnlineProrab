import 'package:online_prorab/services/api_client.dart';

class RemoteProject {
  const RemoteProject({
    required this.id,
    required this.name,
    required this.address,
    required this.status,
    required this.coverFileId,
    required this.startDate,
    this.budgetAmount = 0,
    this.currency = 'KGS',
    this.role = '',
  });

  final String id;
  final String name;
  final String address;
  final String status;
  final String coverFileId;
  final String startDate;
  final double budgetAmount;
  final String currency;
  final String role;

  factory RemoteProject.fromJson(Map<String, dynamic> json) {
    return RemoteProject(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      coverFileId: json['cover_file_id']?.toString() ?? '',
      startDate: json['start_date']?.toString() ?? '',
      budgetAmount: _asDouble(json['budget_amount']),
      currency: json['currency']?.toString() ?? 'KGS',
      role: json['role']?.toString() ?? '',
    );
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

class ProjectRepository {
  const ProjectRepository({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<RemoteProject>> listProjects({
    bool includeArchived = false,
  }) async {
    final items = await _apiClient.listProjects(
      includeArchived: includeArchived,
    );
    return items
        .whereType<Map<String, dynamic>>()
        .map(RemoteProject.fromJson)
        .where((project) => project.id.isNotEmpty)
        .toList();
  }

  Future<RemoteProject> createProject({
    required String name,
    required String address,
    required String startDate,
    double budgetAmount = 0,
    String currency = 'KGS',
  }) async {
    final data = await _apiClient.createProject(
      name,
      address,
      startDate: startDate,
      budgetAmount: budgetAmount,
      currency: currency,
    );
    return RemoteProject.fromJson(data);
  }

  Future<RemoteProject> createProjectWithCover({
    required String name,
    required String address,
    required String startDate,
    required String filePath,
    required String fileName,
    double budgetAmount = 0,
    String currency = 'KGS',
  }) async {
    final data = await _apiClient.createProjectWithCover(
      name: name,
      address: address,
      startDate: startDate,
      filePath: filePath,
      fileName: fileName,
      budgetAmount: budgetAmount,
      currency: currency,
    );
    return RemoteProject.fromJson(data);
  }

  Future<RemoteProject> updateProject({
    required String projectId,
    required String name,
    required String address,
    required String startDate,
    String status = 'active',
    double? budgetAmount,
    String? currency,
  }) async {
    final data = await _apiClient.updateProject(
      projectId,
      name,
      address,
      status: status,
      startDate: startDate,
      budgetAmount: budgetAmount,
      currency: currency,
    );
    return RemoteProject.fromJson(data);
  }

  Future<void> deleteProject(String projectId) {
    return _apiClient.deleteProject(projectId);
  }
}
