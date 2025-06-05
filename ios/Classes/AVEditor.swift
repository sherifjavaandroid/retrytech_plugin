//
//  AVEditor.swift
//
//
//  Created by Aniket Vaddoriya on 15/04/25.
//

import SwiftUI
import AVKit

class AVEditor {
    
    static var shared = AVEditor()
    
    
    func applyFilterToImage(imagePath: String, outputURL: URL, filterValues: [Double], completion: @escaping (_ status: Bool) -> Void) {
        try? FileManager.default.removeItem(at: outputURL)
        guard let image = UIImage(contentsOfFile: imagePath),
              let ciInputImage = CIImage(image: image) else {
            completion(false)
            return
        }

        if filterValues.isEmpty {
            print("There is no filter")
            guard let jpegData = image.jpegData(compressionQuality: 1) else {
                completion(false)
                return
            }
            do {
                try jpegData.write(to: outputURL)
                print("Image saved successfully with correct orientation")
                completion(true)
            } catch {
                print("Error writing image: \(error.localizedDescription)")
                completion(false)
            }
            return
        }

        guard let ciOutputImage = ciInputImage.toFilterCIImage(values: filterValues) else {
            completion(false)
            return
        }

        let context = CIContext()
            guard let cgOutputImage = context.createCGImage(ciOutputImage, from: ciInputImage.extent) else {
                completion(false)
                return
            }

            // Fix orientation
            let finalImage = UIImage(cgImage: cgOutputImage, scale: image.scale, orientation: image.imageOrientation)

            // Redraw image with orientation applied
            UIGraphicsBeginImageContextWithOptions(finalImage.size, false, finalImage.scale)
            finalImage.draw(in: CGRect(origin: .zero, size: finalImage.size))
            let orientedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            guard let jpegData = orientedImage?.jpegData(compressionQuality: 1) else {
                completion(false)
                return
            }


        do {
            try jpegData.write(to: outputURL)
            print("Image saved successfully with correct orientation")
            completion(true)
        } catch {
            print("Error writing image: \(error.localizedDescription)")
            completion(false)
        }
    }


