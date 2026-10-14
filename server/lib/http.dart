/// The HTTP routes, for `bin/server.dart` and tests. Kept out of the main
/// library so the app, which runs [CounterServer] in-process, doesn't pull
/// in shelf.
library;

export 'src/http/routes.dart';
