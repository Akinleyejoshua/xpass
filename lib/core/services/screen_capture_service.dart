import 'package:flutter/services.dart';

import '../models/assist_models.dart';
import 'platform_channels.dart';
import 'settings_service.dart';

/// One JPEG frame grabbed from the screen, plus how long it took.
class CapturedFrame {
  const CapturedFrame({
    required this.jpeg,
    required this.width,
    required this.height,
    required this.elapsed,
  });

  final Uint8List jpeg;
  final int width;
  final int height;
  final Duration elapsed;

  int get bytes => jpeg.lengthInBytes;

  String get sizeLabel => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// A display the user can target.
class DisplayInfo {
  const DisplayInfo({
    required this.id,
    required this.width,
    required this.height,
    required this.scale,
    required this.isMain,
  });

  final int id;
  final double width;
  final double height;
  final double scale;
  final bool isMain;

  String get label =>
      '${width.toInt()}×${height.toInt()}${isMain ? ' (main)' : ''}';
}

/// Dart-side facade over the ScreenCaptureKit half of
/// `NativeAudioScreenBridge.swift`.
class ScreenCaptureService {
  const ScreenCaptureService();

  // -------------------------------------------------------------- permissions
  Future<bool> hasPermission() async {
    try {
      return await XpChannels.media.invokeMethod<bool>('hasScreenPermission') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Triggers the system prompt. macOS only shows it once per app version, and
  /// the grant does not apply until the app is relaunched.
  Future<bool> requestPermission() async {
    try {
      return await XpChannels.media.invokeMethod<bool>(
            'requestScreenPermission',
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openSystemSettings() async {
    try {
      await XpChannels.media.invokeMethod<bool>('openScreenRecordingSettings');
    } on PlatformException {
      // Nothing useful to do if System Settings refuses to open.
    }
  }

  // ------------------------------------------------------------------ capture
  /// Grabs a frame with the xpass HUD excluded.
  ///
  /// [region], when given, is in global top-left screen coordinates and forces
  /// region mode regardless of [mode].
  Future<CapturedFrame> capture({
    CaptureMode mode = CaptureMode.display,
    int maxWidth = 1600,
    double quality = 0.72,
    Rect? region,
    int? displayId,
  }) async {
    try {
      final Map<Object?, Object?>? result = await XpChannels.media
          .invokeMethod<Map<Object?, Object?>>(
            'captureScreen',
            <String, Object?>{
              'mode': region != null ? 'region' : mode.name,
              'maxWidth': maxWidth,
              'quality': quality,
              'displayId': ?displayId,
              if (region != null) ...<String, Object?>{
                'x': region.left,
                'y': region.top,
                'width': region.width,
                'height': region.height,
              },
            },
          );

      if (result == null) {
        throw const AiServiceException(
          'Screen capture returned nothing.',
          provider: 'ScreenCaptureKit',
        );
      }

      final Uint8List? jpeg = result['jpeg'] as Uint8List?;
      if (jpeg == null || jpeg.isEmpty) {
        throw const AiServiceException(
          'Screen capture produced an empty frame.',
          provider: 'ScreenCaptureKit',
        );
      }

      return CapturedFrame(
        jpeg: jpeg,
        width: (result['width'] as num?)?.toInt() ?? 0,
        height: (result['height'] as num?)?.toInt() ?? 0,
        elapsed: Duration(
          microseconds:
              (((result['elapsedMs'] as num?)?.toDouble() ?? 0) * 1000).round(),
        ),
      );
    } on PlatformException catch (error) {
      throw AiServiceException(
        error.code == 'capture_failed'
            ? '${error.message ?? 'Capture failed'} '
                  '— check Screen Recording permission.'
            : error.message ?? 'Capture failed',
        provider: 'ScreenCaptureKit',
      );
    }
  }

  Future<List<DisplayInfo>> listDisplays() async {
    try {
      final List<Object?>? raw = await XpChannels.media
          .invokeMethod<List<Object?>>('listDisplays');
      if (raw == null) return const <DisplayInfo>[];
      return raw.whereType<Map<Object?, Object?>>().map((
        Map<Object?, Object?> map,
      ) {
        return DisplayInfo(
          id: (map['id'] as num?)?.toInt() ?? 0,
          width: (map['width'] as num?)?.toDouble() ?? 0,
          height: (map['height'] as num?)?.toDouble() ?? 0,
          scale: (map['scale'] as num?)?.toDouble() ?? 1,
          isMain: map['isMain'] as bool? ?? false,
        );
      }).toList();
    } on PlatformException {
      return const <DisplayInfo>[];
    }
  }
}
