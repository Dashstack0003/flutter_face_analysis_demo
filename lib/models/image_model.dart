import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';

part 'image_model.g.dart';

@HiveType(typeId: 0)
class ImageModel extends Equatable {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String path;

  @HiveField(2)
  final String name;

  @HiveField(3)
  final DateTime createdAt;

  @HiveField(4)
  final int fileSize;

  @HiveField(5)
  final String? thumbnailPath;

  const ImageModel({
    required this.id,
    required this.path,
    required this.name,
    required this.createdAt,
    required this.fileSize,
    this.thumbnailPath,
  });

  ImageModel copyWith({
    String? id,
    String? path,
    String? name,
    DateTime? createdAt,
    int? fileSize,
    String? thumbnailPath,
  }) {
    return ImageModel(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      fileSize: fileSize ?? this.fileSize,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }

  @override
  List<Object?> get props => [
    id,
    path,
    name,
    createdAt,
    fileSize,
    thumbnailPath,
  ];

  @override
  String toString() {
    return 'ImageModel(id: $id, name: $name, path: $path, createdAt: $createdAt, fileSize: $fileSize)';
  }
}