//
//  VisionProximityModel.swift
//  depth-estimation-demo
//
//  Created by Dohyeop Lim on 2025-07-17.
//

import Foundation
import SwiftUI
import CoreImage
import Vision
import Combine
import AVFoundation
import CoreVideo

// CVPixelBuffer를 Sendable로 하여 warning suppress (임시)
extension CVPixelBuffer: @unchecked @retroactive Sendable {}

/// 카메라 프레임을 최신 상태로 유지하도록 함. take()로 CVPixelBuffer 리턴
actor FrameHolder {
    private var buffer: CVPixelBuffer?
    func set(_ buf: CVPixelBuffer) { buffer = buf }
    func take() -> CVPixelBuffer? {
        let b = buffer
        buffer = nil
        return b
    }
}

final class VisionProximityModel: ObservableObject {
    let camera = Camera()
    let hapticManager = HapticManager()
    private let context = CIContext()
    private var visionModel: VNCoreMLModel?
    
    // async & Combine
    private var cancellables = Set<AnyCancellable>()
    private let frameHolder = FrameHolder()
    private var lastInference: CFTimeInterval = 0
    private let depthSubject = PassthroughSubject<CIImage, Never>()
    
    // UI 관련
    @Published var isModelLoading: Bool = true
    @Published var dangerLevel: Double = 0
    @Published var depthValue: Float = 0
    @Published var feedbackText: String = "카메라를 정면으로 향해주세요"
    @Published var isDebugMode: Bool = false
    @Published var depthMapImage: Image?
    
    // Threshold, depth가 작을수록 벽이 가까움
    // MARK: Threshold 튜닝
    private let nearThreshold: Float = 0.6
    private let farThreshold: Float = 0.3
    
    init() {
        Task {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let ml = try await DepthAnything_Small.load(configuration: config)
            visionModel = try VNCoreMLModel(for: ml.model)
            await MainActor.run {
                isModelLoading = false
                feedbackText = "모델 로드 완료"
            }
        }
        Task.detached { await self.pullFrames() } // 카메라 프레임 시작
        Task.detached { await self.processLoop() } // infer loop 시작
        
        depthSubject
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .compactMap { [weak self] ciImg -> Image? in
                guard let self = self, self.isDebugMode else { return nil }
                // fix: portraig 방향으로만 나오도록 CIImage 그대로 사용함
                guard let cg = self.context.createCGImage(ciImg, from: ciImg.extent) else { return nil }
                return Image(decorative: cg, scale: 1)
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \.depthMapImage, on: self)
            .store(in: &cancellables)
    }
    
    /// 카메라에서 들어오는 픽셀 버퍼를 frameHolder actor에 저장
    private func pullFrames() async {
        for await buf in camera.previewStream {
            await frameHolder.set(buf)
        }
    }
    
    /// 일정 주기로 최신 프레임만 가져와 infer
    private func processLoop() async {
        while true {
            guard let frame = await frameHolder.take() else {
                try? await Task.sleep(nanoseconds: 10_000_000) // 0.01초 delay
                continue
            }
            let now = CACurrentMediaTime()
            guard now - lastInference >= 0.1 else { continue }  // 약 10FPS, 성능이슈
            lastInference = now
            await infer(on: frame)
        }
    }
    
    /// infer()
    private func infer(on buffer: CVPixelBuffer) async {
        guard let model = visionModel else { return }
        let req = VNCoreMLRequest(model: model)
        req.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer)
        do {
            try handler.perform([req])
            guard let obs = req.results?.first as? VNPixelBufferObservation else { return }
            let depthBuf = obs.pixelBuffer
            depthSubject.send(CIImage(cvPixelBuffer: depthBuf))

            guard let centralDepth = getCentralDepth(from: depthBuf) else { return }
            let level = computeLevel(from: centralDepth)

            await MainActor.run {
                self.depthValue = centralDepth
                self.dangerLevel = level
                self.updateFeedback(level)
                self.hapticManager.updateHaptic(dangerLevel: level)
            }
        } catch { }
    }
    
    /// depth에서 level 계산
    private func computeLevel(from depth: Float) -> Double {
        let range = nearThreshold - farThreshold
        guard range > 0 else { return depth > nearThreshold ? 1.0 : 0.0 }
        let level = (depth - farThreshold) / range
        return max(0.0, min(1.0, Double(level)))
    }
    
    /// 화면 중앙에서 특정 region에 대해 평균 depth 계산, Half Float formatted
    private func getCentralDepth(from buf: CVPixelBuffer) -> Float? {
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        
        guard let ptr = CVPixelBufferGetBaseAddress(buf) else { return nil }
        let w = CVPixelBufferGetWidth(buf)
        let h = CVPixelBufferGetHeight(buf)
        let rowBytes = CVPixelBufferGetBytesPerRow(buf)
        let format = CVPixelBufferGetPixelFormatType(buf)
        
        let cx = w / 2
        let cy = h / 2
        let region = 80
        let sy = max(0, cy - region/2)
        let ey = min(h, sy + region)
        let sx = max(0, cx - region/2)
        let ex = min(w, sx + region)
        
        var sum: Float = 0
        var count = 0
        
        guard format == kCVPixelFormatType_OneComponent16Half else { return nil }
        
        let stride = rowBytes / MemoryLayout<UInt16>.size
        let ptr16 = ptr.assumingMemoryBound(to: UInt16.self)
        for y in sy..<ey {
            let row = ptr16 + y * stride
            for x in sx..<ex {
                sum += Float(Float16(bitPattern: row[x]))
                count += 1
            }
        }
        return count > 0 ? sum / Float(count) : nil
    }
    
    @MainActor
    private func updateFeedback(_ level: Double) {
        if level > 0.8 {
            feedbackText = "벽이 매우 가깝습니다"
        } else if level > 0.5 {
            feedbackText = "벽이 앞에 있습니다"
        } else if level > 0.2 {
            feedbackText = "벽까지 여유가 있습니다"
        } else {
            feedbackText = "안전합니다"
        }
    }
}
