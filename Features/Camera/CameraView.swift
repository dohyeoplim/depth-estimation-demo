//
//  CameraView.swift
//  depth-estimation-demo
//
//  Created by Dohyeop Lim on 2025-07-17.
//

import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    var session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        let layer = view.videoPreviewLayer
        layer.session = session
        layer.videoGravity = .resizeAspectFill
        if let conn = layer.connection {
            let angle: CGFloat = 90 // Portrait으로 만들어 버림! 다른 곳에서 rotation 필요 X
            if conn.isVideoRotationAngleSupported(angle) {
                conn.videoRotationAngle = angle
            }
        }
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {}
    
    class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            videoPreviewLayer.frame = bounds
        }
    }
}
