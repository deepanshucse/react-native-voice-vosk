import { useEffect, useState } from 'react';
import {
  Button,
  DeviceEventEmitter,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import VoiceVosk, { type VoskConfig } from 'react-native-voice-vosk';

const App = () => {
  const [isInitialized, setIsInitialized] = useState(false);
  const [isListening, setIsListening] = useState(false);
  const [recognizedText, setRecognizedText] = useState('');
  const [partialText, setPartialText] = useState('');

  useEffect(() => {
    initializeVosk();
    return () => {
      VoiceVosk.releaseModel();
    };
  }, []);

  useEffect(() => {
    // Set up all event listeners using DeviceEventEmitter directly
    const listeners = [
      DeviceEventEmitter.addListener('onResult', (res) => {
        console.log('Result:', res);
        setRecognizedText(res.text || '');
        setPartialText(''); // Clear partial text when we get final result
      }),

      DeviceEventEmitter.addListener('onPartialResult', (res) => {
        console.log('Partial result:', res);
        setPartialText(res.partial || '');
      }),

      DeviceEventEmitter.addListener('onFinalResult', (res) => {
        console.log('Final result:', res);
        setRecognizedText(res.text || '');
        setPartialText('');
      }),

      DeviceEventEmitter.addListener('onError', (error) => {
        console.error('Recognition error:', error);
        setIsListening(false);
      }),

      DeviceEventEmitter.addListener('onTimeout', () => {
        console.log('Recognition timeout');
        setIsListening(false);
      }),
    ];

    return () => {
      // Clean up all listeners
      listeners.forEach((listener) => listener.remove());
    };
  }, []);

  const initializeVosk = async () => {
    try {
      let success = false;
      const config: VoskConfig = {
        modelPath: 'model-en-us',
        sampleRate: 16000,
      };

      console.log(`Trying model path ${config.modelPath}`);

      success = await VoiceVosk.initModel(config);
      if (success) {
        console.log(`Model loaded successfully from: ${config.modelPath}`);
      }

      setIsInitialized(success);
      console.log('Vosk initialized:', success);
    } catch (error) {
      console.error('Failed to initialize Vosk:', error);
      await VoiceVosk.releaseModel();
    }
  };

  const startListening = async () => {
    if (!isInitialized) {
      console.log('Vosk not initialized');
      return;
    }

    console.log('Starting speech recognition...');

    try {
      const success = await VoiceVosk.startListening();
      if (success) {
        setIsListening(true);
        setRecognizedText('');
        setPartialText('');
      }
      console.log('Start listening result:', success);
    } catch (error) {
      console.error('Failed to start listening:', error);
    }
  };

  const stopListening = async () => {
    try {
      await VoiceVosk.stopListening();
      setIsListening(false);
    } catch (error) {
      console.error('Failed to stop listening:', error);
    }
  };

  const resetText = () => {
    setRecognizedText('');
    setPartialText('');
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Vosk Speech Recognition</Text>

      <View style={styles.statusContainer}>
        <Text style={styles.statusText}>
          Status: {isInitialized ? 'Ready' : 'Initializing...'}
        </Text>
        <Text style={styles.statusText}>
          Listening: {isListening ? 'Yes' : 'No'}
        </Text>
      </View>

      <View style={styles.textContainer}>
        <Text style={styles.label}>Partial Text:</Text>
        <Text style={styles.partialText}>{partialText}</Text>

        <Text style={styles.label}>Recognized Text:</Text>
        <Text style={styles.recognizedText}>{recognizedText}</Text>
      </View>

      <View style={styles.buttonContainer}>
        <Button
          title={isListening ? 'Stop Listening' : 'Start Listening'}
          onPress={isListening ? stopListening : startListening}
          disabled={!isInitialized}
        />

        <View style={styles.buttonSpacer} />

        <Button
          title="Clear Text"
          onPress={resetText}
          disabled={!recognizedText && !partialText}
        />
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 20,
  },
  statusContainer: {
    marginBottom: 20,
  },
  statusText: {
    fontSize: 16,
    marginBottom: 5,
    textAlign: 'center',
  },
  textContainer: {
    width: '100%',
    marginBottom: 30,
    padding: 20,
    backgroundColor: '#f5f5f5',
    borderRadius: 10,
  },
  label: {
    fontSize: 14,
    fontWeight: 'bold',
    marginTop: 10,
    marginBottom: 5,
  },
  partialText: {
    fontSize: 16,
    color: '#666',
    minHeight: 25,
    fontStyle: 'italic',
  },
  recognizedText: {
    fontSize: 18,
    color: '#000',
    minHeight: 30,
    fontWeight: '500',
  },
  buttonContainer: {
    width: '100%',
  },
  buttonSpacer: {
    height: 10,
  },
});

export default App;
