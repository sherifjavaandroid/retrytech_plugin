import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'retrytech_plugin_platform_interface.dart';

/// An implementation of [RetrytechPluginPlatform] that uses method channels.
class MethodChannelRetrytechPlugin extends RetrytechPluginPlatform {
  /// The method channel used to interact with the native platform.

  final methodChannel = const MethodChannel('retrytech_plugin');

// Future<bool?> getPlatformVersion() async {
//   final version = await methodChannel.invokeMethod<bool>('runFFmpegCommand');
//   return version;
// }


}
