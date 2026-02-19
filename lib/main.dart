import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/image_bloc/image_bloc.dart';
import 'bloc/image_bloc/image_events.dart';
import 'bloc/face_bloc/face_bloc.dart';
import 'bloc/face_bloc/face_events.dart';
import 'helper/hive_helper.dart';
import 'helper/theme/app_theme.dart';
import 'repository/image_repository.dart';
import 'repository/face_repository.dart';
import 'services/tflite_service.dart';
import 'services/face_detection_service.dart';
import 'services/embedding_service.dart';
import 'services/clustering_service.dart';
import 'ui/home_screen/home_screen.dart';

Future<void> main() async {
  /// Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  /// Lock orientation to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  /// Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  /// Initialize Hive local database (registers all 3 adapters)
  await HiveHelper.initialize();

  /// Initialize TFLite models (BlazeFace + MobileFaceNet)
  final tfliteService = TFLiteService();
  await tfliteService.initialize();

  /// Debug: print model tensor shapes in development
  assert(() {
    tfliteService.debugPrintShapes();
    return true;
  }());

  runApp(MyApp(tfliteService: tfliteService));
}

class MyApp extends StatelessWidget {
  final TFLiteService tfliteService;

  const MyApp({super.key, required this.tfliteService});

  @override
  Widget build(BuildContext context) {
    /// Build service instances
    final detectionService = FaceDetectionService(tfliteService: tfliteService);
    final embeddingService = EmbeddingService(tfliteService: tfliteService);
    final clusteringService = ClusteringService();

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => const ImageRepository()),
        RepositoryProvider(
          create: (_) => FaceRepository(
            detectionService: detectionService,
            embeddingService: embeddingService,
            clusteringService: clusteringService,
          ),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) =>
                ImageBloc(imageRepository: context.read<ImageRepository>())
                  ..add(const LoadImagesRequested()),
          ),
          BlocProvider(
            create: (context) =>
                FaceBloc(faceRepository: context.read<FaceRepository>())
                  ..add(LoadClustersRequested()),
          ),
        ],
        child: MaterialApp(
          title: 'Image Vault',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: HomeScreen(tfliteService: tfliteService),
        ),
      ),
    );
  }
}
