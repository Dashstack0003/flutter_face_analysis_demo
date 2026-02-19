// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cluster_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ClusterModelAdapter extends TypeAdapter<ClusterModel> {
  @override
  final int typeId = 2;

  @override
  ClusterModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ClusterModel(
      clusterId: fields[0] as int,
      faceIds: (fields[2] as List).cast<String>(),
      imageIds: (fields[3] as List).cast<String>(),
      createdAt: fields[6] as DateTime,
      updatedAt: fields[7] as DateTime,
      label: fields[1] as String?,
      representativeFaceId: fields[4] as String?,
      centroidEmbedding: (fields[5] as List?)?.cast<double>(),
    );
  }

  @override
  void write(BinaryWriter writer, ClusterModel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.clusterId)
      ..writeByte(1)
      ..write(obj.label)
      ..writeByte(2)
      ..write(obj.faceIds)
      ..writeByte(3)
      ..write(obj.imageIds)
      ..writeByte(4)
      ..write(obj.representativeFaceId)
      ..writeByte(5)
      ..write(obj.centroidEmbedding)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClusterModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
