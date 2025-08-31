# react-native-voice-vosk

[![npm version](https://badge.fury.io/js/react-native-voice-vosk.svg)](https://badge.fury.io/js/react-native-voice-vosk)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Offline speech recognition for React Native using [Vosk](https://alphacephei.com/vosk/). This library provides real-time speech recognition capabilities without requiring an internet connection.

## Demo

<div align="center">

![Android Demo](https://github.com/deepanshucse/react-native-voice-vosk/blob/main/screenshots/android-demo.png?raw=true)

*Real-time voice recognition on Android - Live speech-to-text conversion*

</div>

## Platform Support

- ✅ **Android**: Fully supported
- ⏳ **iOS**: Coming soon (in progress)

## Features

- 🎤 Real-time speech recognition from microphone
- 📁 Audio file recognition (WAV format)
- 🌐 Offline processing - no internet required
- 🎯 Grammar-based recognition support
- 🔊 Customizable sample rate
- 📱 Lightweight and fast
- 🎛️ Pause/resume functionality
- 📊 Speech start/end detection

## Installation

```bash
npm install react-native-voice-vosk
```

### Android Setup

1. **Download Vosk Model**: Download a Vosk model for your language from [Vosk Models](https://alphacephei.com/vosk/models).

2. **Add Model to Project**: 
   - Extract the model and place it in your project (e.g., `android/app/src/main/assets/model/`)
   - Or store it in device storage and provide the path

3. **Permissions**: Add these permissions to your `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

4. **Request Runtime Permissions**: Don't forget to request microphone permission at runtime.

## Usage

### Basic Example

```javascript
import VoiceVosk, { VoskEventType } from 'react-native-voice-vosk';
import { PermissionsAndroid, Platform } from 'react-native';

// Request microphone permission (Android)
const requestMicrophonePermission = async () => {
  if (Platform.OS === 'android') {
    const granted = await PermissionsAndroid.request(
      PermissionsAndroid.PERMISSIONS.RECORD_AUDIO
    );
    return granted === PermissionsAndroid.RESULTS.GRANTED;
  }
  return true;
};

// Initialize the voice recognition
const initVoiceRecognition = async () => {
  try {
    // Initialize model
    const modelPath = '/path/to/your/vosk-model'; // or assets://model
    await VoiceVosk.initModel({
      modelPath: modelPath,
      sampleRate: 16000, // optional, defaults to 16000
    });
    
    console.log('Model initialized successfully');
  } catch (error) {
    console.error('Failed to initialize model:', error);
  }
};

// Start listening
const startListening = async () => {
  const hasPermission = await requestMicrophonePermission();
  if (!hasPermission) {
    console.log('Microphone permission denied');
    return;
  }
  
  try {
    await VoiceVosk.startListening();
    console.log('Started listening');
  } catch (error) {
    console.error('Failed to start listening:', error);
  }
};

// Stop listening
const stopListening = async () => {
  try {
    await VoiceVosk.stopListening();
    console.log('Stopped listening');
  } catch (error) {
    console.error('Failed to stop listening:', error);
  }
};
```

### Event Listeners

```javascript
import { useEffect } from 'react';

const VoiceRecognitionComponent = () => {
  useEffect(() => {
    // Set up event listeners
    const resultListener = VoiceVosk.addEventListener('onResult', (event) => {
      console.log('Final result:', event.text);
    });

    const partialListener = VoiceVosk.addEventListener('onPartialResult', (event) => {
      console.log('Partial result:', event.partial);
    });

    const speechStartListener = VoiceVosk.addEventListener('onSpeechStart', () => {
      console.log('Speech started');
    });

    const speechEndListener = VoiceVosk.addEventListener('onSpeechEnd', () => {
      console.log('Speech ended');
    });

    const errorListener = VoiceVosk.addEventListener('onError', (event) => {
      console.error('Recognition error:', event.message);
    });

    // Cleanup listeners on unmount
    return () => {
      resultListener.remove();
      partialListener.remove();
      speechStartListener.remove();
      speechEndListener.remove();
      errorListener.remove();
    };
  }, []);

  return (
    // Your component JSX
  );
};
```

### File Recognition

```javascript
const recognizeAudioFile = async (filePath) => {
  try {
    await VoiceVosk.recognizeFile(filePath);
    console.log('File recognition started');
  } catch (error) {
    console.error('File recognition failed:', error);
  }
};
```

### Grammar-based Recognition

```javascript
const initWithGrammar = async () => {
  const grammar = JSON.stringify([
    'yes', 'no', 'maybe', 'start', 'stop', 'pause', 'resume'
  ]);

  await VoiceVosk.initModel({
    modelPath: '/path/to/model',
    grammar: grammar,
  });
};
```

## API Reference

### Methods

#### `initModel(config: VoskConfig): Promise<boolean>`
Initialize the Vosk model.

**Parameters:**
- `config.modelPath`: Path to the Vosk model directory
- `config.sampleRate?`: Audio sample rate (default: 16000)
- `config.grammar?`: JSON string of allowed words/phrases

#### `isModelInitialized(): Promise<boolean>`
Check if the model is initialized.

#### `releaseModel(): Promise<boolean>`
Release the loaded model and free memory.

#### `startListening(): Promise<boolean>`
Start listening to microphone input.

#### `stopListening(): Promise<boolean>`
Stop listening to microphone input.

#### `setPause(paused: boolean): Promise<boolean>`
Pause or resume recognition.

#### `isListening(): Promise<boolean>`
Check if currently listening.

#### `recognizeFile(filePath: string): Promise<boolean>`
Recognize speech from audio file (WAV format).

#### `stopFileRecognition(): Promise<boolean>`
Stop file recognition.

#### `isRecognitionAvailable(): Promise<boolean>`
Check if speech recognition is available on device.

#### `getSampleRate(): Promise<number>`
Get current sample rate.

### Events

#### `onResult`
Fired when speech recognition produces a final result.
```javascript
{ text: string }
```

#### `onPartialResult`
Fired when speech recognition produces a partial result.
```javascript
{ partial: string }
```

#### `onFinalResult`
Fired when file recognition completes.
```javascript
{ text: string }
```

#### `onSpeechStart`
Fired when speech is detected.

#### `onSpeechEnd`
Fired when speech ends.

#### `onError`
Fired when an error occurs.
```javascript
{ message: string }
```

#### `onTimeout`
Fired when recognition times out.

## Supported Audio Formats

- **Live Audio**: 16-bit PCM, mono, 16kHz (configurable)
- **File Audio**: WAV format, 16-bit PCM recommended

## Models

Download language models from [Vosk Models](https://alphacephei.com/vosk/models):

- **Small models** (~50MB): Good for mobile apps, basic vocabulary
- **Large models** (~1GB): Better accuracy, larger vocabulary
- **Server models** (~2GB+): Highest accuracy, best for server use

Popular models:
- `vosk-model-en-us-0.22` - English (US)
- `vosk-model-small-en-us-0.15` - English (US) - Small
- `vosk-model-fr-0.22` - French
- `vosk-model-de-0.21` - German
- `vosk-model-es-0.42` - Spanish

## Performance Tips

1. **Choose appropriate model size**: Smaller models = faster processing + less memory
2. **Use grammar**: Restrict vocabulary for better accuracy and speed
3. **Optimize sample rate**: Lower rates = faster processing (but less accuracy)
4. **Model caching**: Keep models in device storage for faster startup

## Troubleshooting

### Common Issues

#### Model Loading Fails
- Verify model path is correct
- Ensure model is unzipped and contains required files
- Check file permissions

#### No Audio Input
- Verify microphone permissions
- Test device microphone with other apps
- Check audio session configuration

#### Poor Recognition Accuracy
- Use higher quality models
- Ensure clear audio input
- Consider using grammar for specific use cases
- Check sample rate matches model requirements

#### Memory Issues
- Use smaller models for mobile devices
- Call `releaseModel()` when done
- Monitor memory usage in production

## Example App

Check out the example app in the `example/` directory for a complete implementation.

### Running the Example

```bash
# Clone the repository
git clone https://github.com/deepanshucse/react-native-voice-vosk.git
cd react-native-voice-vosk

# Install dependencies
npm install

# Navigate to example
cd example
npm install

# For Android
npx react-native run-android

# For iOS (when available)
npx react-native run-ios
```

The example app demonstrates:
- ✅ Model initialization with different configurations
- ✅ Real-time voice recognition with visual feedback
- ✅ Audio file processing
- ✅ Grammar-based recognition
- ✅ Pause/resume functionality
- ✅ Error handling and user feedback
- ✅ Permission management

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Vosk](https://alphacephei.com/vosk/) - Open source speech recognition toolkit
- [Alpha Cephei](https://alphacephei.com/) - For providing the Vosk speech recognition engine

## Roadmap

- ✅ Android implementation
- ⏳ iOS implementation (in progress)
- 🔮 Voice activity detection improvements
- 🔮 Real-time audio streaming
- 🔮 Custom model training support
- 🔮 Background processing
- 🔮 Multiple language model support
- 🔮 Audio preprocessing options

## Support

If you find this library helpful, please give it a ⭐️ on GitHub!

For issues and questions:
- 🐛 [Report bugs](https://github.com/deepanshucse/react-native-voice-vosk/issues)
- 💡 [Request features](https://github.com/deepanshucse/react-native-voice-vosk/issues)
- 💬 [Join discussions](https://github.com/deepanshucse/react-native-voice-vosk/discussions)