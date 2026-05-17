import 'package:firebase_auth/firebase_auth.dart';
import 'package:get_it/get_it.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // ── Firebase ──────────────────────────────────────────────────────────
  sl.registerLazySingleton(() => FirebaseAuth.instance);

  // ── Services ──────────────────────────────────────────────────────────
  // Registration of future services goes here

  // ── Repositories ──────────────────────────────────────────────────────
  // Registration of repositories goes here

  // ── BLoCs / Cubits ────────────────────────────────────────────────────
  // Use sl.registerFactory for blocs/cubits to get a fresh instance each time
}
