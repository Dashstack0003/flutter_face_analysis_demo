// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'face_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FaceModelAdapter extends TypeAdapter<FaceModel> {
  @override
  final int typeId = 1;

  @override
  FaceModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FaceModel(
      id: fields[0] as String,
      imageId: fields[1] as String,
      bboxX: fields[2] as double,
      bboxY: fields[3] as double,
      bboxWidth: fields[4] as double,
      bboxHeight: fields[5] as double,
      detectionConfidence: fields[6] as double,
      detectedAt: fields[10] as DateTime,
      embedding: (fields[7] as List?)?.cast<double>(),
      clusterId: fields[8] as int,
      croppedFacePath: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, FaceModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.imageId)
      ..writeByte(2)
      ..write(obj.bboxX)
      ..writeByte(3)
      ..write(obj.bboxY)
      ..writeByte(4)
      ..write(obj.bboxWidth)
      ..writeByte(5)
      ..write(obj.bboxHeight)
      ..writeByte(6)
      ..write(obj.detectionConfidence)
      ..writeByte(7)
      ..write(obj.embedding)
      ..writeByte(8)
      ..write(obj.clusterId)
      ..writeByte(9)
      ..write(obj.croppedFacePath)
      ..writeByte(10)
      ..write(obj.detectedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FaceModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
