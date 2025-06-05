import Flutter
import UIKit
import AVKit

public class RetrytechPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "retrytech_plugin", binaryMessenger: registrar.messenger())
        let instance = RetrytechPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        let cameraChannel = FlutterMethodChannel(name: "retrytech_camera", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: cameraChannel)

        let cameraFactory = CameraViewFactory(messenger: registrar.messenger(), channel: cameraChannel)
        registrar.register(cameraFactory, withId: "retrytech_camera_view")
    }


    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            print("Invalid arguments format.")
            result(false)
            return
        }

        switch call.method {
        case "mergeAudioAndVideo":
            handleMergeAudioAndVideo(args: args, result: result)

        case "extractAudio":
            handleExtractAudio(args: args, result: result)

        case "addWaterMarkInVideo":
            handleAddWatermark(args: args, result: result)

        case "applyFilterToImage":
            handleApplyFilterToImage(args: args, result: result)

        case "applyFilterAndAudioToVideo":
            handleApplyFilterAndAudioToVideo(args: args, result: result)

        case "createVideoFromImage":
            handleCreateVideoFromImage(args: args, result: result)

             case "hasAudio":
                        hasAudio(args: args, result: result)

        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func hasAudio(args: [String: Any], result: @escaping FlutterResult) {
            guard let videoInputString = args["input_path"] as? String else {
                print("Missing parameters for merging audio and video.")
                result(false)
                return
            }

           let status = AVEditor.shared.hasAudioTrack(videoURL: URL(fileURLWithPath: videoInputString))
            result(status)
        }

    private func handleMergeAudioAndVideo(args: [String: Any], result: @escaping FlutterResult) {
        guard let videoInputString = args["input_path"] as? String,
              let audioPath = args["audio_path"] as? String,
              let outputPath = args["output_path"] as? String else {
            print("Missing parameters for merging audio and video.")
            result(false)
            return
        }

        AVEditor.shared.mergeAudioVideo(videoInput: URL(fileURLWithPath: videoInputString),
                                        audioInput: URL(fileURLWithPath: audioPath),
                                        outputURL: URL(fileURLWithPath: outputPath)) { status in
            result(status)
        }
    }

    private func handleExtractAudio(args: [String: Any], result: @escaping FlutterResult) {
        guard let videoInputString = args["input_path"] as? String,
              let outputPath = args["output_path"] as? String else {
            print("Missing parameters for extracting audio.")
            result(false)
            return
        }

        AVEditor.shared.extractAudio(videoURL: URL(fileURLWithPath: videoInputString),
                                     outputURL: URL(fileURLWithPath: outputPath)) { status in
            result(status)
        }
    }

    private func handleAddWatermark(args: [String: Any], result: @escaping FlutterResult) {
        guard let videoInputString = args["input_path"] as? String,
              let outputPath = args["output_path"] as? String,
              let thumbnailPath = args["thumbnail_path"] as? String else {
            print("Missing parameters for adding watermark.")
            result(false)
            return
        }

        AVEditor.shared.addWatermark(videoInput: URL(fileURLWithPath: videoInputString),
                                     imagePath: thumbnailPath,
                                     username: "", // Update if needed
                                     outputURL: URL(fileURLWithPath: outputPath)) { status in
            result(status)
        }
    }


    private func handleApplyFilterToImage(args: [String: Any], result: @escaping FlutterResult) {
        guard let inputPath = args["input_path"] as? String,
              let outputPath = args["output_path"] as? String,
              let filterValues = args["filter_values"] as? [Double] else {
            print("Missing parameters for adding watermark.")
            result(false)
            return
        }

        AVEditor.shared.applyFilterToImage(imagePath: inputPath,
                                           outputURL: URL(fileURLWithPath: outputPath),
                                           filterValues: filterValues) { status in
            result(status)
        }
    }

    private func handleApplyFilterAndAudioToVideo(args: [String: Any], result: @escaping FlutterResult) {
        guard let inputPath = args["input_path"] as? String,
              let outputPath = args["output_path"] as? String else {
            print("Missing parameters for adding watermark. \n\(args)")
            result(false)
            return
        }
        let audioPath = args["audio_path"] as? String
        let startAudioTimeInMS = args["audio_start_time_in_ms"] as? Double
        let shouldAddBothMusics = args["should_add_both_musics"] as? Bool
        let filterValues = args["filter_values"] as? [Double]
        AVEditor.shared.applyFilterAndAudioToVideo(inputVideoURL: URL(fileURLWithPath: inputPath),
                                                   inputAudioURL: audioPath == nil ? nil : URL(fileURLWithPath: audioPath!),
                                                   startTime: (startAudioTimeInMS ?? 0) / 1000,
                                                   shouldAddBothMusic: shouldAddBothMusics ?? false,
                                                   outputURL: URL(fileURLWithPath: outputPath),
                                                   filterValues: filterValues ?? []) { status in
            result(status)
        }
    }

    private func handleCreateVideoFromImage(args: [String: Any], result: @escaping FlutterResult) {
        guard let inputPath = args["input_path"] as? String,
              let outputPath = args["output_path"] as? String,
              let videoTotalDurationInSec = args["video_total_duration_in_sec"] as? Double else {
            print("Missing parameters for adding watermark. \n\(args)")
            result(false)
            return
        }
        let audioPath = args["audio_path"] as? String
        let startAudioTimeInMS = args["audio_start_time_in_ms"] as? Double
        let filterValues = args["filter_values"] as? [Double]

        AVEditor.shared.createVideoFromImage(from: URL(fileURLWithPath: inputPath),
                                             withAudio: audioPath == nil ? nil : URL(fileURLWithPath: audioPath!),
                                             outputURL: URL(fileURLWithPath: outputPath),
                                             colorChannelMixer: filterValues ?? [],
                                             audioStartSec: (startAudioTimeInMS ?? 0) / 1000,
                                             videoTotalDurationInSec: videoTotalDurationInSec) { status in
            result(status)
        }
    }
}
