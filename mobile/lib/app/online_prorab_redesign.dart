import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:online_prorab/app/project_team_screen.dart';
import 'package:online_prorab/features/projects/project_data_repositories.dart';
import 'package:online_prorab/features/projects/project_repository.dart';
import 'package:online_prorab/features/projects/project_team_repository.dart';
import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/auth_repository.dart';
import 'package:online_prorab/services/project_file_download_service.dart';
import 'package:online_prorab/services/session_store.dart';
import 'package:online_prorab/services/demo_mode.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

part 'redesign/auth_login.dart';
part 'redesign/projects_screen.dart';
part 'redesign/project_card.dart';
part 'redesign/workspace.dart';
part 'redesign/overview.dart';
part 'redesign/expenses.dart';
part 'redesign/reports.dart';
part 'redesign/files.dart';
part 'redesign/more_analytics.dart';
part 'redesign/cost_project_form.dart';
part 'redesign/expense_form.dart';
part 'redesign/widgets.dart';
part 'redesign/helpers.dart';

const _ink = Color(0xFF111815);
const _muted = Color(0xFF6F7C75);
const _surface = Color(0xFFF4F7F4);
const _brand = Color(0xFF087A3D);
const _brandSoft = Color(0xFFE5F5EB);
const _line = Color(0xFFE8ECE9);
const _warningSoft = Color(0xFFFFF0D6);
const _warning = Color(0xFFC27A16);
const _offlineDemo = bool.fromEnvironment(
  'OFFLINE_DEMO',
  defaultValue: false,
);

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
  late final AuditLogRepository _auditLogRepository;
  late final stt.SpeechToText _speechToText;
  late final http.Client? _demoHttpClient;

  @override
  void initState() {
    super.initState();
    _demoHttpClient = _offlineDemo ? DemoHttpClient() : null;
    _apiClient = ApiClient(httpClient: _demoHttpClient);
    _authRepository = AuthRepository(
      apiClient: _apiClient,
      sessionStore: SessionStore(),
    );
    _projectRepository = ProjectRepository(apiClient: _apiClient);
    _costItemRepository = CostItemRepository(apiClient: _apiClient);
    _dailyReportRepository = DailyReportRepository(apiClient: _apiClient);
    _fileRepository = ProjectFileRepository(apiClient: _apiClient);
    _teamRepository = ProjectTeamRepository(apiClient: _apiClient);
    _auditLogRepository = AuditLogRepository(apiClient: _apiClient);
    _speechToText = stt.SpeechToText();
  }

  @override
  void dispose() {
    _authRepository.dispose();
    _apiClient.close();
    _speechToText.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _brand,
      brightness: Brightness.light,
      surface: _surface,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OnlinePRorab',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme.copyWith(
          primary: _brand,
          onPrimary: Colors.white,
          surface: _surface,
          onSurface: _ink,
          outline: _line,
        ),
        scaffoldBackgroundColor: _surface,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: _surface,
          foregroundColor: _ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: _ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _line),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          labelStyle: const TextStyle(color: _muted),
          hintStyle: const TextStyle(color: Color(0xFF9AA49F)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: _brand, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _brand,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _brand,
            minimumSize: const Size.fromHeight(50),
            side: const BorderSide(color: _line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: _brand,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: _ink,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white,
          selectedColor: _brandSoft,
          side: const BorderSide(color: _line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
          labelStyle: const TextStyle(
            color: _ink,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 68,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          indicatorColor: _brandSoft,
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          showDragHandle: true,
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
        auditLogRepository: _auditLogRepository,
        speechToText: _speechToText,
        offlineDemo: _offlineDemo,
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
    required this.auditLogRepository,
    required this.speechToText,
    required this.offlineDemo,
  });

  final ApiClient apiClient;
  final AuthRepository authRepository;
  final ProjectRepository projectRepository;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final ProjectFileRepository fileRepository;
  final ProjectTeamRepository teamRepository;
  final AuditLogRepository auditLogRepository;
  final stt.SpeechToText speechToText;
  final bool offlineDemo;
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
    required this.auditLogRepository,
    required this.speechToText,
    required this.offlineDemo,
  });

  final ApiClient apiClient;
  final AuthRepository authRepository;
  final ProjectRepository projectRepository;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final ProjectFileRepository fileRepository;
  final ProjectTeamRepository teamRepository;
  final AuditLogRepository auditLogRepository;
  final stt.SpeechToText speechToText;
  final bool offlineDemo;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late Future<SessionData?> _sessionFuture;
  StreamSubscription<void>? _sessionExpiredSubscription;

  _Dependencies get _deps => _Dependencies(
    apiClient: widget.apiClient,
    authRepository: widget.authRepository,
    projectRepository: widget.projectRepository,
    costItemRepository: widget.costItemRepository,
    dailyReportRepository: widget.dailyReportRepository,
    fileRepository: widget.fileRepository,
    teamRepository: widget.teamRepository,
    auditLogRepository: widget.auditLogRepository,
    speechToText: widget.speechToText,
    offlineDemo: widget.offlineDemo,
  );

  @override
  void initState() {
    super.initState();
    _sessionFuture = widget.offlineDemo
        ? Future<SessionData?>.value(
            const SessionData(
              phone: '+996700000001',
              accessToken: 'demo-access-token',
              refreshToken: 'demo-refresh-token',
            ),
          )
        : widget.authRepository.loadSession();
    _sessionExpiredSubscription = widget.authRepository.sessionExpired.listen((
      _,
    ) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() => _sessionFuture = Future<SessionData?>.value(null));
    });
  }

  @override
  void dispose() {
    _sessionExpiredSubscription?.cancel();
    super.dispose();
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
        return _LoginScreen(
          deps: _deps,
          onAuthenticated: (session) => setState(
            () => _sessionFuture = Future<SessionData?>.value(session),
          ),
        );
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
