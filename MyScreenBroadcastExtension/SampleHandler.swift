//
//  SampleHandler.swift
//  MyScreenBroadcastExtension
//

import ReplayKit
import AVFoundation
import Accelerate
import UIKit

// Make sure this matches your App Group
private let appGroupID = "group.com.techpal.mobile.ChatGPTScreenRecorder"

// We store frames in "BroadcastFrames"
private let framesFolder = "BroadcastFrames"

class SampleHandler: RPBroadcastSampleHandler {

    private var frameCount = 0
    // Example: only 1 frame per second so we don’t flood the container
    private let maxFrameRate: Double = 1.0

    private var lastFrameTimestamp: CFTimeInterval = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        print("Broadcast started in extension!")
        clearExistingFrames()
    }
    
    override func broadcastPaused() {
        print("Broadcast paused.")
    }
    
    override func broadcastResumed() {
        print("Broadcast resumed.")
    }
    
    override func broadcastFinished() {
        print("Broadcast finished. Wrote done marker.")
        writeDoneMarker()
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        // We only care about video
        guard sampleBufferType == .video else { return }

        let currentTimestamp = CACurrentMediaTime()
        if (currentTimestamp - lastFrameTimestamp) < (1.0 / maxFrameRate) {
            // Throttle frames if we exceed maxFrameRate
            return
        }
        lastFrameTimestamp = currentTimestamp
        
        guard let image = uiImageFromSampleBuffer(sampleBuffer) else {
            return
        }
        
        saveFrame(image)
    }
    
    // MARK: - Convert CMSampleBuffer to UIImage
    private func uiImageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return nil
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - Save PNG to shared container
    private func saveFrame(_ image: UIImage) {
        guard let pngData = image.pngData() else { return }
        
        frameCount += 1
        let filename = "frame\(frameCount).png"
        
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            print("Could not get containerURL for app group!")
            return
        }
        
        let framesPath = containerURL.appendingPathComponent(framesFolder, isDirectory: true)
        
        do {
            // Make the folder if it’s missing
            try FileManager.default.createDirectory(at: framesPath,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
            let fileURL = framesPath.appendingPathComponent(filename)
            try pngData.write(to: fileURL)
            // Logging
            print("Wrote frame to \(fileURL.path)")
        } catch {
            print("Error writing frame: \(error)")
        }
    }
    
    private func clearExistingFrames() {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return }
        
        let framesPath = containerURL.appendingPathComponent(framesFolder, isDirectory: true)
        try? FileManager.default.removeItem(at: framesPath)
        print("Cleared old frames.")
    }
    
    private func writeDoneMarker() {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return }
        
        let doneURL = containerURL.appendingPathComponent("BroadcastDone.txt")
        let text = "DONE:\(frameCount)"
        try? text.write(to: doneURL, atomically: true, encoding: .utf8)
    }
}
