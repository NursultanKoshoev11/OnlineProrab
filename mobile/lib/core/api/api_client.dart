class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;

  Uri uri(String path) {
    return Uri.parse('$baseUrl$path');
  }
}
