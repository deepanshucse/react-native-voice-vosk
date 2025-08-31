package com.voicevosk

import android.Manifest
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.*
import com.facebook.react.modules.core.DeviceEventManagerModule
import org.vosk.LibVosk
import org.vosk.LogLevel
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import org.vosk.android.SpeechStreamService
import org.vosk.android.StorageService
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.util.concurrent.Executors

class VoiceVoskModule(reactContext: ReactApplicationContext) :
  NativeVoiceVoskSpec(reactContext), RecognitionListener {

  companion object {
    const val NAME = "VoiceVosk"
    private const val TAG = "VoiceVoskModule"
  }

  private val reactContext: ReactApplicationContext = reactContext
  private var model: Model? = null
  private var speechService: SpeechService? = null
  private var speechStreamService: SpeechStreamService? = null
  private var recognizer: Recognizer? = null
  private var isModelInitialized = false
  private var isListening = false
  private var sampleRate = 16000.0f
  private val executor = Executors.newSingleThreadExecutor()

  init {
    LibVosk.setLogLevel(LogLevel.INFO)
  }

  override fun getName(): String = NAME

  @ReactMethod
  override fun initModel(config: ReadableMap, promise: Promise) {
    executor.execute {
      try {
        val modelPath = config.getString("modelPath")
        if (config.hasKey("sampleRate")) {
          sampleRate = config.getDouble("sampleRate").toFloat()
        }


        if (modelPath.isNullOrEmpty()) {
          promise.reject("INVALID_MODEL_PATH", "Model path cannot be null or empty")
          return@execute
        }

        // Clean up existing model first
        model?.close()
        model = null
        recognizer?.close()
        recognizer = null
        isModelInitialized = false

        try {
          // Try to load model directly from file path first
          Log.d(TAG, "Loading model from path: $modelPath")
          model = Model(modelPath)

          // Create recognizer with optional grammar
          recognizer = if (config.hasKey("grammar") && config.getString("grammar") != null) {
            val grammar = config.getString("grammar")!!
            Recognizer(model, sampleRate, grammar)
          } else {
            Recognizer(model, sampleRate)
          }

          isModelInitialized = true
          promise.resolve(true)
          Log.d(TAG, "Vosk model initialized successfully from file")

        } catch (e: IOException) {
          Log.d(TAG, "Model directory does not exist at path: $modelPath")
          Log.d(TAG, "Attempting to unpack from assets...")

          // If direct loading fails, try to unpack from assets
          StorageService.unpack(
            reactContext,
            modelPath,
            "model", // destination folder name
            { unpackedModel ->
              try {
                this.model = unpackedModel

                // Create recognizer with optional grammar
                recognizer = if (config.hasKey("grammar") && config.getString("grammar") != null) {
                  val grammar = config.getString("grammar")!!
                  Recognizer(model, sampleRate, grammar)
                } else {
                  Recognizer(model, sampleRate)
                }

                isModelInitialized = true
                promise.resolve(true)
                Log.d(TAG, "Vosk model initialized successfully from assets")
              } catch (ex: Exception) {
                model = null
                recognizer = null
                isModelInitialized = false
                promise.reject(
                  "RECOGNIZER_INIT_FAILED",
                  "Failed to initialize recognizer: ${ex.message}",
                  ex
                )
              }
            },
            { exception ->
              model = null
              recognizer = null
              isModelInitialized = false
              promise.reject(
                "MODEL_LOAD_FAILED",
                "Failed to load model: ${exception.message}",
                exception
              )
              Log.e(TAG, "Failed to unpack model from assets", exception)
            }
          )
        }

      } catch (e: Exception) {
        model = null
        recognizer = null
        isModelInitialized = false
        promise.reject("INIT_ERROR", "Error initializing model: ${e.message}", e)
        Log.e(TAG, "Failed to initialize Vosk model", e)
      }
    }
  }

  @ReactMethod
  override fun isModelInitialized(promise: Promise) {
    promise.resolve(isModelInitialized)
  }

  @ReactMethod
  override fun releaseModel(promise: Promise) {
    executor.execute {
      try {
        stopListeningInternal()

        recognizer?.let {
          it.close() // Properly close the recognizer
          recognizer = null
        }

        model?.let {
          it.close() // Properly close the model
          model = null
        }

        isModelInitialized = false
        promise.resolve(true)
        Log.d(TAG, "Vosk model released")
      } catch (e: Exception) {
        promise.reject("RELEASE_ERROR", "Error releasing model: ${e.message}", e)
      }
    }
  }


  @ReactMethod
  override fun startListening(promise: Promise) {
    if (!isModelInitialized) {
      promise.reject("MODEL_NOT_INITIALIZED", "Model is not initialized")
      return
    }

    // Check microphone permission
    if (ContextCompat.checkSelfPermission(reactContext, Manifest.permission.RECORD_AUDIO)
      != PackageManager.PERMISSION_GRANTED
    ) {
      promise.reject("PERMISSION_DENIED", "Microphone permission not granted")
      return
    }

    executor.execute {
      try {
        stopListeningInternal()

        val currentRecognizer = recognizer ?: run {
          promise.reject("RECOGNIZER_NULL", "Recognizer is null")
          return@execute
        }

        speechService = SpeechService(currentRecognizer, sampleRate).apply {
          startListening(this@VoiceVoskModule)
        }

        // Reset speech detection state
        speechStartDetected = false
        lastPartialResult = null

        isListening = true
        promise.resolve(true)
        Log.d(TAG, "Started listening")

      } catch (e: IOException) {
        promise.reject(
          "START_LISTENING_ERROR",
          "Error starting speech recognition: ${e.message}",
          e
        )
      } catch (e: Exception) {
        promise.reject(
          "START_LISTENING_ERROR",
          "Unexpected error starting speech recognition: ${e.message}",
          e
        )
      }
    }
  }

  @ReactMethod
  override fun stopListening(promise: Promise) {
    executor.execute {
      try {
        stopListeningInternal()
        promise.resolve(true)
        Log.d(TAG, "Stopped listening")
      } catch (e: Exception) {
        promise.reject("STOP_LISTENING_ERROR", "Error stopping speech recognition: ${e.message}", e)
      }
    }
  }

  @ReactMethod
  override fun setPause(paused: Boolean, promise: Promise) {
    try {
      speechService?.let { service ->
        service.setPause(paused)
        promise.resolve(true)
        Log.d(TAG, "Speech recognition ${if (paused) "paused" else "resumed"}")
      } ?: run {
        promise.reject("SERVICE_NOT_ACTIVE", "Speech service is not active")
      }
    } catch (e: Exception) {
      promise.reject("PAUSE_ERROR", "Error setting pause state: ${e.message}", e)
    }
  }

  @ReactMethod
  override fun isListening(promise: Promise) {
    promise.resolve(isListening)
  }

  @ReactMethod
  override fun recognizeFile(filePath: String, promise: Promise) {
    if (!isModelInitialized) {
      promise.reject("MODEL_NOT_INITIALIZED", "Model is not initialized")
      return
    }

    executor.execute {
      try {
        val file = File(filePath)
        if (!file.exists()) {
          promise.reject("FILE_NOT_FOUND", "Audio file not found: $filePath")
          return@execute
        }

        speechStreamService?.stop()
        speechStreamService = null

        val currentRecognizer = recognizer ?: run {
          promise.reject("RECOGNIZER_NULL", "Recognizer is null")
          return@execute
        }

        val audioStream = FileInputStream(file)

        // Skip WAV header (44 bytes)
        if (audioStream.skip(44) != 44L) {
          audioStream.close()
          promise.reject("INVALID_FILE", "Invalid audio file format")
          return@execute
        }

        speechStreamService = SpeechStreamService(
          currentRecognizer,
          audioStream,
          sampleRate.toInt().toFloat()
        ).apply {
          start(this@VoiceVoskModule)
        }

        promise.resolve(true)
        Log.d(TAG, "Started file recognition: $filePath")

      } catch (e: Exception) {
        promise.reject("FILE_RECOGNITION_ERROR", "Error recognizing file: ${e.message}", e)
      }
    }
  }

  @ReactMethod
  override fun stopFileRecognition(promise: Promise) {
    executor.execute {
      try {
        speechStreamService?.stop()
        speechStreamService = null
        promise.resolve(true)
        Log.d(TAG, "Stopped file recognition")
      } catch (e: Exception) {
        promise.reject("STOP_FILE_ERROR", "Error stopping file recognition: ${e.message}", e)
      }
    }
  }

  @ReactMethod
  override fun isRecognitionAvailable(promise: Promise) {
    // Check if device has microphone
    val hasMicrophone =
      reactContext.packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE)
    promise.resolve(hasMicrophone)
  }

  @ReactMethod
  override fun getSampleRate(promise: Promise) {
    promise.resolve(sampleRate.toDouble())
  }

  @ReactMethod
  override fun addListener(eventName: String) {
    // Required for RCTEventEmitter
  }

  @ReactMethod
  override fun removeListeners(count: Double) {
    // Required for RCTEventEmitter
  }

  // Private helper method
  private fun stopListeningInternal() {
    speechService?.let { service ->
      service.stop()
      service.shutdown()
      speechService = null
    }
    isListening = false

    // Reset speech detection state
    speechStartDetected = false
    lastPartialResult = null
  }

  // RecognitionListener implementation
  override fun onResult(hypothesis: String) {
    Log.d(TAG, "onResult: $hypothesis")
    val params = Arguments.createMap().apply {
      putString("text", hypothesis)
    }
    sendEvent("onResult", params)
  }

  override fun onFinalResult(hypothesis: String) {
    Log.d(TAG, "onFinalResult: $hypothesis")
    val params = Arguments.createMap().apply {
      putString("text", hypothesis)
    }
    sendEvent("onFinalResult", params)

    // Clean up after final result
    speechStreamService = null
  }

  override fun onPartialResult(hypothesis: String) {
    Log.d(TAG, "onPartialResult: $hypothesis")

    // Detect speech start and end
    detectSpeechStart(hypothesis)
    detectSpeechEnd(hypothesis)

    val params = Arguments.createMap().apply {
      putString("partial", hypothesis)
    }
    sendEvent("onPartialResult", params)
  }

  override fun onError(exception: Exception) {
    Log.e(TAG, "onError: ${exception.message}", exception)
    val params = Arguments.createMap().apply {
      putString("message", exception.message ?: "Unknown error")
    }
    sendEvent("onError", params)
  }

  override fun onTimeout() {
    Log.d(TAG, "onTimeout")
    sendEvent("onTimeout", null)
  }

  // Custom speech start/end detection
  private var lastPartialResult: String? = null
  private var speechStartDetected = false

  private fun detectSpeechStart(partialResult: String) {
    if (!speechStartDetected && partialResult.isNotBlank()) {
      speechStartDetected = true
      Log.d(TAG, "Speech start detected")
      sendEvent("onSpeechStart", null)
    }
  }

  private fun detectSpeechEnd(partialResult: String) {
    if (speechStartDetected && partialResult.isBlank() && lastPartialResult?.isNotBlank() == true) {
      speechStartDetected = false
      Log.d(TAG, "Speech end detected")
      sendEvent("onSpeechEnd", null)
    }
    lastPartialResult = partialResult
  }

  private fun sendEvent(eventName: String, params: WritableMap?) {
    if (reactContext.hasActiveReactInstance()) {
      reactContext
        .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
        .emit(eventName, params)
    }
  }


//    override fun onCatalystInstanceDestroy() {
//        super.onCatalystInstanceDestroy()
//        executor.execute {
//            try {
//                stopListeningInternal()
//                speechStreamService?.stop()
//                speechStreamService = null
//                model = null
//                recognizer = null
//                isModelInitialized = false
//            } catch (e: Exception) {
//                Log.e(TAG, "Error during cleanup", e)
//            }
//        }
//        executor.shutdown()
//    }
}
