import { DeviceEventEmitter, type EmitterSubscription } from 'react-native';
import NativeVoiceVosk, {
  type RecognitionResult,
  type VoskConfig,
} from './NativeVoiceVosk';

export type { RecognitionResult, VoskConfig };

export type VoskEventType =
  | 'onSpeechStart'
  | 'onSpeechEnd'
  | 'onPartialResult'
  | 'onResult'
  | 'onFinalResult'
  | 'onError'
  | 'onTimeout';

class ReactNativeVoiceVosk {
  constructor() {
    // Simple wrapper around the native module
  }

  /**
   * Initialize the Vosk model with configuration
   */
  async initModel(config: VoskConfig): Promise<boolean> {
    try {
      return await NativeVoiceVosk.initModel(config);
    } catch (error) {
      console.error('Failed to initialize Vosk model:', error);
      return false;
    }
  }

  /**
   * Check if model is initialized
   */
  async isModelInitialized(): Promise<boolean> {
    return NativeVoiceVosk.isModelInitialized();
  }

  /**
   * Release the loaded model
   */
  async releaseModel(): Promise<boolean> {
    return NativeVoiceVosk.releaseModel();
  }

  /**
   * Start listening to microphone
   */
  async startListening(): Promise<boolean> {
    return NativeVoiceVosk.startListening();
  }

  /**
   * Stop listening to microphone
   */
  async stopListening(): Promise<boolean> {
    return NativeVoiceVosk.stopListening();
  }

  /**
   * Pause or resume recognition
   */
  async setPause(paused: boolean): Promise<boolean> {
    return NativeVoiceVosk.setPause(paused);
  }

  /**
   * Check if currently listening
   */
  async isListening(): Promise<boolean> {
    return NativeVoiceVosk.isListening();
  }

  /**
   * Recognize audio from file
   */
  async recognizeFile(filePath: string): Promise<boolean> {
    return NativeVoiceVosk.recognizeFile(filePath);
  }

  /**
   * Stop file recognition
   */
  async stopFileRecognition(): Promise<boolean> {
    return NativeVoiceVosk.stopFileRecognition();
  }

  /**
   * Check if speech recognition is available on device
   */
  async isRecognitionAvailable(): Promise<boolean> {
    return NativeVoiceVosk.isRecognitionAvailable();
  }

  /**
   * Get current sample rate
   */
  async getSampleRate(): Promise<number> {
    return NativeVoiceVosk.getSampleRate();
  }

  /**
   * Create an event listener - returns the subscription for manual cleanup
   *
   * Usage:
   * const subscription = VoiceVosk.addEventListener('onResult', (data) => {
   *   console.log('Result:', data.text);
   * });
   *
   * // Clean up when done
   * subscription.remove();
   */
  static addEventListener(
    eventName: VoskEventType,
    callback: (data: any) => void
  ): EmitterSubscription {
    return DeviceEventEmitter.addListener(eventName, callback);
  }

  /**
   * Remove a specific event listener
   */
  static removeEventListener(subscription: EmitterSubscription): void {
    subscription.remove();
  }

  /**
   * Remove all listeners for a specific event type
   * Use with caution - this removes ALL listeners for the event, including those from other parts of your app
   */
  static removeAllListeners(eventType: VoskEventType): void {
    DeviceEventEmitter.removeAllListeners(eventType);
  }
}

// Export singleton instance
const VoiceVosk = new ReactNativeVoiceVosk();
export default VoiceVosk;

// Also export the class for static methods
export { ReactNativeVoiceVosk };

// Export DeviceEventEmitter for direct access if needed
export { DeviceEventEmitter };
