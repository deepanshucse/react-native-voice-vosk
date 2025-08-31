import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface VoskConfig {
  modelPath: string;
  sampleRate?: number;
  grammar?: string;
}

export interface RecognitionResult {
  partial?: string;
  text?: string;
  confidence?: number;
}

export interface Spec extends TurboModule {
  // Model management
  initModel(config: VoskConfig): Promise<boolean>;
  isModelInitialized(): Promise<boolean>;
  releaseModel(): Promise<boolean>;

  // Recognition control
  startListening(): Promise<boolean>;
  stopListening(): Promise<boolean>;
  setPause(paused: boolean): Promise<boolean>;
  isListening(): Promise<boolean>;

  // File recognition
  recognizeFile(filePath: string): Promise<boolean>;
  stopFileRecognition(): Promise<boolean>;

  // Utility methods
  isRecognitionAvailable(): Promise<boolean>;
  getSampleRate(): Promise<number>;

  // Event emitter methods
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('VoiceVosk');
