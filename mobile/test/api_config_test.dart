import 'package:flutter_test/flutter_test.dart';
import 'package:online_prorab/services/api_config.dart';

void main() {
  test('ApiConfig builds endpoint with query parameters', () {
    final uri = ApiConfig.endpoint('/api/v1/projects', {'page': '1'});
    expect(uri.path, '/api/v1/projects');
    expect(uri.queryParameters['page'], '1');
  });
  test('ApiConfig accepts paths without leading slash', () {
    expect(ApiConfig.endpoint('api/v1/projects').path, '/api/v1/projects');
  });
  test('API paths retain query encoding and accept a leading slash', () {
    final uri = ApiConfig.endpoint('/api/v1/projects', {'search': 'Дом & сад'});
    expect(uri.path, '/api/v1/projects');
    expect(uri.queryParameters['search'], 'Дом & сад');
    expect(ApiConfig.endpoint('api/v1/projects').path, uri.path);
    expect(uri.scheme, 'https');
  });
}
