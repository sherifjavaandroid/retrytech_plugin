package com.retrytech.retrytech_plugin

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.media.ExifInterface
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.net.Uri
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultMuxer
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import com.retrytech.retrytech_plugin.camera.NativeViewFactory
import com.retrytech.retrytech_plugin.filter.RgbFilter
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer


/** RetrytechPlugin */
open class RetrytechPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel
    private lateinit var cameraChannel: MethodChannel
    var context: Activity? = null
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            "retrytech_plugin"
        )
        channel.setMethodCallHandler(this)

        cameraChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "retrytech_camera")
        cameraChannel.setMethodCallHandler(this)
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "retrytech_camera_view",
            NativeViewFactory(cameraChannel)
        )
    }

    @UnstableApi
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {

            "shareToInstagram" -> {
                shareToInstagram(call.arguments.toString(), result)
            }

            "applyFilterAndAudioToVideo" -> {
                applyFilterAndAudioToVideo(call.arguments as Map<String, String>, result)
            }

            "addWaterMarkInVideo" -> {
                addWatermarkToVideo(call.arguments as Map<String, String>, result)
            }

            "extractAudio" -> {
                extractAudio(call.arguments as Map<String, String>, result)
            }

            "applyFilterToImage" -> {
                applyFilterOnImage(call.arguments as Map<String, String>, result)
            }

            "hasAudio" -> {
                checkAudioTrack(call.arguments as Map<String, String>, result)
            }

            "createVideoFromImage" -> {
                createVideoFromImage(call.arguments as Map<String, String>, result)

            }


            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        context = binding.activity
        binding.addActivityResultListener { requestCode, resultCode, data ->
            Log.e(
                "TAG",
                "onReattachedToActivityForConfigChanges: " + requestCode + "resultCode" + resultCode + "Data" + data
            )

            true
        }
        if (ContextCompat.checkSelfPermission(
                context!!, Manifest.permission.CAMERA
            ) != PackageManager.PERMISSION_GRANTED || ContextCompat.checkSelfPermission(
                context!!, Manifest.permission.READ_EXTERNAL_STORAGE
            ) != PackageManager.PERMISSION_GRANTED || ContextCompat.checkSelfPermission(
                context!!, Manifest.permission.WRITE_EXTERNAL_STORAGE
            ) != PackageManager.PERMISSION_GRANTED || ContextCompat.checkSelfPermission(
                context!!, Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                context!!, arrayOf(
                    Manifest.permission.CAMERA,
                    Manifest.permission.READ_EXTERNAL_STORAGE,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                    Manifest.permission.RECORD_AUDIO
                ), 1000
            )
        }

    }

    override fun onDetachedFromActivityForConfigChanges() {
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    }

    override fun onDetachedFromActivity() {
    }

    @UnstableApi
    fun createVideoFromImage(arguments: Map<String, Any>, onComplete: Result) {
        val inputPath = (arguments["input_path"] ?: "").toString().toUri()
        val audioPath = (arguments["audio_path"] ?: "").toString().toUri()
        val outputPath = (arguments["output_path"] ?: "").toString()
        val filterValues = arguments["filter_values"] as? ArrayList<Float>
        val audioStartTimeInMs = arguments["audio_start_time_in_ms"] as Double?
        val videoTotalDurationInSec = arguments["video_total_duration_in_sec"] as Double?

        Log.d("TAG", "createVideoFromImage: " + arguments)
        val imageMediaItem = MediaItem.fromUri(inputPath)
        val videoItemBuilder = EditedMediaItem.Builder(imageMediaItem)
            .setDurationUs(1000000 * (videoTotalDurationInSec?.toLong() ?: 1))
            .setFrameRate(60)
        if (filterValues != null && filterValues.isNotEmpty()) {
            val videoEffects = mutableListOf<Effect>()
            val rgbFilter = RgbFilter(filterValues.toFloatArray())
            videoEffects.add(rgbFilter)
            videoItemBuilder.setEffects(Effects(listOf(), videoEffects))
        }

        val editedImage = videoItemBuilder.build()


        val clippedAudioMediaItem = MediaItem.Builder()
            .setUri(audioPath)
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(audioStartTimeInMs?.toLong() ?: 0)
                    .setEndPositionMs(
                        (audioStartTimeInMs?.toLong() ?: 0) + ((videoTotalDurationInSec?.toLong()
                            ?: 0) * 1000)
                    )
                    .build()
            )
            .build()
        val audioItem = EditedMediaItem.Builder(clippedAudioMediaItem)
            .build()
