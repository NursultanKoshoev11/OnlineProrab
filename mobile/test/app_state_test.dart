import 'package:flutter_test/flutter_test.dart';
import 'package:online_prorab/app/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('AppState stores projects, expenses, reports and tasks', () async {
    final state = AppState();
    await state.loadFromDevice();

    state.signIn('+996700000000');
    final project = state.addProject(name: 'Demo house', address: 'Bishkek');
    state.addExpense(projectId: project.id, title: 'Cement', amount: 1200, category: 'materials', vendor: 'Supplier');
    state.addReport(projectId: project.id, summary: 'Foundation completed', workersCount: 4, issues: '');
    final task = state.addTask(projectId: project.id, title: 'Buy cement', description: 'Call supplier');

    expect(state.isSignedIn, isTrue);
    expect(state.projects.length, 1);
    expect(state.expensesFor(project.id).length, 1);
    expect(state.reportsFor(project.id).length, 1);
    expect(state.tasksFor(project.id).length, 1);
    expect(state.totalSpent(project.id), 1200);
    expect(state.openTasksCount(project.id), 1);

    state.markTaskDone(task.id);
    expect(state.openTasksCount(project.id), 0);
  });

  test('AppState restores saved data from shared preferences', () async {
    final first = AppState();
    await first.loadFromDevice();
    first.signIn('+996700000000');
    final project = first.addProject(name: 'Saved project', address: 'Osh');
    first.addExpense(projectId: project.id, title: 'Sand', amount: 500, category: 'materials', vendor: 'Supplier');
    await first.saveToDevice();

    final second = AppState();
    await second.loadFromDevice();

    expect(second.isSignedIn, isTrue);
    expect(second.phone, '+996700000000');
    expect(second.projects.length, 1);
    expect(second.projects.first.name, 'Saved project');
    expect(second.totalSpent(second.projects.first.id), 500);
  });
}
