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
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Settings()
      ..runOnStartup = fields[0] == null ? true : fields[0] as bool
      ..autoHideTaskbar = fields[1] == null ? true : fields[1] as bool
      ..taskBarAppsStyle =
          fields[2] == null ? 'activeMonitorFirst' : fields[2] as String
      ..taskbarRenames = fields[3] == null ? '' : fields[3] as String
      ..fullScreenModeBlackWallpaper =
          fields[4] == null ? false : fields[4] as bool
      ..fullScreenModeShowTaskbar =
          fields[5] == null ? false : fields[5] as bool
      ..language = fields[6] == null ? 'en' : fields[6] as String
      ..volumeOSDStyle = fields[7] == null ? 'normal' : fields[7] as String
      ..weather = fields[8] == null ? 'normal' : fields[8] as String
      ..weatherCity = fields[9] == null ? 'berlin' : fields[9] as String;
  }

  @override
  void write(BinaryWriter writer, Settings obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.runOnStartup)
      ..writeByte(1)
      ..write(obj.autoHideTaskbar)
      ..writeByte(2)
      ..write(obj.taskBarAppsStyle)
      ..writeByte(3)
      ..write(obj.taskbarRenames)
      ..writeByte(4)
      ..write(obj.fullScreenModeBlackWallpaper)
      ..writeByte(5)
      ..write(obj.fullScreenModeShowTaskbar)
      ..writeByte(6)
      ..write(obj.language)
      ..writeByte(7)
      ..write(obj.volumeOSDStyle)
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

class ProjectsAdapter extends TypeAdapter<Projects> {
  @override
  final int typeId = 1;

  @override
  Projects read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Projects(
      name: fields[0] as String,
      execution: fields[1] as String,
      icon: fields[2] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Projects obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.execution)
      ..writeByte(2)
      ..write(obj.icon);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RemapKeysAdapter extends TypeAdapter<RemapKeys> {
  @override
  final int typeId = 2;

  @override
  RemapKeys read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RemapKeys(
      from: fields[0] as String,
      to: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, RemapKeys obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.from)
      ..writeByte(1)
      ..write(obj.to);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemapKeysAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HotkeysAdapter extends TypeAdapter<Hotkeys> {
  @override
  final int typeId = 3;

  @override
  Hotkeys read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Hotkeys(
      name: fields[0] as String,
      key: fields[1] as String,
      action: fields[2] as String,
      description: fields[3] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Hotkeys obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.key)
      ..writeByte(2)
      ..write(obj.action)
      ..writeByte(3)
      ..write(obj.description);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HotkeysAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RunSettingsAdapter extends TypeAdapter<RunSettings> {
  @override
  final int typeId = 4;

  @override
  RunSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RunSettings(
      type: fields[0] as String,
      shortcut: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, RunSettings obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.type)
      ..writeByte(1)
      ..write(obj.shortcut);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RunShortcutsAdapter extends TypeAdapter<RunShortcuts> {
  @override
  final int typeId = 5;

  @override
  RunShortcuts read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RunShortcuts(
      key: fields[0] as String,
      shortcut: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, RunShortcuts obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.key)
      ..writeByte(1)
      ..write(obj.shortcut);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunShortcutsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RunApiAdapter extends TypeAdapter<RunApi> {
  @override
  final int typeId = 6;

  @override
  RunApi read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RunApi(
      key: fields[0] as String,
      api: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, RunApi obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.key)
      ..writeByte(1)
      ..write(obj.api);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunApiAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class KeyObjectAdapter extends TypeAdapter<KeyObject> {
  @override
  final int typeId = 7;

  @override
  KeyObject read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return KeyObject()..value = (fields[0] as Map).cast<int, dynamic>();
  }

  @override
  void write(BinaryWriter writer, KeyObject obj) {
    writer
      ..writeByte(1)
      ..writeByte(0)
      ..write(obj.value);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyObjectAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
