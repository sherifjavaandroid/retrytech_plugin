package com.retrytech.retrytech_plugin.camera

import android.Manifest.permission.CAMERA
import android.annotation.SuppressLint
import android.app.Activity
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import android.util.Rational
import android.view.LayoutInflater
import android.view.View
import androidx.annotation.RequiresApi
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.FocusMeteringAction.FLAG_AE
import androidx.camera.core.FocusMeteringAction.FLAG_AF
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCapture.OutputFileOptions
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.ViewPort
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.PermissionChecker
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.retrytech.retrytech_plugin.R
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit


internal class CameraXView(
    private val context: Activity?,
    id: Int,
    creationParams: Map<String?, Any?>?,
    private val channel: MethodChannel
) :
    PlatformView, MethodChannel.MethodCallHandler {
    private lateinit var camera: Camera
    private var imageCapture: ImageCapture? = null

    private var videoCapture: VideoCapture<Recorder>? = null
    private var recording: Recording? = null
    private lateinit var cameraExecutor: ExecutorService
    private lateinit var viewFinder: PreviewView

    companion object {
        private const val TAG = "CameraXApp"
        private const val FILENAME_FORMAT = "yyyy-MM-dd-HH-mm-ss-SSS"
        private const val REQUEST_CODE_PERMISSIONS = 10
        private val REQUIRED_PERMISSIONS =
            mutableListOf(
                CAMERA,
                android.Manifest.permission.RECORD_AUDIO
            ).apply {
                if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
                    add(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)
                }
            }.toTypedArray()
    }

    private var view1: View? = null
    override fun getView(): View {
        if (view1 != null) {
            return view1!!
        }
        view1 = LayoutInflater.from(context).inflate(R.layout.item_camera, null, false)
        channel.setMethodCallHandler(this)
        viewFinder = view1!!.findViewById(R.id.viewFinder)

        if (allPermissionsGranted()) {
            startCamera()
        } else {
            ActivityCompat.requestPermissions(
                context!!, REQUIRED_PERMISSIONS, REQUEST_CODE_PERMISSIONS
            )
        }
        return view1!!
    }

    override fun onFlutterViewAttached(flutterView: View) {
        super.onFlutterViewAttached(flutterView)
    }

    override fun onFlutterViewDetached() {
        super.onFlutterViewDetached()
    }

    private fun takePhoto() {}

    @SuppressLint("RestrictedApi")
    private fun captureVideo() {
        val videoCapture = videoCapture ?: return


        // create and start a new recording session
        val name = SimpleDateFormat(FILENAME_FORMAT, Locale.US)
            .format(System.currentTimeMillis())
        val contentValues = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT > Build.VERSION_CODES.P) {
                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/CameraX-Video")
            }
        }

//        val mediaStoreOutputOptions = MediaStoreOutputOptions
//            .Builder(context!!.contentResolver, MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
//            .setContentValues(contentValues)
//            .build()
//        val parceleFileDescriptor =
//            ParcelFileDescriptor.open(getOutputMediaFile(), ParcelFileDescriptor.MODE_WRITE_ONLY)
//        val fileDescriptorOutputOptions =
//            FileDescriptorOutputOptions.Builder(parceleFileDescriptor).build()
        recording = videoCapture.output
            .prepareRecording(context!!, FileOutputOptions.Builder(getOutputMediaFile()).build())
            .apply {
                if (PermissionChecker.checkSelfPermission(
                        context,
                        android.Manifest.permission.RECORD_AUDIO
                    ) ==
                    PermissionChecker.PERMISSION_GRANTED
                ) {
                    withAudioEnabled()
                }
            }
            .start(ContextCompat.getMainExecutor(context)) { recordEvent ->
                when (recordEvent) {
                    is VideoRecordEvent.Start -> {
                    }

                    is VideoRecordEvent.Finalize -> {
                        if (!recordEvent.hasError()) {
                            channel.invokeMethod("url_path", getOutputMediaFile().absolutePath)
                            result?.success(getOutputMediaFile().absolutePath)
                            val msg = "Video capture succeeded: " +
                                    "${recordEvent.outputResults.outputUri}"
                            //                            Toast.makeText(context, msg, Toast.LENGTH_SHORT)
                            //                                .show()
                            Log.d(TAG, msg)
                        } else {
                            recording?.close()
                            recording = null
                            Log.e(
                                TAG, "Video capture ends with error: " +
                                        "${recordEvent.error}"
                            )
                        }

                    }
                }
            }
    }

    private fun getOutputMediaFile(): File {
        val state: String = Environment.getExternalStorageState()
        val filesDir: File? = if (Environment.MEDIA_MOUNTED == state) {
            // We can read and write the media
            context?.getExternalFilesDir(null)
        } else {
            // Load another directory, probably local memory
            context?.filesDir
        }
        val file = File(filesDir, "finalvideo.mp4")
        if (!file.exists()) {
            file.createNewFile()
        }
        return file
    }

    var isFlashOn: Boolean = false
    var isFrontCamera: Boolean = false

    @SuppressLint("ClickableViewAccessibility", "RestrictedApi")
    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context!!)
        viewFinder.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
