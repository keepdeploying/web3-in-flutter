/// A tiny status payload, used by `GET /health` and by the app to check
/// which backend it is talking to.
Map<String, Object> health({required String mode}) => {'ok': true, 'service': 'flutter_counter_server', 'mode': mode};