//        val audioSequence = EditedMediaItemSequence.Builder(listOf(audioItem))
//            .build()
        val imageSequence = EditedMediaItemSequence.Builder(listOf(editedImage)).build()
        val audioSequence = EditedMediaItemSequence.Builder(listOf(audioItem)).build()

        val composition = Composition.Builder(listOf(imageSequence, audioSequence)).build()

        val transformer = Transformer.Builder(context!!)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setPortraitEncodingEnabled(true)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, result: ExportResult) {
                    onComplete.success(true)
                }

                override fun onError(
                    composition: Composition,
                    result: ExportResult,
                    exception: ExportException
                ) {
                    Log.e("ImageToVideo", "Export error: ${exception.message}", exception)
                    onComplete.success(true)
                }
            })
            .build()

        transformer.start(composition, outputPath)
    }

    fun shareToInstagram(url: String, result: Result) {

        val shareIntent = Intent(Intent.ACTION_SEND)
        shareIntent.type = "text/plain"
        shareIntent.putExtra(Intent.EXTRA_TEXT, url)
        val pm = context!!.packageManager

        pm.queryIntentActivities(shareIntent, 0)
        shareIntent.setPackage("com.instagram.android")
        shareIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT)
        context!!.startActivity(shareIntent)

        try {
            Log.d("TAG", "onMethodCall: Sucess $shareIntent")
            result.success(true)
        } catch (e: Exception) {
            Log.e("TAG", "onMethodCall: Failed $shareIntent $e")
            result.success(false)
        }
    }

    @UnstableApi
    fun addWatermarkToVideo(arguments: Map<String, String>, result: Result) {
        try {
            val inputPath = arguments["input_path"]
            val thumbnailPath = arguments["thumbnail_path"]
            val outputPath = arguments["output_path"]

            if (inputPath.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
                Log.e("addWatermark", "Missing input or output path.")
                result.success(false)
                return
            }

            val inputUri = inputPath.toUri()
            val outputUri = outputPath.toUri()

            val bitmap = thumbnailPath?.takeIf { it.isNotEmpty() }?.let {
                BitmapFactory.decodeFile(it)
            }

            if (bitmap == null) {
                Log.e("addWatermark", "Failed to decode thumbnail bitmap.")
                result.success(false)
                return
            }

            val retriever = MediaMetadataRetriever().apply { setDataSource(inputPath) }
            val videoWidth =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                    ?.toIntOrNull() ?: 0
            val videoHeight =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                    ?.toIntOrNull() ?: 0
            retriever.release()

            if (videoWidth == 0 || videoHeight == 0) {
                Log.e("addWatermark", "Could not retrieve video dimensions.")
                result.success(false)
                return
            }

            Log.d("addWatermark", "Video resolution: ${videoWidth}x${videoHeight}")

            val imageScaleFactor = when {
                videoWidth > 1080 -> .3f
                videoWidth > 480 -> .2f
                else -> 0.5f
            }
            val y = when {
                videoHeight > 1080 -> -.9f
                videoHeight > 480 -> -.85f
                else -> -0.5f
            }

            val imageOverlay = BitmapOverlay.createStaticBitmapOverlay(
                bitmap,
                StaticOverlaySettings.Builder()
                    .setAlphaScale(1f)
                    .setScale(imageScaleFactor, imageScaleFactor)
                    .setBackgroundFrameAnchor(0.75f, y) // Fixed Y anchor
                    .build()
            )

            val effects = Effects(
                emptyList(), // No video effects
                listOf(OverlayEffect(listOf(imageOverlay)))
            )

            val editedItem = EditedMediaItem.Builder(MediaItem.fromUri(inputUri))
                .setEffects(effects)
                .build()

            val composition = Composition.Builder(
                listOf(
                    EditedMediaItemSequence.Builder(listOf(editedItem)).build()
                )
            ).build()

            Transformer.Builder(context!!)
                .setPortraitEncodingEnabled(true)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        Log.d("addWatermark", "Transformation completed")
                        result.success(true)
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException
                    ) {
                        Log.e(
                            "addWatermark",
                            "Transformation failed: ${exportException.message}",
                            exportException
                        )
                        result.success(false)
                    }
                })
                .build()
                .start(composition, outputUri.path!!)

            Log.d("addWatermark", "Transformation started")

        } catch (e: Exception) {
            Log.e("addWatermark", "Unexpected error: ${e.message}", e)
            result.success(false)
        }
    }


    @UnstableApi
    private fun extractAudio(arguments: Map<String, String>, result: Result) {
        val videoUri = arguments["input_path"]?.toUri()
        val outputUri = arguments["output_path"]?.toUri()

        try {
            val extractor = MediaExtractor()
            extractor.setDataSource(videoUri?.path ?: "")

            var audioTrackIndex = -1
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME)
                if (mime?.startsWith("audio/") == true) {
                    audioTrackIndex = i
                    break
                }
            }

            if (audioTrackIndex == -1) {
                result.success(false)
                return
            }

            extractor.selectTrack(audioTrackIndex)

            val muxer =
                MediaMuxer(outputUri?.path ?: "", MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val format = extractor.getTrackFormat(audioTrackIndex)
            val muxerTrackIndex = muxer.addTrack(format)
            muxer.start()

            val bufferSize = 1024 * 1024
            val buffer = ByteBuffer.allocate(bufferSize)
            val bufferInfo = MediaCodec.BufferInfo()

            extractor.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC)

            while (true) {
                bufferInfo.offset = 0
                bufferInfo.size = extractor.readSampleData(buffer, 0)

                if (bufferInfo.size < 0) break

                bufferInfo.presentationTimeUs = extractor.sampleTime
                bufferInfo.flags = extractor.sampleFlags
                muxer.writeSampleData(muxerTrackIndex, buffer, bufferInfo)
                extractor.advance()
            }

            muxer.stop()
            muxer.release()
            extractor.release()

            result.success(true)
        } catch (e: Exception) {
            e.printStackTrace()
            result.success(false)
        }
    }

    private fun applyFilterOnImage(arguments: Map<String, Any>, result: Result) {
        val inputFilePath = arguments["input_path"]?.toString()
        val outputFilePath = arguments["output_path"]?.toString()
        val filterValues = arguments["filter_values"] as? ArrayList<Float>
        val colorMatrix =
            if (!filterValues.isNullOrEmpty()) ColorMatrix(filterValues.toFloatArray()) else null

        if (inputFilePath.isNullOrEmpty() || outputFilePath.isNullOrEmpty()) {
            result.success(false)
            return
        }

        val originalBitmap = BitmapFactory.decodeFile(inputFilePath) ?: run {
            result.success(false)
            return
        }

        // Read EXIF and rotate if needed
        val rotatedBitmap = try {
            val exif = ExifInterface(inputFilePath)
            val orientation = exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )
            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            }
            Bitmap.createBitmap(
                originalBitmap,
                0,
                0,
                originalBitmap.width,
                originalBitmap.height,
                matrix,
                true
            )
        } catch (e: Exception) {
            originalBitmap // fallback
        }

        val paint = Paint().apply {
            colorMatrix?.let {
                colorFilter = ColorMatrixColorFilter(it)
            }
        }

        val outputBitmap =
            Bitmap.createBitmap(rotatedBitmap.width, rotatedBitmap.height, rotatedBitmap.config!!)
        val canvas = Canvas(outputBitmap)
        canvas.drawBitmap(rotatedBitmap, 0f, 0f, paint)

        try {
            val file = File(outputFilePath)
            file.parentFile?.mkdirs()
            val out = FileOutputStream(file)
            outputBitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
            out.flush()
            out.close()
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }


    @UnstableApi
    private fun applyFilterAndAudioToVideo(arguments: Map<String, Any>, result: Result) {
        val videoUri = Uri.fromFile(File(arguments["input_path"].toString()))
//        val videoUri = arguments["input_path"]?.toString()?.toUri()
        val audioUri = arguments["audio_path"]?.toString()?.toUri()
        val outputUri = arguments["output_path"]?.toString()?.toUri()
        val filterValues = arguments["filter_values"] as ArrayList<Float>?
        val shouldAddBothMusics = arguments["should_add_both_musics"] as Boolean
        val audioStartTimeInMs = arguments["audio_start_time_in_ms"] as Double?
        val videoItemBuilder = EditedMediaItem.Builder(MediaItem.fromUri(videoUri!!))
            .setRemoveAudio(!shouldAddBothMusics);
        if (filterValues != null && filterValues.isNotEmpty()) {
            val videoEffects = mutableListOf<Effect>()
            val rgbFilter = RgbFilter(filterValues.toFloatArray())
            videoEffects.add(rgbFilter)
            videoItemBuilder.setEffects(Effects(listOf(), videoEffects))
        }
        val videoItem = videoItemBuilder.build()
        val mediaItemSequences: ArrayList<EditedMediaItemSequence> = ArrayList()
        val videoSequence = EditedMediaItemSequence.Builder(listOf(videoItem))
            .build()
        mediaItemSequences.add(videoSequence)
        if (audioUri != null) {
            val videoDurationUs = getVideoDurationUs(videoUri)
            val clippedAudioMediaItem = MediaItem.Builder()
                .setUri(audioUri)
                .setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(audioStartTimeInMs?.toLong() ?: 0L)
                        .setEndPositionMs((audioStartTimeInMs?.toLong() ?: 0L) + videoDurationUs)
                        .build()
                )
                .build()
            val audioItem = EditedMediaItem.Builder(clippedAudioMediaItem)
                .build()
            val audioSequence = EditedMediaItemSequence.Builder(listOf(audioItem))
                .build()
            mediaItemSequences.add(audioSequence)
        }
        val composition = Composition.Builder(mediaItemSequences).build()
        val transformer = Transformer.Builder(context!!)
            .setMuxerFactory(DefaultMuxer.Factory())
            .setPortraitEncodingEnabled(true)
            .addListener(object : Transformer.Listener {
                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException
                ) {
                    result.success(false)
                    Log.d("TAG", "onMethodCall: " + exportException.message)
                    super.onError(composition, exportResult, exportException)
                }

                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    super.onCompleted(composition, exportResult)
                    result.success(true)
                }
            })
            .build()
        transformer.start(composition, outputUri?.path!!)
    }

    @UnstableApi
    private fun getVideoDurationUs(videoUri: Uri): Long {
        val retriever = MediaMetadataRetriever()
        retriever.setDataSource(context, videoUri)
        val durationMs =
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                ?: 0L
        retriever.release()
        Log.d("Dhruv", "Video duration: $durationMs ms")
        return durationMs
    }

    private fun checkAudioTrack(arguments: Map<String, Any>, result: Result) {
        val videoPath = arguments["input_path"]?.toString()?.toUri()
        val retriever = MediaMetadataRetriever()
        retriever.setDataSource(context, videoPath)
        val hasAudioStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO)
        retriever.release()
        Log.d("HashAudio", "checkAudioTrack: ")
        return result.success("yes" == hasAudioStr)
    }
}
