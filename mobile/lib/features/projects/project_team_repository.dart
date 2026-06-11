import 'package:online_prorab/services/api_client.dart';

class RemoteProjectMember {
  const RemoteProjectMember({
    required this.userId,
    required this.phone,
    required this.name,
    required this.role,
    required this.createdAt,
  });

  final String userId;
  final String phone;
  final String name;
  final String role;
  final String createdAt;

  factory RemoteProjectMember.fromJson(Map<String, dynamic> json) {
    return RemoteProjectMember(
      userId: json['user_id']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      role: json['role']?.toString() ?? 'viewer',
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}

class ProjectInviteResult {
  const ProjectInviteResult({
    required this.status,
    required this.expiresIn,
    this.inviteToken = '',
  });

  final String status;
  final int expiresIn;
  final String inviteToken;

  factory ProjectInviteResult.fromJson(Map<String, dynamic> json) {
    return ProjectInviteResult(
      status: json['status']?.toString() ?? '',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
      inviteToken: json['invite_token']?.toString() ?? '',
    );
  }
}

class ProjectTeamRepository {
  const ProjectTeamRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<RemoteProjectMember>> listMembers(String projectId) async {
    final data = await _apiClient.getJson(
      '/api/v1/project-members',
      {'project_id': projectId},
    );
    final items = _asList(data);
    return items
        .whereType<Map<String, dynamic>>()
        .map(RemoteProjectMember.fromJson)
        .where((member) => member.userId.isNotEmpty)
        .toList();
  }

  Future<ProjectInviteResult> invite({
    required String projectId,
    required String phone,
    required String role,
  }) async {
    final data = await _apiClient.postJson('/api/v1/project-invites', {
      'project_id': projectId,
      'phone': phone,
      'role': role,
    });
    return ProjectInviteResult.fromJson(data);
  }

  Future<void> acceptInvite(String inviteToken) async {
    await _apiClient.postJson('/api/v1/project-invites/accept', {
      'invite_token': inviteToken,
    });
  }

  Future<void> updateRole({
    required String projectId,
    required String userId,
    required String role,
  }) async {
    await _apiClient.patchJson(
      '/api/v1/project-members/$userId?project_id=$projectId',
      {'role': role},
    );
  }

  Future<void> removeMember({
    required String projectId,
    required String userId,
  }) async {
    await _apiClient.deleteJson(
      '/api/v1/project-members/$userId?project_id=$projectId',
    );
  }

  List<dynamic> _asList(dynamic data) {
    if (data is List<dynamic>) return data;
    if (data is Map<String, dynamic>) {
      final items = data['items'];
      if (items is List<dynamic>) return items;
    }
    return const <dynamic>[];
  }
}