    func extractAudio(videoURL: URL, outputURL: URL, completion: @escaping (_ status: Bool) -> Void ) {

        let asset = AVAsset(url: videoURL)

        let composition = AVMutableComposition()
        // Create an array of audio tracks in the given asset
        // Typically, there is only one
        let audioTracks = asset.tracks(withMediaType: .audio)

        // Iterate through the audio tracks while
        // Adding them to a new AVAsset
        for track in audioTracks {
            let compositionTrack = composition.addMutableTrack(withMediaType: .audio,
                                                               preferredTrackID: kCMPersistentTrackID_Invalid)
            do {
                // Add the current audio track at the beginning of
                // the asset for the duration of the source AVAsset
                try compositionTrack?.insertTimeRange(track.timeRange,
                                                      of: track,
                                                      at: track.timeRange.start)
            } catch {
                print(error)
            }
        }

        guard let exportSession = AVAssetExportSession(asset: composition,
                                                       presetName: AVAssetExportPresetAppleM4A) else {
            // This is just a generic error
            completion(false)

            return
        }

        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputFileType = .m4a
        exportSession.outputURL = outputURL

        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                completion(true)
            case .unknown, .waiting, .exporting, .failed, .cancelled:
                completion(false)
            default:
                break
            }

        }
    }

    func mergeAudioVideo(videoInput: URL, audioInput: URL, outputURL: URL, completion: @escaping (_ output: Bool) -> Void) {
    let mixComposition = AVMutableComposition()
    let videoAsset = AVAsset(url: videoInput)
    let audioAsset = AVAsset(url: audioInput)

    Task {
        do {
            // Load and insert video track
            let videoTracks: [AVAssetTrack]
            if #available(iOS 15.0, *) {
                videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
            } else {
                videoTracks = videoAsset.tracks(withMediaType: .video)
            }

            guard let videoTrack = videoTracks.first else {
                completion(false)
                return
            }

            let videoCompositionTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            try videoCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: videoAsset.duration), of: videoTrack, at: .zero)

            videoCompositionTrack?.preferredTransform = videoTrack.preferredTransform

            // Load and insert audio track
            let newAudioTracks: [AVAssetTrack]
            if #available(iOS 15.0, *) {
                newAudioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
            } else {
                newAudioTracks = audioAsset.tracks(withMediaType: .audio)
            }

            if let newAudioTrack = newAudioTracks.first {
                let newAudioCompositionTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                try newAudioCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: videoAsset.duration), of: newAudioTrack, at: .zero)
            }

            // Export
            try? FileManager.default.removeItem(at: outputURL)
            let exporter = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality)
            exporter?.outputFileType = .mp4
            exporter?.outputURL = outputURL
            exporter?.shouldOptimizeForNetworkUse = true

            exporter?.exportAsynchronously {
                DispatchQueue.main.async {
                    if exporter?.status == .completed {
                        completion(true)
                    } else {
                        print("❌ Export failed: \(exporter?.error?.localizedDescription ?? "Unknown error")")
                        completion(false)
                    }
                }
            }

        } catch {
            print("❌ Error merging: \(error.localizedDescription)")
            completion(false)
        }
    }
}



    func addWatermark(videoInput: URL, imagePath: String,username: String,outputURL: URL, handler:@escaping (_ status: Bool)-> Void) {
        guard let watermark = UIImage(contentsOfFile: imagePath) else {
            print("UIImage issue")
            handler(false)
            return
        }
        let asset = AVAsset(url: videoInput)
        let mixComposition = AVMutableComposition()
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            print("❌ No video track found in asset")
            handler(false)
            return
        }

        let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)

        let minDimension = min(abs(size.width), abs(size.height))
        let imageSize: CGFloat = minDimension * 0.1 // Simpler logic

        let timerange = CMTimeRangeMake(start: CMTime.zero, duration: asset.duration)

        guard let compositionVideoTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            print("❌ Failed to create composition track")
            handler(false)
            return
        }

        do {
            try compositionVideoTrack.insertTimeRange(timerange, of: videoTrack, at: CMTime.zero)
            compositionVideoTrack.preferredTransform = videoTrack.preferredTransform
        } catch {
            print("❌ Failed to insert video track: \(error)")
            handler(false)
            return
        }

        let resizedWatermark = watermark.resizeImage(targetSize: CGSize(width: abs(size.width), height: imageSize))
        guard let watermarkCIImage = CIImage(image: resizedWatermark) else {
            print("❌ Failed to convert watermark to CIImage")
            handler(false)
            return
        }

        let watermarkFilter = CIFilter(name: "CISourceOverCompositing")!

        let videoComposition = AVVideoComposition(asset: asset) { (filteringRequest) in
            let source = filteringRequest.sourceImage.clampedToExtent()
            watermarkFilter.setValue(source, forKey: "inputBackgroundImage")

            let height = filteringRequest.sourceImage.extent.height
            let bottomPadding = height * 0.02 // 3% of video height

            let transform = CGAffineTransform(
                translationX: filteringRequest.sourceImage.extent.width - watermarkCIImage.extent.width - 10,
                y: bottomPadding
            )

            watermarkFilter.setValue(watermarkCIImage.transformed(by: transform), forKey: "inputImage")
            filteringRequest.finish(with: watermarkFilter.outputImage!, context: nil)
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            handler(false)

            return
        }

        try? FileManager.default.removeItem(at: outputURL) // Clean up before exporting

        exportSession.outputURL = outputURL
        exportSession.outputFileType = AVFileType.mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition
        DispatchQueue.main.async {
            exportSession.exportAsynchronously { () -> Void in
                handler(true)
            }
        }
    }
}

