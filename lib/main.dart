import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:llamaseek/Constants/constants.dart';
import 'package:llamaseek/Models/settings_route_arguments.dart';
import 'package:llamaseek/Pages/chat_page/chat_page_view_model.dart';
import 'package:llamaseek/Pages/main_page.dart';
import 'package:llamaseek/Pages/settings_page/settings_page.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/memory_service.dart';
import 'package:llamaseek/Services/services.dart';
import 'package:llamaseek/Utils/favicon_cache.dart';
import 'package:llamaseek/Utils/gradient_settings.dart';
import 'package:llamaseek/Utils/material_color_adapter.dart';
import 'package:llamaseek/Utils/mode_palette.dart';
import 'package:llamaseek/Utils/perf_probe.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'package:llamaseek/Utils/request_review_helper.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize PathManager
  await PathManager.initialize();

  // Initialize Hive
  if (Platform.isLinux) {
    Hive.init(PathManager.instance.documentsDirectory.path);
  } else {
    await Hive.initFlutter();
  }

  Hive.registerAdapter(MaterialColorAdapter());

  await Hive.openBox('settings');
  await Hive.openBox('model_readmes');
  final faviconBox =
      await Hive.openBox<Uint8List>(FaviconCache.boxName);
  FaviconCache.instance.attachBox(faviconBox);

  // Initialize RequestReviewHelper and request review if needed
  final reviewHelper = await RequestReviewHelper.initialize();

  await reviewHelper.incrementCount(isLaunch: true);

  final inAppReview = InAppReview.instance;
  if (await inAppReview.isAvailable() && reviewHelper.shouldRequestReview()) {
    await inAppReview.requestReview();
  }

  // One HTTP client shared by OllamaService and MemoryService so they reuse a
  // single TLS connection to ollama.com instead of each paying a cold-start
  // handshake on the first message.
  final sharedHttpClient = http.Client();

  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => OllamaService(client: sharedHttpClient)),
        Provider(create: (_) => DatabaseService()),
        Provider(create: (_) => PermissionService()),
        Provider(create: (_) => ImageService()),
        ChangeNotifierProvider(
          create: (context) => MemoryService(
            db: context.read<DatabaseService>(),
            client: sharedHttpClient,
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => ChatProvider(
            ollamaService: context.read(),
            databaseService: context.read(),
            memoryService: context.read<MemoryService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => ChatPageViewModel(
            chatProvider: context.read(),
            permissionService: context.read(),
            imageService: context.read(),
          ),
        ),
      ],
      child: const DriftPacaApp(),
    ),
  );
}

class DriftPacaApp extends StatelessWidget {
  const DriftPacaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('settings').listenable(
        keys: ['bgColor1', 'bgColor2', 'brightness'],
      ),
      builder: (context, box, _) {
        return MaterialApp(
          title: AppConstants.appName,
          theme: () {
            final pair = readGradientPair(box);
            final brightness =
                _brightness ?? MediaQuery.platformBrightnessOf(context);
            final palette = resolvePalette(
              pair,
              brightness == Brightness.dark ? AppMode.dark : AppMode.normal,
            );
            return ThemeData(
              colorScheme: palette.scheme,
              appBarTheme: const AppBarTheme(centerTitle: true),
              useMaterial3: true,
            );
          }(),
          builder: (context, child) {
            final responsive = ResponsiveBreakpoints.builder(
              breakpoints: [
                const Breakpoint(start: 0, end: 450, name: MOBILE),
                const Breakpoint(start: 451, end: 800, name: TABLET),
                const Breakpoint(start: 801, end: 1920, name: DESKTOP),
              ],
              useShortestSide: true,
              child: child!,
            );
            return kPerfProbe ? PerfProbeHud(child: responsive) : responsive;
          },
          onGenerateRoute: (settings) {
            if (settings.name == '/') {
              return MaterialPageRoute(
                builder: (context) => const DriftPacaMainPage(),
              );
            }

            if (settings.name == '/settings') {
              final args = settings.arguments as SettingsRouteArguments?;

              return CupertinoPageRoute(
                builder: (context) => SettingsPage(arguments: args),
              );
            }

            assert(false, 'Need to implement ${settings.name}');
            return null;
          },
        );
      },
    );
  }

  Brightness? get _brightness {
    final brightnessValue = Hive.box('settings').get('brightness');
    if (brightnessValue == null) return null;
    return brightnessValue == 1 ? Brightness.light : Brightness.dark;
  }
}
