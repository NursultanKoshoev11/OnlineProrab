import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:online_prorab/features/projects/project_data_repositories.dart';
import 'package:online_prorab/features/projects/project_repository.dart';
import 'package:online_prorab/features/projects/project_team_repository.dart';
import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/api_config.dart';
import 'package:online_prorab/services/auth_repository.dart';
import 'package:online_prorab/services/session_store.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

part 'redesign/auth_login.dart';
part 'redesign/projects_screen.dart';
part 'redesign/project_card.dart';
part 'redesign/workspace.dart';
part 'redesign/overview.dart';
part 'redesign/expenses.dart';
part 'redesign/more_analytics.dart';
part 'redesign/cost_project_form.dart';
part 'redesign/expense_form.dart';
part 'redesign/widgets.dart';
part 'redesign/helpers.dart';

const _ink = Color(0xFF111815);
const _muted = Color(0xFF6F7C75);
const _surface = Color(0xFFF6F8F6);
const _brand = Color(0xFF087A3D);
const _brandSoft = Color(0xFFE5F5EB);
const _line = Color(0xFFE8ECE9);
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
  late final ProjectFileRepository _fileRepository;
  late final ProjectTeamRepository _teamRepository;
  late final stt.SpeechToText _speechToText;

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
    _fileRepository = ProjectFileRepository(apiClient: _apiClient);
    _teamRepository = ProjectTeamRepository(apiClient: _apiClient);
    _speechToText = stt.SpeechToText();
  }

  @override
  void dispose() {
    _apiClient.close();
    _speechToText.cancel();
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
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: _line),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          labelStyle: const TextStyle(color: _muted),
          hintStyle: const TextStyle(color: Color(0xFF9AA49F)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: _brand, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _brand,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 72,
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
        apiClient: _apiClient,
        authRepository: _authRepository,
        projectRepository: _projectRepository,
        costItemRepository: _costItemRepository,
        dailyReportRepository: _dailyReportRepository,
        fileRepository: _fileRepository,
        teamRepository: _teamRepository,
        speechToText: _speechToText,
      ),
    );
  }
}

class _Dependencies {
  const _Dependencies({
    required this.apiClient,
    required this.authRepository,
    required this.projectRepository,
    required this.costItemRepository,
    required this.dailyReportRepository,
    required this.fileRepository,
    required this.teamRepository,
    required this.speechToText,
  });

  final ApiClient apiClient;
  final AuthRepository authRepository;
  final ProjectRepository projectRepository;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final ProjectFileRepository fileRepository;
  final ProjectTeamRepository teamRepository;
  final stt.SpeechToText speechToText;
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({
    required this.apiClient,
    required this.authRepository,
    required this.projectRepository,
    required this.costItemRepository,
    required this.dailyReportRepository,
    required this.fileRepository,
    required this.teamRepository,
    required this.speechToText,
  });

  final ApiClient apiClient;
  final AuthRepository authRepository;
  final ProjectRepository projectRepository;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final ProjectFileRepository fileRepository;
  final ProjectTeamRepository teamRepository;
  final stt.SpeechToText speechToText;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final Future<SessionData?> _sessionFuture;

  _Dependencies get _deps => _Dependencies(
    apiClient: widget.apiClient,
    authRepository: widget.authRepository,
    projectRepository: widget.projectRepository,
    costItemRepository: widget.costItemRepository,
    dailyReportRepository: widget.dailyReportRepository,
    fileRepository: widget.fileRepository,
    teamRepository: widget.teamRepository,
    speechToText: widget.speechToText,
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