extension AVEditor {
    func applyFilterAndAudioToVideo(inputVideoURL: URL, inputAudioURL: URL?, startTime: Double, shouldAddBothMusic: Bool = false, outputURL: URL, filterValues: [Double], completion: @escaping (_ status: Bool) -> Void) {
        try? FileManager.default.removeItem(at: outputURL)

        let mixComposition = AVMutableComposition()

        let videoAsset = AVAsset(url: inputVideoURL)

        Task {
            do {
                // ✅ Load video track asynchronously (iOS 16+)
                let videoTracks: [AVAssetTrack]
if #available(iOS 15.0, *) {
    videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
} else {
    videoTracks = videoAsset.tracks(withMediaType: .video)
}

                guard let videoTrack = videoTracks.first else {
                    completion(false)
                    return
                }


//                mixComposition.naturalSize = CGSize(width: 1920, height: 1080)
                let naturalSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform).standardizedSize
                mixComposition.naturalSize = naturalSize

                let videoCompositionTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                try videoCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: videoAsset.duration), of: videoTrack, at: .zero)


                // Apply Filter
                let composition = AVVideoComposition(asset: mixComposition) { request in
                    let source = request.sourceImage.clampedToExtent()



                    if !filterValues.isEmpty,
                       let filter = filterValues.toCIFilter() {

                        filter.setValue(source, forKey: kCIInputImageKey)

                        if let outputImage = filter.outputImage {
                            request.finish(with: outputImage, context: nil)
                        } else {
                            request.finish(with: NSError(domain: "FilterError", code: 0, userInfo: nil))
                        }
                    } else {
                        // No filter to apply, pass original image
                        request.finish(with: source, context: nil)
                    }
                }

                let mixAudioComposition = AVMutableAudioMix()
                var audioMixParams: [AVMutableAudioMixInputParameters] = []

                // ✅ Handle selectedAudioOption correctly
                if let inputAudioURL {
                    let audioAsset = AVAsset(url: inputAudioURL)
                    try await addAudioTrack(
                        from: audioAsset,
                        to: mixComposition,
                        at: CMTime(seconds: startTime, preferredTimescale: .max),
                        duration: videoAsset.duration,
                        audioMixParams: &audioMixParams
                    )

                    if shouldAddBothMusic {
                        try await addAudioTrack(
                            from: videoAsset,
                            to: mixComposition,
                            at: .zero,
                            duration: videoAsset.duration,
                            audioMixParams: &audioMixParams
                        )
                    }
                } else {
                    try await addAudioTrack(
                        from: videoAsset,
                        to: mixComposition,
                        at: .zero,
                        duration: videoAsset.duration,
                        audioMixParams: &audioMixParams
                    )
                }

                mixAudioComposition.inputParameters = audioMixParams

                // Export video with the filter and audio mix
                let exporter = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality)
                exporter?.outputFileType = .mov
                exporter?.outputURL = outputURL
                exporter?.videoComposition = composition
                exporter?.audioMix = mixAudioComposition
                exporter?.outputURL = outputURL

                exporter?.exportAsynchronously {
                    if exporter?.status == .completed {
                        completion(true)
                    } else {
                        completion(false)
                    }
                }
            } catch {
                print("❌ Error loading tracks: \(error.localizedDescription)")
                completion(false)
            }
        }
    }

    private func addAudioTrack(
        from asset: AVAsset,
        to composition: AVMutableComposition,
        at startTime: CMTime,
        duration: CMTime,
        audioMixParams: inout [AVMutableAudioMixInputParameters]
    ) async throws {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { return }

        let compTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        try compTrack?.insertTimeRange(CMTimeRange(start: startTime, duration: duration), of: track, at: .zero)

        let params = AVMutableAudioMixInputParameters(track: compTrack)
        params.setVolume(1.0, at: .zero)
        audioMixParams.append(params)
    }
}

extension AVEditor {
    func createVideoFromImage(
        from imageURL: URL,
        withAudio audioURL: URL?,
        outputURL: URL,
        colorChannelMixer: [Double],
        audioStartSec: Double,
        videoTotalDurationInSec: Double,
        completion: @escaping (Bool) -> Void
    ) {
        try? FileManager.default.removeItem(at: outputURL)
        let image = UIImage(contentsOfFile: imageURL.path)!
        let size = image.size
        let fps: Int32 = 30
        let durationSeconds: Double = videoTotalDurationInSec
        let totalFrames = Int(durationSeconds * Double(fps))

        // Setup writer
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
            completion(false)
            return
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let ciContext = CIContext()
        var buffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height),
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary

        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, attrs, &buffer)

        guard let pixelBuffer = buffer else {
            completion(false)
            return
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])

        var ciImage = CIImage(image: image)!

        if !colorChannelMixer.isEmpty {
            if let filter = colorChannelMixer.toCIFilter() {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                if let output = filter.outputImage {
                    ciImage = output
                }
            }
        }

        ciContext.render(ciImage, to: pixelBuffer)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let mediaInputQueue = DispatchQueue(label: "mediaInputQueue")

        var frameCount = 0

        input.requestMediaDataWhenReady(on: mediaInputQueue) {
            while input.isReadyForMoreMediaData && frameCount < totalFrames {
                let frameTime = CMTime(value: CMTimeValue(frameCount), timescale: fps)
                adaptor.append(pixelBuffer, withPresentationTime: frameTime)
                frameCount += 1
            }

            if frameCount >= totalFrames {
                input.markAsFinished()
                writer.finishWriting {
                    if let audioURL {
                        self.addAudio(to: outputURL, audioURL: audioURL, audioStartSec: audioStartSec) { success in
                            completion(success)
                        }
                    } else {
                        completion(true)
                    }
                }
            }
        }
    }

    private func addAudio(to videoURL: URL, audioURL: URL,audioStartSec: Double, completion: @escaping (Bool) -> Void) {
        let mixComposition = AVMutableComposition()

        let videoAsset = AVAsset(url: videoURL)
        let audioAsset = AVAsset(url: audioURL)

        guard
            let videoTrack = videoAsset.tracks(withMediaType: .video).first,
            let audioTrack = audioAsset.tracks(withMediaType: .audio).first
        else {
            completion(false)
            return
        }

        let videoCompositionTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let audioCompositionTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!

        do {
            try videoCompositionTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: videoAsset.duration), of: videoTrack, at: .zero)
            try audioCompositionTrack.insertTimeRange(CMTimeRangeMake(start: CMTime(seconds: audioStartSec, preferredTimescale: 600), duration: videoAsset.duration), of: audioTrack, at: .zero)
        } catch {
            completion(false)
            return
        }

        // Export final video with audio
        let finalOutputURL = videoURL.deletingLastPathComponent().appendingPathComponent("final_with_audio.mp4")
        if FileManager.default.fileExists(atPath: finalOutputURL.path) {
            try? FileManager.default.removeItem(at: finalOutputURL)
        }

        let exporter = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality)!
        exporter.outputURL = finalOutputURL
        exporter.outputFileType = .mp4
        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                if exporter.status == .completed {
                    try? FileManager.default.removeItem(at: videoURL) // remove temp video
                    try? FileManager.default.moveItem(at: finalOutputURL, to: videoURL)
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }
    }
}


