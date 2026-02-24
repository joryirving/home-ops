import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'chat.openclaw.miso',
  appName: 'OpenClaw Chat',
  webDir: 'public',
  server: {
    androidScheme: 'https',
    // Configure for local development
    url: process.env.CAPACITOR_URL || 'http://localhost:3000'
  },
  android: {
    buildToolsVersion: '33.0.0',
    minSdkVersion: 22,
    targetSdkVersion: 33,
    useAndroidX: true,
    allowMixedContent: true
  },
  ios: {
    minVersion: '13.0',
    allowMixedContent: true,
    splashScaled: true
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 3000,
      backgroundColor: '#0d0d14',
      androidScaleType: 'CENTER_CROP'
    }
  }
};

export default config;
