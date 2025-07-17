//
//  CameraManager.swift
//  depth-estimation-demo
//
//  Created by Dohyeop Lim on 2025-07-17.
//

import Foundation
import AVFoundation
import Vision
import CoreImage
import Combine
import OSLog

let logger = Logger(subsystem: "com.demo.depth-haptic-app", category: "Camera")

final class Camera: NSObject {
    let captureSession = AVCaptureSession()
    private var configured = false
    private var deviceInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "camera.session")
    
    lazy var previewStream: AsyncStream<CVPixelBuffer> = {
        AsyncStream { cont in addToPreview = { cont.yield($0) } }
    }()
    private var addToPreview: ((CVPixelBuffer) -> Void)?
    
    /// 카메라 설정: 장치, 입력, 출력, 회전...
    private func configure() -> Bool {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        // 518px model requirement 충족
        captureSession.sessionPreset = .vga640x480

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            logger.error("카메라 장치 설정 실패")
            return false
        }
        
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_32BGRA] // fix: 프레임 출력 BGRA → Vision 호환
        output.setSampleBufferDelegate(self,
                                       queue: DispatchQueue(label: "video.queue"))
        
        guard captureSession.canAddInput(input),
              captureSession.canAddOutput(output) else {
            logger.error("I/O를 추가할 수 없음")
            return false
        }
        
        captureSession.addInput(input)
        captureSession.addOutput(output)
        
        if let conn = output.connection(with: .video) {
            let angle: CGFloat = 90 // Portrait 고정!
            if conn.isVideoRotationAngleSupported(angle) {
                conn.videoRotationAngle = angle
            }
        }
        
        deviceInput = input
        videoOutput = output
        configured = true
        return true
    }
    
    /// 카메라 접근 권한
    private func checkAuth() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
    
    func start() async {
        guard await checkAuth() else { return }
        if configured {
            if !captureSession.isRunning {
                sessionQueue.async { self.captureSession.startRunning() }
            }
        } else {
            sessionQueue.async {
                if self.configure() {
                    self.captureSession.startRunning()
                }
            }
        }
    }
    
    func stop() {
        guard configured, captureSession.isRunning else { return }
        sessionQueue.async { self.captureSession.stopRunning() }
    }
}

extension Camera: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// 프레임 수신 시: (프레임 → previewStream으로 전달
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from _: AVCaptureConnection) {
        guard let buffer = sampleBuffer.imageBuffer else { return }
        addToPreview?(buffer)
    }
}

// Sendable warning suppress
extension Camera: @unchecked Sendable {}
