import 'package:online_prorab/services/api_client.dart';

class RemoteProject {
  const RemoteProject({
    required this.id,
    required this.name,
    required this.address,
    required this.status,
    required this.coverFileId,
    required this.startDate,
  });

  final String id;
  final String name;
  final String address;
  final String status;
  final String coverFileId;
  final String startDate;

  factory RemoteProject.fromJson(Map<String, dynamic> json) {
    return RemoteProject(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      coverFileId: json['cover_file_id']?.toString() ?? '',
      startDate: json['start_date']?.toString() ?? '',
    );
  }
}

class ProjectRepository {
  const ProjectRepository({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<RemoteProject>> listProjects() async {
    final items = await _apiClient.listProjects();
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
  }) async {
    final data = await _apiClient.createProject(
      name,
      address,
      startDate: startDate,
    );
    return RemoteProject.fromJson(data);
  }

  Future<RemoteProject> createProjectWithCover({
    required String name,
    required String address,
    required String startDate,
    required String filePath,
    required String fileName,
  }) async {
    final data = await _apiClient.createProjectWithCover(
      name: name,
      address: address,
      startDate: startDate,
      filePath: filePath,
      fileName: fileName,
    );
    return RemoteProject.fromJson(data);
  }

  Future<RemoteProject> updateProject({
    required String projectId,
    required String name,
    required String address,
    required String startDate,
    String status = 'active',
  }) async {
    final data = await _apiClient.updateProject(
      projectId,
      name,
      address,
      status: status,
      startDate: startDate,
    );
    return RemoteProject.fromJson(data);
  }

  Future<void> deleteProject(String projectId) {
    return _apiClient.deleteProject(projectId);
  }
}
