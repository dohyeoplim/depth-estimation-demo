//
//  HomeView.swift
//  depth-estimation-demo
//
//  Created by Dohyeop Lim on 2025-07-17.
//

import SwiftUI

struct HomeView: View {
    @StateObject private var model = VisionProximityModel()
    
    var body: some View {
        ZStack {
            CameraPreview(session: model.camera.captureSession)
                .allowsHitTesting(false)
                .ignoresSafeArea()
            
            uiOverlay
            
            if model.isModelLoading {
                Color.black.opacity(0.8).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("모델 로드 중...")
                        .foregroundColor(.white)
                        .font(.headline)
                }
            }
        }
        .sheet(isPresented: $model.isDebugMode) {
            DebugSheet(model: model)
        }
        .task { await model.camera.start() }
        .onDisappear {
            model.camera.stop()
            model.hapticManager.stopHaptics()
        }
        .statusBar(hidden: true)
    }
    
    private var uiOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    withAnimation { model.isDebugMode.toggle() }
                } label: {
                    Image(systemName: "dot.viewfinder")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(8)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .padding(.top, 20)
                .padding(.trailing, 20)
            }
            Spacer()
            Text(model.feedbackText)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(12)
                .padding(.bottom, 30)
        }
    }
}

struct DebugSheet: View {
    @ObservedObject var model: VisionProximityModel
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Group {
                        if let img = model.depthMapImage {
                            img
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 200)
                                Text("Depth 정보 없음")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    VStack(spacing: 12) {
                        debugValueView(label: "Raw Depth", value: Double(model.depthValue))
                        debugValueView(label: "Danger Level", value: model.dangerLevel)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    Text(model.feedbackText)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(12)
                    
                    Spacer(minLength: 30)
                    
                    VStack(spacing: 8) {
                        Text("Developed by Dohyeop Lim")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Link("GitHub", destination: URL(string: "https://github.com/dohyeoplim/depth-estimation-demo")!)
                            .font(.footnote)
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 10)
                }
                .padding()
            }
            .navigationTitle("Demo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        model.isDebugMode = false
                    }
                }
            }
        }
    }
    
    private func debugValueView(label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            Spacer()
            Text(String(format: "%.2f", value))
                .foregroundColor(.blue)
        }
        .font(.subheadline)
    }
}

#Preview {
    HomeView()
}
