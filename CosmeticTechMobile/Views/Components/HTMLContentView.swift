//
//  HTMLContentView.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/8/25.
//

import SwiftUI
import WebKit

// MARK: - HTML Content View
/// A SwiftUI view that safely renders HTML content with proper styling and accessibility
struct HTMLContentView: View {
    let htmlContent: String
    let title: String
    let height: CGFloat
    
    @State private var isLoading = true
    @State private var loadError: String?
    
    init(htmlContent: String, title: String = "Script Products", height: CGFloat = 200) {
        self.htmlContent = htmlContent
        self.title = title
        self.height = height
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with title and loading state
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            // HTML content container
            if let error = loadError {
                // Error state
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                    
                    Text("Failed to load content")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                )
            } else {
                // HTML content
                HTMLWebView(
                    htmlContent: htmlContent,
                    height: height,
                    onLoadingChanged: { loading in
                        isLoading = loading
                    },
                    onError: { error in
                        loadError = error
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        )
    }
}

// MARK: - HTML Web View
/// A WebKit-based view for rendering HTML content with custom styling
private struct HTMLWebView: UIViewRepresentable {
    let htmlContent: String
    let height: CGFloat
    let onLoadingChanged: (Bool) -> Void
    let onError: (String) -> Void
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.backgroundColor = UIColor.clear
        webView.isOpaque = false
        
