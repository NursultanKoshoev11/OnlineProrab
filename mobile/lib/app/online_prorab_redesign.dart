import 'package:flutter/material.dart';
import 'package:online_prorab/features/projects/project_data_repositories.dart';
import 'package:online_prorab/features/projects/project_repository.dart';
import 'package:online_prorab/features/projects/project_team_repository.dart';
import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/auth_repository.dart';
import 'package:online_prorab/services/session_store.dart';

part 'redesign/auth_login.dart';
part 'redesign/projects_screen.dart';
part 'redesign/project_card.dart';
part 'redesign/workspace.dart';
part 'redesign/overview.dart';
part 'redesign/expenses.dart';
part 'redesign/tasks.dart';
part 'redesign/more_analytics.dart';
part 'redesign/cost_project_form.dart';
part 'redesign/expense_form.dart';
part 'redesign/task_form.dart';
part 'redesign/widgets.dart';
part 'redesign/helpers.dart';

const _ink = Color(0xFF101512);
const _muted = Color(0xFF718078);
const _surface = Color(0xFFF7F8F6);
const _brand = Color(0xFF315F4D);
const _brandSoft = Color(0xFFDFF2E7);
const _line = Color(0xFFE7EBE8);
const _warningSoft = Color(0xFFFFF0D6);
const _warning = Color(0xFFC27A16);

class OnlineProrabRedesignApp extends StatefulWidget {
  const OnlineProrabRedesignApp({super.key});

  @override
  State<OnlineProrabRedesignApp> createState() =>
      _OnlineProrabRedesignAppState();
}

class _OnlineProrabRedesignAppState extends State<OnlineProrabRedesignApp> {
  late final ApiClient _apiClient;
  late final AuthRepository _authRepository;
  late final ProjectRepository _projectRepository;
  late final CostItemRepository _costItemRepository;
  late final DailyReportRepository _dailyReportRepository;
  late final TaskRepository _taskRepository;
  late final ProjectFileRepository _fileRepository;
  late final ProjectTeamRepository _teamRepository;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _authRepository = AuthRepository(
      apiClient: _apiClient,
      sessionStore: SessionStore(),
    );
    _projectRepository = ProjectRepository(apiClient: _apiClient);
    _costItemRepository = CostItemRepository(apiClient: _apiClient);
    _dailyReportRepository = DailyReportRepository(apiClient: _apiClient);
    _taskRepository = TaskRepository(apiClient: _apiClient);
    _fileRepository = ProjectFileRepository(apiClient: _apiClient);
    _teamRepository = ProjectTeamRepository(apiClient: _apiClient);
  }

  @override
  void dispose() {
    _apiClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _brand,
      brightness: Brightness.light,
      surface: Colors.white,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OnlinePRorab',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme.copyWith(primary: _brand),
        scaffoldBackgroundColor: _surface,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: _surface,
          foregroundColor: _ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: _line),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: const TextStyle(color: _muted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _brand, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _brand,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          indicatorColor: _brandSoft,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected) ? _brand : _muted,
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
        ),
      ),
      home: _AuthGate(
        authRepository: _authRepository,
        projectRepository: _projectRepository,
        costItemRepository: _costItemRepository,
        dailyReportRepository: _dailyReportRepository,
        taskRepository: _taskRepository,
        fileRepository: _fileRepository,
        teamRepository: _teamRepository,
      ),
    );
  }
}

class _Dependencies {
  const _Dependencies({
    required this.authRepository,
    required this.projectRepository,
    required this.costItemRepository,
    required this.dailyReportRepository,
    required this.taskRepository,
    required this.fileRepository,
    required this.teamRepository,
  });

  final AuthRepository authRepository;
  final ProjectRepository projectRepository;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final TaskRepository taskRepository;
  final ProjectFileRepository fileRepository;
  final ProjectTeamRepository teamRepository;
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({
    required this.authRepository,
    required this.projectRepository,
    required this.costItemRepository,
    required this.dailyReportRepository,
    required this.taskRepository,
    required this.fileRepository,
    required this.teamRepository,
  });

  final AuthRepository authRepository;
  final ProjectRepository projectRepository;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final TaskRepository taskRepository;
  final ProjectFileRepository fileRepository;
  final ProjectTeamRepository teamRepository;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final Future<SessionData?> _sessionFuture;

  _Dependencies get _deps => _Dependencies(
    authRepository: widget.authRepository,
    projectRepository: widget.projectRepository,
    costItemRepository: widget.costItemRepository,
    dailyReportRepository: widget.dailyReportRepository,
    taskRepository: widget.taskRepository,
    fileRepository: widget.fileRepository,
    teamRepository: widget.teamRepository,
  );

  @override
  void initState() {
    super.initState();
    _sessionFuture = widget.authRepository.loadSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SessionData?>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingScreen();
        }
        if (snapshot.data case final session?) {
          return _ProjectsScreen(session: session, deps: _deps);
        }
        return _LoginScreen(deps: _deps);
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BrandMark(size: 66),
            SizedBox(height: 18),
            CircularProgressIndicator(color: _brand),
          ],
        ),
      ),
    );
  }
}
