import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RetrytechPlugin {
  static var shared = RetrytechPlugin();
  final methodChannel = const MethodChannel('retrytech_plugin');
  final cameraChannel = const MethodChannel('retrytech_camera');

  Future<bool?> shareToInstagram(String command) {
    return methodChannel.invokeMethod("shareToInstagram", command);
  }

  Future<bool?> applyFilterAndAudioToVideo({
    required String inputPath,
    required String outputPath,
    bool shouldBothMusics = false,
    String? audioPath,
    List<double> filterValues = const [],
    double? audioStartTimeInMS,
  }) {
    return methodChannel.invokeMethod("applyFilterAndAudioToVideo", {
      'input_path': inputPath,
      'audio_path': audioPath,
      'filter_values': filterValues,
      'output_path': outputPath,
      'should_add_both_musics': shouldBothMusics,
      'audio_start_time_in_ms': audioStartTimeInMS,
    });
  }

  Future<bool?> extractAudio({
    required String inputPath,
    required String outputPath,
  }) {
    return methodChannel.invokeMethod("extractAudio", {
      'input_path': inputPath,
      'output_path': outputPath,
    });
  }

  Future<bool?> addWaterMarkInVideo({
    required String inputPath,
    required String thumbnailPath,
    required String username,
    required String outputPath,
  }) {
    return methodChannel.invokeMethod("addWaterMarkInVideo", {
      'input_path': inputPath,
      'thumbnail_path': thumbnailPath,
      'username': username,
      'output_path': outputPath,
    });
  }

  Future<bool?> applyFilterToImage({
    required String inputPath,
    required List<double> filterValues,
    required String outputPath,
  }) {
    return methodChannel.invokeMethod("applyFilterToImage", {
      'input_path': inputPath,
      'filter_values': filterValues,
      'output_path': outputPath
    });
  }

  Future<bool?> createVideoFromImage({
    required String inputPath,
    required String outputPath,
    String? audioPath,
    List<double> filterValues = const [],
    double? audioStartTimeInMS,
    double videoTotalDurationInSec = 5.0,
  }) {
    return methodChannel.invokeMethod("createVideoFromImage", {
      'input_path': inputPath,
      'audio_path': audioPath,
      'filter_values': filterValues,
      'output_path': outputPath,
      'audio_start_time_in_ms': audioStartTimeInMS,
      'video_total_duration_in_sec': videoTotalDurationInSec,
    });
  }

  Future<bool?> hasAudio({required String inputPath }) {
    return methodChannel.invokeMethod('hasAudio', {'input_path': inputPath});
  }
}

extension RetrytechCameraPlugin on RetrytechPlugin {
  Widget get cameraView {
    return  Platform.isAndroid
        ? AndroidView(
      viewType: 'retrytech_camera_view',
      layoutDirection: TextDirection.ltr,
      creationParams: {},
      creationParamsCodec: StandardMessageCodec(),
    )
        : UiKitView(
      viewType: 'retrytech_camera_view',
      layoutDirection: TextDirection.ltr,
      creationParams: {},
      creationParamsCodec: StandardMessageCodec(),
    );
  }

  Future<void> initCamera() async {
    await cameraChannel.invokeMethod('init');
  }

  Future<void>  get startRecording async {
    await cameraChannel.invokeMethod('start');
  }

  Future<void> get pauseRecording async {
    await cameraChannel.invokeMethod('pause');
  }

  Future<void>  get resumeRecording async {
    await cameraChannel.invokeMethod('resume');
  }

  Future<String?> get stopRecording async {
    return await cameraChannel.invokeMethod('stop');
  }

  Future<bool> get disposeCamera async {
    return await cameraChannel.invokeMethod('dispose');
  }
  Future<void> get toggleCamera async {
    await cameraChannel.invokeMethod('toggle');
  }

  Future<void> get flashOnOff async {
    await cameraChannel.invokeMethod('flash');
  }

  Future<String?>  captureImage() async {
    return await cameraChannel.invokeMethod('capture_image');
  }
}