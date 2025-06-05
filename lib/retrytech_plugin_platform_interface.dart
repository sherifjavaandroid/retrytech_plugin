import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'retrytech_plugin_method_channel.dart';

abstract class RetrytechPluginPlatform extends PlatformInterface {
  /// Constructs a RetrytechPluginPlatform.
  RetrytechPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static RetrytechPluginPlatform _instance = MethodChannelRetrytechPlugin();

  /// The default instance of [RetrytechPluginPlatform] to use.
  ///
  /// Defaults to [MethodChannelRetrytechPlugin].
  static RetrytechPluginPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [RetrytechPluginPlatform] when
  /// they register themselves.
  static set instance(RetrytechPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }


}
