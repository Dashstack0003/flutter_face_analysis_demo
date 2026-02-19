
import 'package:hive_flutter/hive_flutter.dart';
import '../models/image_model.dart';
import '../models/face_model.dart';
import '../models/cluster_model.dart';

/// Helper class to manage Hive database operations
class HiveHelper {
  static const String _imageBoxName   = 'images';
  static const String _faceBoxName    = 'faces';
  static const String _clusterBoxName = 'clusters';

  /// Box instances
  static Box<ImageModel>?   _imageBox;
  static Box<FaceModel>?    _faceBox;
  static Box<ClusterModel>? _clusterBox;

  /// Initialize Hive and register all adapters
  static Future<void> initialize() async {
    await Hive.initFlutter();

    // Register Hive adapters — typeId must match each model
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ImageModelAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(FaceModelAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ClusterModelAdapter());
    }
  }

  // ─────────────────────────────────────────
  // Image Box
  // ─────────────────────────────────────────

  /// Open the image box
  static Future<Box<ImageModel>> openImageBox() async {
    if (_imageBox != null && _imageBox!.isOpen) {
      return _imageBox!;
    }
    _imageBox = await Hive.openBox<ImageModel>(_imageBoxName);
    return _imageBox!;
  }

  /// Get the image box (opens if not already open)
  static Future<Box<ImageModel>> getImageBox() async {
    return await openImageBox();
  }

  // ─────────────────────────────────────────
  // Face Box
  // ─────────────────────────────────────────

  /// Open the face box
  static Future<Box<FaceModel>> openFaceBox() async {
    if (_faceBox != null && _faceBox!.isOpen) {
      return _faceBox!;
    }
    _faceBox = await Hive.openBox<FaceModel>(_faceBoxName);
    return _faceBox!;
  }

  /// Get the face box (opens if not already open)
  static Future<Box<FaceModel>> getFaceBox() async {
    return await openFaceBox();
  }

  /// Add a single face to the database
  static Future<void> addFace(FaceModel face) async {
    final box = await getFaceBox();
    await box.put(face.id, face);
  }

  /// Add multiple faces in one batch write
  static Future<void> addFaces(List<FaceModel> faces) async {
    final box = await getFaceBox();
    final map = {for (final f in faces) f.id: f};
    await box.putAll(map);
  }

  /// Get a face by ID
  static Future<FaceModel?> getFaceById(String id) async {
    final box = await getFaceBox();
    return box.get(id);
  }

  /// Get all faces
  static Future<List<FaceModel>> getAllFaces() async {
    final box = await getFaceBox();
    return box.values.toList();
  }

  /// Get all faces belonging to a specific image
  static Future<List<FaceModel>> getFacesByImageId(String imageId) async {
    final box = await getFaceBox();
    return box.values.where((f) => f.imageId == imageId).toList();
  }

  /// Get all faces belonging to a specific cluster
  static Future<List<FaceModel>> getFacesByClusterId(int clusterId) async {
    final box = await getFaceBox();
    return box.values.where((f) => f.clusterId == clusterId).toList();
  }

  /// Get all faces that have an embedding (ready for clustering)
  static Future<List<FaceModel>> getFacesWithEmbeddings() async {
    final box = await getFaceBox();
    return box.values.where((f) => f.hasEmbedding).toList();
  }

  /// Get all faces that have NOT yet been clustered
  static Future<List<FaceModel>> getUnclusteredFaces() async {
    final box = await getFaceBox();
    return box.values.where((f) => !f.isClustered && f.hasEmbedding).toList();
  }

  /// Update a face (e.g. after embedding is added or cluster assigned)
  static Future<void> updateFace(FaceModel face) async {
    final box = await getFaceBox();
    await box.put(face.id, face);
  }

  /// Update multiple faces in one batch write
  static Future<void> updateFaces(List<FaceModel> faces) async {
    final box = await getFaceBox();
    final map = {for (final f in faces) f.id: f};
    await box.putAll(map);
  }

  /// Delete all faces belonging to a specific image
  static Future<void> deleteFacesByImageId(String imageId) async {
    final box = await getFaceBox();
    final toDelete = box.values
        .where((f) => f.imageId == imageId)
        .map((f) => f.id)
        .toList();
    await box.deleteAll(toDelete);
  }

  /// Get the total number of faces stored
  static Future<int> getFaceCount() async {
    final box = await getFaceBox();
    return box.length;
  }

  /// Clear all faces
  static Future<void> clearAllFaces() async {
    final box = await getFaceBox();
    await box.clear();
  }

  // ─────────────────────────────────────────
  // Cluster Box
  // ─────────────────────────────────────────

  /// Open the cluster box
  static Future<Box<ClusterModel>> openClusterBox() async {
    if (_clusterBox != null && _clusterBox!.isOpen) {
      return _clusterBox!;
    }
    _clusterBox = await Hive.openBox<ClusterModel>(_clusterBoxName);
    return _clusterBox!;
  }

  /// Get the cluster box (opens if not already open)
  static Future<Box<ClusterModel>> getClusterBox() async {
    return await openClusterBox();
  }

  /// Save or update a cluster
  static Future<void> saveCluster(ClusterModel cluster) async {
    final box = await getClusterBox();
    // Key by clusterId so overwriting updates the same record
    await box.put(cluster.clusterId, cluster);
  }

  /// Save multiple clusters in one batch write
  static Future<void> saveClusters(List<ClusterModel> clusters) async {
    final box = await getClusterBox();
    final map = {for (final c in clusters) c.clusterId: c};
    await box.putAll(map);
  }

  /// Get a cluster by its ID
  static Future<ClusterModel?> getClusterById(int clusterId) async {
    final box = await getClusterBox();
    return box.get(clusterId);
  }

  /// Get all clusters, sorted by face count descending (most faces first)
  static Future<List<ClusterModel>> getAllClusters() async {
    final box = await getClusterBox();
    final clusters = box.values.toList();
    clusters.sort((a, b) => b.faceCount.compareTo(a.faceCount));
    return clusters;
  }

  /// Get total number of clusters (= number of unique people)
  static Future<int> getClusterCount() async {
    final box = await getClusterBox();
    return box.length;
  }

  /// Delete a specific cluster
  static Future<void> deleteCluster(int clusterId) async {
    final box = await getClusterBox();
    await box.delete(clusterId);
  }

  /// Clear all clusters (used before re-clustering)
  static Future<void> clearAllClusters() async {
    final box = await getClusterBox();
    await box.clear();
  }

  /// Add a new image to the database
  static Future<void> addImage(ImageModel image) async {
    final box = await getImageBox();
    await box.put(image.id, image);
  }

  /// Get all images from the database
  static Future<List<ImageModel>> getAllImages() async {
    final box = await getImageBox();
    return box.values.toList();
  }

  /// Get a specific image by ID
  static Future<ImageModel?> getImageById(String id) async {
    final box = await getImageBox();
    return box.get(id);
  }

  /// Update an existing image
  static Future<void> updateImage(ImageModel image) async {
    final box = await getImageBox();
    await box.put(image.id, image);
  }

  /// Delete an image by ID
  static Future<void> deleteImage(String id) async {
    final box = await getImageBox();
    await box.delete(id);
  }

  /// Delete multiple images by IDs
  static Future<void> deleteImages(List<String> ids) async {
    final box = await getImageBox();
    await box.deleteAll(ids);
  }

  /// Clear all images from the database
  static Future<void> clearAllImages() async {
    final box = await getImageBox();
    await box.clear();
  }

  /// Get the total number of images
  static Future<int> getImageCount() async {
    final box = await getImageBox();
    return box.length;
  }

  /// Check if an image exists by ID
  static Future<bool> imageExists(String id) async {
    final box = await getImageBox();
    return box.containsKey(id);
  }

  /// Close all Hive boxes
  static Future<void> closeBoxes() async {
    if (_imageBox != null && _imageBox!.isOpen) {
      await _imageBox!.close();
      _imageBox = null;
    }
    if (_faceBox != null && _faceBox!.isOpen) {
      await _faceBox!.close();
      _faceBox = null;
    }
    if (_clusterBox != null && _clusterBox!.isOpen) {
      await _clusterBox!.close();
      _clusterBox = null;
    }
  }

  /// Close Hive completely (use on app termination)
  static Future<void> closeHive() async {
    await closeBoxes();
    await Hive.close();
  }

  /// Get images sorted by date (newest first)
  static Future<List<ImageModel>> getImagesSortedByDate({
    bool ascending = false,
  }) async {
    final images = await getAllImages();
    images.sort((a, b) {
      return ascending
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt);
    });
    return images;
  }

  /// Get images within a date range
  static Future<List<ImageModel>> getImagesByDateRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final images = await getAllImages();
    return images.where((image) {
      return image.createdAt.isAfter(startDate) &&
          image.createdAt.isBefore(endDate);
    }).toList();
  }

  /// Get total storage size of all images
  static Future<int> getTotalStorageSize() async {
    final images = await getAllImages();
    int total = 0;
    for (var image in images) {
      total += image.fileSize;
    }
    return total;
  }
}