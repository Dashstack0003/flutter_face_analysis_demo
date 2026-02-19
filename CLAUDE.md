# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
flutter pub get

# Run all tests
flutter test

# Run a single test file
flutter test test/ml_pipe_test.dart

# Static analysis
flutter analyze

# Regenerate Hive adapters after modifying any model (image_model, face_model, cluster_model)
dart run build_runner build --delete-conflicting-outputs

# Run the app
flutter run
```

> **SDK note:** The project requires Dart `^3.11.0`. If your local SDK is older, update the `environment.sdk` constraint in `pubspec.yaml` to match your installed version (e.g. `'>=3.6.0 <4.0.0'`).

## Architecture

### ML Pipeline (the core of this app)

The app processes photos through a sequential 7-phase pipeline, all on-device:

```
Image picked by user
  → FaceDetectionService   (BlazeFace Full-Range Sparse, 192×192 input, 2304 anchors)
      Outputs: bounding boxes → saved as 112×112 JPEG crops in app documents dir
  → EmbeddingService       (MobileFaceNet 512D, 112×112 input)
      Outputs: L2-normalized 512D embedding per face
  → ClusteringService      (DBSCAN, eps=0.65, minSamples=1)
      Outputs: cluster IDs per face, ClusterModel list
  → HiveHelper             (persists FaceModel + ClusterModel)
```

**Key constraints baked into the pipeline:**
- **Same-image constraint:** Two faces from the same photo always get distance=∞ in DBSCAN so they can never merge into one cluster.
- **Incremental assignment:** New faces first attempt matching against existing cluster centroids (threshold 0.9) before triggering a DBSCAN sub-run for unmatched faces. Full DBSCAN is only triggered manually.
- **Label preservation on re-cluster:** A 3-pass remapping algorithm (face-ID overlap → centroid fallback → fresh ID) prevents user-assigned cluster labels from being lost when DBSCAN runs.

### Model Files (`assets/models/`)

| File | Purpose | Input | Output |
|---|---|---|---|
| `face_detection_full_range_sparse.tflite` | Face detection | `[1,192,192,3]` | `[1,2304,1]` scores + `[1,2304,16]` boxes |
| `mobilefacenet_512d.tflite` | Face embeddings | `[1,112,112,3]` | `[1,512]` |

**Critical:** The full-range detector has `reverse_output_order=true` — output[0] is **scores**, output[1] is **boxes** (opposite of the short-range model).

Pixel normalization: both models use `(pixel - 127.5) / 128.0 → [-1, 1]`.

### TFLiteService constants (`lib/services/tflite_service.dart`)

All model parameters are defined here as static constants:
- `blazeFaceInputSize = 192`
- `mobileFaceNetInputSize = 112`
- `embeddingSize = 512`
- `numAnchors = 2304`

When switching models, update these constants first — `FaceDetectionService` and `EmbeddingService` consume them directly.

### State Management (BLoC)

Two independent BLoCs wired together in `main.dart`:

- **ImageBloc** — manages the image gallery (pick, delete, selection mode). Emits `lastPickedImage` after a successful pick; `HomeScreen` observes this to trigger `ProcessImageRequested` on FaceBloc.
- **FaceBloc** — orchestrates the ML pipeline. Key events: `ProcessImageRequested` (per-image), `RunFullClusteringRequested` (full DBSCAN), `LoadClustersRequested` (People tab).

### Persistence (Hive)

Three typed boxes, all opened lazily by `HiveHelper`:

| Box | Key type | Model | typeId |
|---|---|---|---|
| `images` | `String` (UUID) | `ImageModel` | 0 |
| `faces` | `String` (UUID) | `FaceModel` | 1 |
| `clusters` | `int` (clusterId) | `ClusterModel` | 2 |

After any change to a Hive model class, run `build_runner` to regenerate the `.g.dart` adapter.

### Repository layer

- `ImageRepository` — thin wrapper around `HiveHelper` + `ImagePickerHelper` for image CRUD. Returns `RepositoryResult<T>`.
- `FaceRepository` — orchestrates the full ML pipeline. Returns `FaceRepositoryResult<T>`. The main entry points are `processImage(ImageModel)` and `runFullClustering()`.

### Clustering thresholds (tuning guide)

All defaults are in `ClusteringService` constructor:
- `eps = 0.65` — DBSCAN neighbor distance. Increase if the same person splits into multiple clusters; decrease if different people merge.
- `mergeThreshold = 0.65` — post-DBSCAN centroid merge. Keep ≤ eps.
- `assignmentThreshold = 0.9` — incremental assignment cutoff. Higher = more lenient linking of new photos to existing people.

### Anchor generation for BlazeFace Full-Range

If you ever switch back to the short-range model, change `_generateAnchors()` in `FaceDetectionService`:
- Short-range: strides `[8,16,16,16]`, repeats `[2,6]` → 896 anchors
- Full-range sparse: single stride `4`, feature map `48×48`, 1 anchor/cell → 2304 anchors
