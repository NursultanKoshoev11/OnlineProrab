import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:online_prorab/services/api_client.dart';

void main() {
  test(
    'simplified expense uses internal defaults for removed fields',
    () async {
      final client = ApiClient(
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/cost-items');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['project_id'], 'project-1');
          expect(body['title'], 'Цемент М500');
          expect(body['amount'], 12500);
          expect(body['spent_at'], '2026-09-06');
          expect(body['category'], 'other');
          expect(body['vendor'], '');
          expect(body['currency'], 'KGS');
          return http.Response(jsonEncode({'id': 'cost-1'}), 201);
        }),
      );

      final result = await client.createCostItem(
        projectId: 'project-1',
        title: 'Цемент М500',
        amount: 12500,
        spentAt: '2026-09-06',
      );

      expect(result['id'], 'cost-1');
    },
  );
}
