//
//  WebView.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL
    let onDismiss: () -> Void
    let onLoadingChanged: (Bool) -> Void
    let onLoadingProgress: (Double) -> Void
    let onNavigationChanged: (Bool, Bool) -> Void
    let onWebViewCreated: (WKWebView) -> Void
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        // Add observer for loading progress
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        
        webView.load(URLRequest(url: url))
        
        // Provide reference to the webView
        onWebViewCreated(webView)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Update navigation state
        context.coordinator.updateNavigationState(uiView)
    }
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // Remove observer when view is dismantled
        uiView.removeObserver(coordinator, forKeyPath: #keyPath(WKWebView.estimatedProgress))
        uiView.navigationDelegate = nil
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == #keyPath(WKWebView.estimatedProgress) {
                if let webView = object as? WKWebView {
                    parent.onLoadingProgress(webView.estimatedProgress)
                }
            }
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoadingChanged(true)
            print("🔄 WebView started loading")
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoadingChanged(false)
            updateNavigationState(webView)
            print("✅ WebView loaded successfully")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onLoadingChanged(false)
            print("❌ WebView failed to load: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onLoadingChanged(false)
            print("❌ WebView failed to load (provisional): \(error.localizedDescription)")
        }
        
        func updateNavigationState(_ webView: WKWebView) {
            let canGoBack = webView.canGoBack
            let canGoForward = webView.canGoForward
            parent.onNavigationChanged(canGoBack, canGoForward)
        }
    }
}

struct WebViewModal: View {
    let url: URL
    let onDismiss: () -> Void
    @State private var isLoading = true
    @State private var loadingProgress: Double = 0.0
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var webViewRef: WKWebView?
    
    var body: some View {
        NavigationView {
            ZStack {
                WebView(
                    url: url,
                    onDismiss: onDismiss,
                    onLoadingChanged: { loading in
                        isLoading = loading
                    },
                    onLoadingProgress: { progress in
                        loadingProgress = progress
                    },
                    onNavigationChanged: { back, forward in
                        canGoBack = back
                        canGoForward = forward
                    },
                    onWebViewCreated: { webView in
                        webViewRef = webView
                    }
                )
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("Web Content")
                .navigationBarBackButtonHidden(true)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            HStack(spacing: 16) {
                                Button("Close") {
                                    onDismiss()
                                }
                                .foregroundColor(.blue)
                                
                                if canGoBack {
                                    Button(action: {
                                        webViewRef?.goBack()
                                    }) {
                                        Image(systemName: "chevron.left")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            HStack(spacing: 16) {
                                Button(action: {
                                    webViewRef?.reload()
                                }) {
                                    Image(systemName: "arrow.clockwise")
                                        .foregroundColor(.blue)
                                }
                                
                                if canGoForward {
                                    Button(action: {
                                        webViewRef?.goForward()
                                    }) {
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.blue)
                                    }
                                }
                                
                                Button("Done") {
                                    onDismiss()
                                }
                                .foregroundColor(.blue)
                            }
                        }
                    }
                
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView(value: loadingProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .scaleEffect(1.2)
                            .frame(width: 200)
                        
                        Text("Loading...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        if loadingProgress > 0 {
                            Text("\(Int(loadingProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                }
            }
        }
        .onAppear {
            // Set initial loading state
            isLoading = true
        }
    }
} 