        // Load HTML content with custom styling
        let styledHTML = createStyledHTML(from: htmlContent)
        webView.loadHTMLString(styledHTML, baseURL: nil)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Update if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - HTML Styling
    private func createStyledHTML(from content: String) -> String {
        let css = """
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            font-size: 16px;
            line-height: 1.5;
            color: #1d1d1f;
            background-color: transparent;
            margin: 0;
            padding: 16px;
            -webkit-text-size-adjust: 100%;
        }
        
        /* Dark mode support */
        @media (prefers-color-scheme: dark) {
            body {
                color: #f5f5f7;
            }
        }
        
        /* Typography */
        h1, h2, h3, h4, h5, h6 {
            margin: 0 0 12px 0;
            font-weight: 600;
            line-height: 1.3;
        }
        
        h1 { font-size: 24px; }
        h2 { font-size: 20px; }
        h3 { font-size: 18px; }
        h4 { font-size: 16px; }
        h5 { font-size: 14px; }
        h6 { font-size: 12px; }
        
        p {
            margin: 0 0 12px 0;
        }
        
        /* Lists */
        ul, ol {
            margin: 0 0 12px 0;
            padding-left: 20px;
        }
        
        li {
            margin: 0 0 4px 0;
        }
        
        /* Links */
        a {
            color: #007AFF;
            text-decoration: none;
        }
        
        a:hover {
            text-decoration: underline;
        }
        
        /* Tables */
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 0 0 16px 0;
        }
        
        th, td {
            border: 1px solid #d2d2d7;
            padding: 8px 12px;
            text-align: left;
        }
        
        th {
            background-color: #f5f5f7;
            font-weight: 600;
        }
        
        /* Dark mode table borders */
        @media (prefers-color-scheme: dark) {
            th, td {
                border-color: #424245;
            }
            
            th {
                background-color: #1d1d1f;
            }
            
            td {
                background-color: #2c2c2e;
            }
            
            table {
                background-color: #1d1d1f;
            }
        }
        
        /* Code blocks */
        code {
            background-color: #f5f5f7;
            padding: 2px 6px;
            border-radius: 4px;
            font-family: 'SF Mono', Monaco, 'Cascadia Code', monospace;
            font-size: 14px;
        }
        
        pre {
            background-color: #f5f5f7;
            padding: 16px;
            border-radius: 8px;
            overflow-x: auto;
            margin: 0 0 16px 0;
        }
        
        @media (prefers-color-scheme: dark) {
            code, pre {
                background-color: #1d1d1f;
                color: #f5f5f7;
            }
            
            code {
                background-color: #2c2c2e;
                color: #f5f5f7;
            }
        }
        
        /* Blockquotes */
        blockquote {
            border-left: 4px solid #007AFF;
            margin: 0 0 16px 0;
            padding-left: 16px;
            font-style: italic;
            color: #6e6e73;
        }
        
        @media (prefers-color-scheme: dark) {
            blockquote {
                color: #a1a1a6;
                background-color: #2c2c2e;
                padding: 12px 16px;
                border-radius: 8px;
                margin: 16px 0;
            }
        }
        
        /* Responsive images */
        img {
            max-width: 100%;
            height: auto;
            border-radius: 8px;
            border: 1px solid #d2d2d7;
        }
        
        @media (prefers-color-scheme: dark) {
            img {
                border-color: #424245;
                background-color: #1d1d1f;
            }
        }
        
        /* Emphasis */
        strong, b {
            font-weight: 600;
        }
        
        em, i {
            font-style: italic;
        }
        
        /* Small text */
        small {
            font-size: 14px;
            color: #6e6e73;
        }
        
        @media (prefers-color-scheme: dark) {
            small {
                color: #a1a1a6;
            }
        }
        
        /* Horizontal rule */
        hr {
            border: none;
            border-top: 1px solid #d2d2d7;
            margin: 16px 0;
        }
        
        @media (prefers-color-scheme: dark) {
            hr {
                border-color: #424245;
            }
        }
        
        /* Enhanced dark mode support for consultation details */
        @media (prefers-color-scheme: dark) {
            body {
                background-color: #000000;
                color: #f5f5f7;
            }
            
            h1, h2, h3, h4, h5, h6 {
                color: #ffffff;
            }
            
            p {
                color: #f5f5f7;
            }
            
            li {
                color: #f5f5f7;
            }
            
            .consultation-field {
                background-color: #2c2c2e;
                border: 1px solid #424245;
                border-radius: 8px;
                padding: 12px;
                margin: 8px 0;
            }
            
            .consultation-field strong {
                color: #007AFF;
            }
        }
        </style>
        """
        
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
            <meta name="color-scheme" content="light dark">
            \(css)
        </head>
        <body>
            \(content)
        </body>
        </html>
        """
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: HTMLWebView
        
        init(_ parent: HTMLWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoadingChanged(true)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoadingChanged(false)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onLoadingChanged(false)
            parent.onError(error.localizedDescription)
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onLoadingChanged(false)
            parent.onError(error.localizedDescription)
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        HTMLContentView(
            htmlContent: """
            <h3>Treatment Plan</h3>
            <p><strong>Primary Treatment:</strong> Botox injection for forehead lines</p>
            <ul>
                <li>Dosage: 20 units</li>
                <li>Areas: Frontalis muscle</li>
                <li>Expected results: 3-4 months</li>
            </ul>
            <p><em>Note: Patient has no contraindications</em></p>
            """,
            title: "Script Products",
            height: 250
        )
        
        HTMLContentView(
            htmlContent: """
            <h3>Product Details</h3>
            <table>
                <tr><th>Product</th><th>Quantity</th><th>Notes</th></tr>
                <tr><td>Botox</td><td>1 vial</td><td>20 units</td></tr>
                <tr><td>Syringe</td><td>1</td><td>30G needle</td></tr>
            </table>
            """,
            title: "Product List",
            height: 200
        )
        
        HTMLContentView(
            htmlContent: """
            <h2>Dermal Filler Treatment</h2>
            <p><strong>Product:</strong> Juvederm Voluma XC</p>
            <ul>
                <li>Volume: 1.0ml</li>
                <li>Areas: Cheeks, midface</li>
                <li>Technique: Deep dermal injection</li>
                <li>Expected duration: 18-24 months</li>
            </ul>
            <blockquote>Patient desires natural-looking volume restoration</blockquote>
            """,
            title: "Advanced Treatment",
            height: 300
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
