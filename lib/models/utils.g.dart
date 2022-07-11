// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'utils.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SettingsAdapter extends TypeAdapter<Settings> {
  @override
  final int typeId = 0;

  @override
  Settings read(BinaryReader reader) {
    final int numOfFields = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Settings()
      ..runOnStartup = fields[0] == null ? true : fields[0] as bool
      ..autoHideTaskbar = fields[1] == null ? true : fields[1] as bool
      ..taskBarAppsStyle =
          fields[2] == null ? 'activeMonitorFirst' : fields[2] as String
      ..language = fields[6] == null ? 'en' : fields[6] as String
      ..weather = fields[8] == null ? 'normal' : fields[8] as String
      ..weatherCity = fields[9] == null ? 'berlin' : fields[9] as String;
  }

  @override
  void write(BinaryWriter writer, Settings obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.runOnStartup)
      ..writeByte(1)
      ..write(obj.autoHideTaskbar)
      ..writeByte(2)
      ..write(obj.taskBarAppsStyle)
      ..writeByte(6)
      ..write(obj.language)
      ..writeByte(7)
      ..write(obj.maps)
      ..writeByte(8)
      ..write(obj.weather)
      ..writeByte(9)
      ..write(obj.weatherCity);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
