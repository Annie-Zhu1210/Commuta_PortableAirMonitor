import 'package:flutter/widgets.dart';
import 'app.dart';
import 'services/app_services.dart';

Future<void> main() async {
  // Required before any plugin channels are touched (rootBundle,
  // path_provider, etc.) — AppServices.init() loads bundled assets.
  WidgetsFlutterBinding.ensureInitialized();

  await AppServices.instance.init();

  runApp(const CommutaApp());
}