//      viewFinder.scaleType = PreviewView.ScaleType.FIT_CENTER
        val cameraProvider: ProcessCameraProvider = cameraProviderFuture.get()

        // Preview
        val preview = Preview.Builder()

            .build().also {
                it.setSurfaceProvider(viewFinder.surfaceProvider)
            }


        // Select back camera as a default
        val cameraSelector =
            if (isFrontCamera) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA

        try {
            // Unbind use cases before rebinding+6
            // Bind use cases to camera+6
            val recorder = Recorder.Builder()
                .build()
            videoCapture = VideoCapture.withOutput(recorder)
            imageCapture = ImageCapture.Builder().build()

            val viewPort = ViewPort.Builder(
                Rational(context.window.decorView.width, context.window.decorView.height),
                context.window.decorView.rotation.toInt()
            ).build()
            val useCaseGroup = UseCaseGroup.Builder()
                .addUseCase(preview)
                .addUseCase(videoCapture!!)
                .addUseCase(imageCapture!!)
                .setViewPort(viewPort)
                .build()

            cameraProvider.unbindAll()

            camera = cameraProvider.bindToLifecycle(
                object : LifecycleOwner {
                    override val lifecycle: Lifecycle
                        get() = object : Lifecycle() {
                            override val currentState: State
                                get() = State.STARTED

                            override fun addObserver(observer: LifecycleObserver) {
                            }

                            override fun removeObserver(observer: LifecycleObserver) {
                            }

                        }

                }, cameraSelector, useCaseGroup
            )


            viewFinder.setOnTouchListener { _, motionEvent ->
                val meteringPoint = viewFinder.meteringPointFactory
                    .createPoint(motionEvent!!.x, motionEvent.y)
                val action = FocusMeteringAction.Builder(meteringPoint)
                    .addPoint(meteringPoint, FLAG_AF or FLAG_AE)
                    .setAutoCancelDuration(3, TimeUnit.SECONDS)
                    .build()

                camera.cameraControl.startFocusAndMetering(action)

                true
            }
        } catch (exc: Exception) {
            Log.e(TAG, "Use case binding failed", exc)
        }
    }

    private fun allPermissionsGranted() = REQUIRED_PERMISSIONS.all {
        ContextCompat.checkSelfPermission(
            context!!, it
        ) == PackageManager.PERMISSION_GRANTED
    }

    override fun dispose() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context!!)

        val cameraProvider: ProcessCameraProvider = cameraProviderFuture.get()
        cameraProvider.unbindAll()
    }

    var result: MethodChannel.Result? = null

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == null) return
        this.result = result
        Log.d(TAG, "onMethodCall666: " + call.method)
        if (call.method != null && call.method == "start") {
            captureVideo()
            return
        }

        if (call.method != null && call.method == "pause") {
            val curRecording = recording
            if (curRecording != null) {
                // Stop the current recording session.
                curRecording.pause()
                return
            }
            return
        }

        if (call.method != null && call.method == "resume") {
            val curRecording = recording
            if (curRecording != null) {
                // Stop the current recording session.
                curRecording.resume()
                return
            }
            return
        }

        if (call.method != null && call.method == "stop") {
            val curRecording = recording
            if (curRecording != null) {
                // Stop the current recording session.
                curRecording.stop()

                recording = null
                return
            }
            return
        }

        if (call.method != null && call.method == "toggle") {
            isFrontCamera = !isFrontCamera
            startCamera()
            return
        }

        if (call.method != null && call.method == "flash") {
            isFlashOn = !isFlashOn
            camera.cameraControl.enableTorch(isFlashOn)
            return
        }

        Log.d(TAG, "onMethodCall: " + call.method)
        if (call.method != null && call.method == "capture_image") {
            captureImage(result)
            return
        }
    }

    private fun captureImage(result: MethodChannel.Result) {
        val photoFile = File.createTempFile("image" + System.currentTimeMillis(), ".jpg", context?.cacheDir)

        imageCapture?.takePicture(OutputFileOptions.Builder(photoFile).build(), ContextCompat.getMainExecutor(context!!), object : ImageCapture.OnImageSavedCallback {
            override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                context.runOnUiThread {

                    result?.success(photoFile.absolutePath)
                    Log.d(TAG, "onImageSaved: " + photoFile.absolutePath)
                }
            }

            override fun onError(exception: ImageCaptureException) {
                Log.d(TAG, "onError: " + exception.message)
                this@CameraXView.result?.error(exception.message ?: "", exception.message, exception)
            }
        })
    }


}
