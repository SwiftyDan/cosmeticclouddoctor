//
//  RegionInfoView.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/6/25.
//

import SwiftUI

struct RegionInfoView: View {
    @StateObject private var regionService = RegionService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Region Information")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(title: "Current Region", value: regionService.getUserRegion())
                InfoRow(title: "Region Name", value: regionService.getRegionDisplayName())
                InfoRow(title: "Is China", value: regionService.isUserInChina() ? "Yes" : "No")
                InfoRow(title: "CallKit Enabled", value: regionService.isCallKitEnabled() ? "Yes" : "No")
            }
            
            if regionService.isUserInChina() {
                VStack(alignment: .leading, spacing: 8) {
                    Text("⚠️ CallKit Disabled")
                        .font(.headline)
                        .foregroundColor(.orange)
                    
                    Text("CallKit functionality is disabled for users in China per Apple's requirements. Calls will still work but without the native CallKit interface.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            Button("Test Region Detection") {
                let result = regionService.testRegionDetection()
                print(result)
            }
            .buttonStyle(.bordered)
            
            Button("Show Detailed Info") {
                let detailedInfo = regionService.getDetailedRegionInfo()
                print("📊 Detailed Region Info:")
                for (key, value) in detailedInfo {
                    print("   \(key): \(value)")
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .font(.system(.body, design: .monospaced))
        }
    }
}

#Preview {
    RegionInfoView()
}