extension AVEditor {
     func hasAudioTrack(videoURL: URL) -> Bool {
           let asset = AVAsset(url: videoURL)
           let audioTracks = asset.tracks(withMediaType: .audio)
           return !audioTracks.isEmpty
       }
}

extension View {
    func snapshotComplition(color: Color = .white,complition: @escaping (UIImage)->()){
        DispatchQueue.main.async {
            let controller = UIHostingController(rootView: self)
            let view = controller.view

            let targetSize = controller.view.intrinsicContentSize
            view?.bounds = CGRect(origin: .zero, size: targetSize)
            view?.backgroundColor = UIColor(color)

            let renderer = UIGraphicsImageRenderer(size: targetSize)
            DispatchQueue.main.async {
                let image = renderer.image { _ in
                    view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                }
                complition(image)
            }
        }
    }
}


extension UIImage {
    func resizeImage(targetSize: CGSize) -> UIImage {
        let size = self.size

        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height

        // Figure out what our orientation is, and use that to form the rectangle
        var newSize: CGSize
        if(widthRatio > heightRatio) {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
        }

        // This is the rect that we've calculated out and this is what is actually used below
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)

        // Actually do the resizing to the rect using the ImageContext stuff
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        self.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage!
    }
}


extension Array where Element == Double {
    func toCIFilter() -> CIFilter? {
        let values = self
        let filter = CIFilter(name: "CIColorMatrix")

        filter?.setValue(CIVector(x: values[0], y: values[1], z: values[2], w: values[3]), forKey: "inputRVector") // Red
        filter?.setValue(CIVector(x: values[5], y: values[6], z: values[7], w: values[8]), forKey: "inputGVector") // Green
        filter?.setValue(CIVector(x: values[10], y: values[11], z: values[12], w: values[13]), forKey: "inputBVector") // Blue
        filter?.setValue(CIVector(x: values[15], y: values[16], z: values[17], w: values[18]), forKey: "inputAVector") // Alpha

        // Normalize Bias (Offset) from 0-255 to 0-1 range
        filter?.setValue(CIVector(x: values[4] / 255.0, y: values[9] / 255.0, z: values[14] / 255.0, w: values[19]), forKey: "inputBiasVector")

        return filter
    }
}

extension CIImage {
    func toFilterCIImage(values: [Double]) -> CIImage? {
               guard
                   let colorMatrix = CIFilter(name: "CIColorMatrix",
                       parameters: ["inputImage":  self,
                                    "inputRVector": CIVector(x: values[0], y: values[1], z: values[2], w: values[3]),
                                    "inputGVector": CIVector(x: values[5], y: values[6], z: values[7], w: values[8]),
                                    "inputBVector": CIVector(x: values[10], y: values[11], z: values[12], w: values[13]),
                                    "inputAVector": CIVector(x: values[15], y: values[16], z: values[17], w: values[18])])
               else { return nil }
               return colorMatrix.outputImage

    }
}
extension CGSize {
    var standardizedSize: CGSize {
        CGSize(width: abs(width), height: abs(height))
    }
}
