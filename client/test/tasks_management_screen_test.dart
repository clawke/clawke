import 'package:client/models/managed_task.dart';
import 'package:client/providers/tasks_provider.dart';
import 'package:client/providers/ws_state_provider.dart';
import 'package:client/screens/tasks_management_screen.dart';
import 'package:client/services/tasks_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/pump_helpers.dart';

class _TimeoutTasksApiService extends TasksApiService {
  @override
  Future<List<ManagedTask>> listTasks({String? accountId}) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/api/tasks'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/tasks'),
        statusCode: 504,
        data: const {'error': 'gateway_timeout'},
      ),
      type: DioExceptionType.badResponse,
    );
  }
}

void main() {
  testWidgets('task gateway errors stay centered until dismissed', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: [
        tasksApiServiceProvider.overrideWithValue(_TimeoutTasksApiService()),
        connectedAccountsProvider.overrideWith(
          (ref) => [
            const ConnectedAccount(accountId: 'hermes', agentName: 'Hermes'),
          ],
        ),
      ],
      screenSize: const Size(1280, 800),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const ValueKey('tasks_error_panel')), findsOneWidget);
    expect(
      find.text('Hermes 网关响应超时，请确认 Hermes Gateway 正在运行后重试。'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('tasks_error_close')));
    await tester.pump();

    expect(find.byKey(const ValueKey('tasks_error_panel')), findsNothing);
  });
}
