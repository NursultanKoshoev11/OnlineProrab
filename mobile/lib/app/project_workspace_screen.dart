import 'package:flutter/material.dart';
import 'package:online_prorab/app/backend_project_dashboard_v2.dart';
import 'package:online_prorab/app/project_team_screen.dart';
import 'package:online_prorab/features/projects/project_data_repositories.dart';
import 'package:online_prorab/features/projects/project_repository.dart';
import 'package:online_prorab/features/projects/project_team_repository.dart';

class ProjectWorkspaceScreen extends StatelessWidget {
  const ProjectWorkspaceScreen({
    required this.project,
    required this.costItemRepository,
    required this.dailyReportRepository,
    required this.taskRepository,
    required this.fileRepository,
    required this.teamRepository,
    super.key,
  });

  final RemoteProject project;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final TaskRepository taskRepository;
  final ProjectFileRepository fileRepository;
  final ProjectTeamRepository teamRepository;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(project.name.isEmpty ? 'Project' : project.name),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Dashboard'),
              Tab(icon: Icon(Icons.groups_outlined), text: 'Team'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            BackendProjectDashboardScreenV2(
              project: project,
              costItemRepository: costItemRepository,
              dailyReportRepository: dailyReportRepository,
              taskRepository: taskRepository,
              fileRepository: fileRepository,
              embedded: true,
            ),
            ProjectTeamScreen(
              projectId: project.id,
              repository: teamRepository,
              embedded: true,
            ),
          ],
        ),
      ),
    );
  }
}
