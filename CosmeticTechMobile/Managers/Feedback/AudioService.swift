//
//  AudioService.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/6/25.
//

import Foundation
import AVFoundation
import AudioToolbox

@MainActor
class AudioService: NSObject, ObservableObject {
    static let shared = AudioService()
    
    private var ringtonePlayer: AVAudioPlayer?
    private var connectionPlayer: AVAudioPlayer?
    private var endCallPlayer: AVAudioPlayer?
    private var vibrationTimer: Timer?
    
    @Published var isPlayingRingtone = false
    
    override init() {
        super.init()
        setupAudioSession()
        prepareAudioPlayers()
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use playback to allow sound even with Silent switch, and route to speaker for loudness
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            // Failed to setup audio session - could log to analytics
        }
    }
    
    private func prepareAudioPlayers() {
        // Prepare ringtone player
        if let ringtoneURL = Bundle.main.url(forResource: "ringtone", withExtension: "caf") {
            do {
                ringtonePlayer = try AVAudioPlayer(contentsOf: ringtoneURL)
                ringtonePlayer?.numberOfLoops = -1 // Loop indefinitely
                ringtonePlayer?.volume = 1.0
                ringtonePlayer?.prepareToPlay()
                // Ringtone loaded successfully
            } catch {
                // Failed to load ringtone - could log to analytics
                createDefaultRingtone()
            }
        } else {
            // Ringtone file not found - could log to analytics
            createDefaultRingtone()
        }
        
        // Prepare connection sound player
        if let connectionURL = Bundle.main.url(forResource: "connection", withExtension: "caf") {
            do {
                connectionPlayer = try AVAudioPlayer(contentsOf: connectionURL)
                connectionPlayer?.volume = 1.0
                connectionPlayer?.prepareToPlay()
                // Connection sound loaded successfully
            } catch {
                // Failed to load connection sound - could log to analytics
                createDefaultConnectionSound()
            }
        } else {
            // Connection sound file not found - could log to analytics
            createDefaultConnectionSound()
        }
        
        // Prepare end call sound player
        if let endCallURL = Bundle.main.url(forResource: "endcall", withExtension: "caf") {
            do {
                endCallPlayer = try AVAudioPlayer(contentsOf: endCallURL)
                endCallPlayer?.volume = 1.0
                endCallPlayer?.prepareToPlay()
                // End call sound loaded successfully
            } catch {
                // Failed to load end call sound - could log to analytics
                createDefaultEndCallSound()
            }
        } else {
            // End call sound file not found - could log to analytics
            createDefaultEndCallSound()
        }
    }
    
    private func createDefaultRingtone() {
        // Create a simple ringtone using system sounds
        ringtonePlayer = nil
    }
    
    private func createDefaultConnectionSound() {
        // Create a simple connection sound using system sounds
        connectionPlayer = nil
    }
    
    private func createDefaultEndCallSound() {
        // Create a simple end call sound using system sounds
        endCallPlayer = nil
    }
    
    // MARK: - Public Methods
    
    func playIncomingCallSound() {
        stopAllSounds()
        
        // Ensure session routes to speaker for maximum loudness
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true, options: [])
        } catch {
            // Ignore failures; fallback still plays
        }

        if let player = ringtonePlayer {
            player.currentTime = 0
            player.volume = 1.0
            player.play()
            isPlayingRingtone = true
        } else {
            // Fallback to system sound (this uses the device’s current ringtone style/volume constraints)
            AudioServicesPlaySystemSound(1007)
            isPlayingRingtone = true
        }
        
        // Start vibration
        startVibration()
    }
    
    func stopIncomingCallSound() {
        ringtonePlayer?.stop()
        isPlayingRingtone = false
        stopVibration()

    }
    
    func playCallConnectedSound() {
        stopAllSounds()
        
        if let player = connectionPlayer {
            player.currentTime = 0
            player.volume = 1.0
            player.play()
        } else {
            // Fallback to system sound
            AudioServicesPlaySystemSound(1008) // System connection sound
        }
    }
    
    func playCallEndedSound() {
        stopAllSounds()
        
        if let player = endCallPlayer {
            player.currentTime = 0
            player.volume = 1.0
            player.play()
        } else {
            // Fallback to system sound
            AudioServicesPlaySystemSound(1009) // System end call sound
        }
    }
    
    func stopAllSounds() {
        ringtonePlayer?.stop()
        connectionPlayer?.stop()
        endCallPlayer?.stop()
        isPlayingRingtone = false
        stopVibration()
    }
    
    private func startVibration() {
        // Create a timer for periodic vibration
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard self != nil else { return }
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
    
    private func stopVibration() {
        vibrationTimer?.invalidate()
        vibrationTimer = nil
    }
    
    // MARK: - Audio Session Management
    
    func activateCallAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Configure audio session for voice calls with optimal settings
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
            
            // Set preferred sample rate and I/O buffer duration for voice calls
            try audioSession.setPreferredSampleRate(44100.0)
            try audioSession.setPreferredIOBufferDuration(0.005) // 5ms for low latency
            
            // Activate the audio session
            try audioSession.setActive(true)
            
            print("🎤 Call audio session activated successfully")
            print("   - Category: \(audioSession.category)")
            print("   - Mode: \(audioSession.mode)")
            print("   - Sample Rate: \(audioSession.sampleRate)")
            print("   - I/O Buffer Duration: \(audioSession.ioBufferDuration)")
            
        } catch {
            print("❌ Failed to activate call audio session: \(error)")
        }
    }
    
    func deactivateCallAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Be courteous to other audio and avoid deactivation errors
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            print("🎤 Call audio session deactivated successfully")
        } catch {
            print("❌ Failed to deactivate call audio session: \(error)")
        }
    }
    
    /// Transition from CallKit audio session to Jitsi audio session
    func transitionToJitsiAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // First deactivate the current session
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            
            // Configure for Jitsi meeting with optimal settings
            try audioSession.setCategory(.playAndRecord, mode: .videoChat, options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
            
            // Set preferred sample rate and I/O buffer duration for video calls
            try audioSession.setPreferredSampleRate(48000.0) // Higher sample rate for video calls
            try audioSession.setPreferredIOBufferDuration(0.01) // 10ms for video calls
            
            // Activate the new session
            try audioSession.setActive(true)
            
            print("🎤 Transitioned to Jitsi audio session successfully")
            print("   - Category: \(audioSession.category)")
            print("   - Mode: \(audioSession.mode)")
            print("   - Sample Rate: \(audioSession.sampleRate)")
            print("   - I/O Buffer Duration: \(audioSession.ioBufferDuration)")
            
        } catch {
            print("❌ Failed to transition to Jitsi audio session: \(error)")
            // Fallback to standard call audio session
            activateCallAudioSession()
        }
    }
    
    /// Transition from Jitsi audio session back to normal audio session
    func transitionFromJitsiAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Deactivate the current session
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            
            // Reset to default playback category
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            
            // Activate the new session
            try audioSession.setActive(true)
            
            print("🎤 Transitioned from Jitsi audio session successfully")
            
        } catch {
            print("❌ Failed to transition from Jitsi audio session: \(error)")
        }
    }
    
    // MARK: - Audio Session Status
    
    func logAudioSessionStatus() {
        let audioSession = AVAudioSession.sharedInstance()
        print("🎤 Current Audio Session Status:")
        print("   - Category: \(audioSession.category)")
        print("   - Mode: \(audioSession.mode)")
        print("   - Is Active: \(audioSession.isOtherAudioPlaying)")
        print("   - Sample Rate: \(audioSession.sampleRate)")
        print("   - I/O Buffer Duration: \(audioSession.ioBufferDuration)")
        print("   - Output Volume: \(audioSession.outputVolume)")
        print("   - Input Available: \(audioSession.isInputAvailable)")
    
        
        // Check microphone permission status
        checkMicrophonePermission()
    }
    
    private func checkMicrophonePermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            print("🎤 Microphone permission: GRANTED")
        case .denied:
            print("🎤 Microphone permission: DENIED")
        case .undetermined:
            print("🎤 Microphone permission: UNDETERMINED")
            // Request permission if undetermined
            requestMicrophonePermission()
        @unknown default:
            print("🎤 Microphone permission: UNKNOWN")
        }
    }
    
    private func requestMicrophonePermission() {
        print("🎤 Requesting microphone permission...")
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    print("🎤 Microphone permission granted")
                    // Re-activate audio session with new permission
                    self?.activateCallAudioSession()
                } else {
                    print("🎤 Microphone permission denied")
                }
            }
        }
    }

    deinit {
        DispatchQueue.main.async { [weak self] in
            self?.stopAllSounds()
        }
    }
    
} 
