//
//  SharedComponents.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import SwiftUI

// MARK: - Custom Navigation Bar
struct CustomNavigationBarView: View {
    let title: String
    let showLogoutButton: Bool
    let onLogout: (() -> Void)?
    
    init(title: String, showLogoutButton: Bool = false, onLogout: (() -> Void)? = nil) {
        self.title = title
        self.showLogoutButton = showLogoutButton
        self.onLogout = onLogout
    }
    
    var body: some View {
        HStack {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Spacer()
            
            if showLogoutButton, let onLogout = onLogout {
                Button(action: onLogout) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.title2)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconSize: CGFloat
    let refreshAction: (() -> Void)?
    
    init(icon: String, title: String, subtitle: String, iconSize: CGFloat = 80, refreshAction: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.iconSize = iconSize
        self.refreshAction = refreshAction
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundColor(.gray)
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(subtitle)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if let refreshAction = refreshAction {
                Button(action: refreshAction) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .medium))
                        Text("Refresh")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Card View
struct CardView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(20)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Loading View
struct LoadingView: View {
    let message: String
    
    init(_ message: String = "Loading...") {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error View
struct ErrorView: View {
    let title: String
    let message: String
    let retryAction: (() -> Void)?
    
    init(title: String = "Error", message: String, retryAction: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.retryAction = retryAction
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if let retryAction = retryAction {
                Button("Retry") {
                    retryAction()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
} 

// MARK: - Bottom Sheet (Snap) component
struct BottomSheet<Content: View>: View {
    @Binding var isPresented: Bool
    let snapPoints: [CGFloat]
    let initialIndex: Int
    let allowsBackgroundDismiss: Bool
    let showsTipCollapsed: Bool
    let bottomInset: CGFloat
    let tipBottomInset: CGFloat
    let content: Content
    let collapsedHeight: CGFloat
    let showsHeaderControls: Bool

    @GestureState private var dragOffset: CGFloat = 0
    @State private var currentIndex: Int

    init(
        isPresented: Binding<Bool>,
        snapPoints: [CGFloat],
        initialIndex: Int = 0,
        allowsBackgroundDismiss: Bool = false,
        showsTipCollapsed: Bool = false,
        bottomInset: CGFloat = 0,
        tipBottomInset: CGFloat? = nil,
        collapsedHeight: CGFloat = 36,
        showsHeaderControls: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        // Resolve values up front to avoid referencing self before full initialization
        let sortedSnapPoints = snapPoints.sorted()
        let resolvedInitialIndex = min(max(0, initialIndex), sortedSnapPoints.count - 1)
        let resolvedBottomInset = max(0, bottomInset)
        let resolvedTipBottomInset = max(0, tipBottomInset ?? resolvedBottomInset)
        let resolvedCollapsedHeight = max(24, collapsedHeight)

        self._isPresented = isPresented
        self.snapPoints = sortedSnapPoints
        self.initialIndex = resolvedInitialIndex
        self.allowsBackgroundDismiss = allowsBackgroundDismiss
        self.showsTipCollapsed = showsTipCollapsed
        self.bottomInset = resolvedBottomInset
        self.tipBottomInset = resolvedTipBottomInset
        self.content = content()
        self.collapsedHeight = resolvedCollapsedHeight
        self.showsHeaderControls = showsHeaderControls
        self._currentIndex = State(initialValue: resolvedInitialIndex)
    }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let tipHeight: CGFloat = collapsedHeight
            let basePositions = snapPoints.map { max(0, height * (1 - $0) - bottomInset) }
            let tipPosition = max(0, height - tipHeight - tipBottomInset) // Sit flush on reserved bottom space
            let yPositions: [CGFloat] = showsTipCollapsed ? [tipPosition] + basePositions : basePositions
            let isCollapsed = showsTipCollapsed && currentIndex == 0
            let overlayHitTesting: Bool = allowsBackgroundDismiss && !isCollapsed

            ZStack(alignment: .bottom) {
                // Only insert a background tap-target when allowed.
                if overlayHitTesting {
                    Rectangle()
                        .fill(Color.clear)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { isPresented = false }
                }

                // Define drag recognizer once and attach only to the handle to avoid conflicting with inner ScrollViews
                let drag = DragGesture(minimumDistance: 3)
                    .updating($dragOffset) { value, state, _ in
                        // Smooth drag tracking with reduced sensitivity
                        state = value.translation.height * 0.9
                    }
                    .onEnded { value in
                        let predictedEnd = yPositions[currentIndex] + value.predictedEndTranslation.height
                        // Clamp prediction into the bounds we manage so it never falls off-screen
                        let clamped = min(max(predictedEnd, yPositions.last ?? 0), yPositions.first ?? 0)
                        let closestIndex = yPositions.enumerated().min(by: { abs($0.element - clamped) < abs($1.element - clamped) })?.offset ?? currentIndex
                        
                        // Only update if we're actually moving to a different position
                        if closestIndex != currentIndex {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0)) {
                                currentIndex = closestIndex
                            }
                        }
                    }

                VStack(spacing: 0) {
                    // Enhanced handle with better touch area and dark mode visibility
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(Color.primary.opacity(0.3))
                            .frame(width: 40, height: 5)
                        
                        // Invisible touch area for better drag handling
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 20)
                            .contentShape(Rectangle())
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .gesture(drag)
                    .allowsHitTesting(true)
                    .onHover { _ in }

                    // Optional header controls (hidden by default)
                    if showsHeaderControls {
                        HStack(spacing: 8) {
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    currentIndex = 0
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(8)
                                    .background(Color(.systemGray6))
                                    .clipShape(Circle())
                            }
                            .accessibilityLabel("Collapse sheet")
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                    }

                    // Always show content; when collapsed the outer container reduces height
                    VStack(spacing: 0) {
                        content
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemBackground))
                        // Spacer helps ensure inner controls aren't clipped at the bottom edge
                        Color.clear.frame(height: 12)
                    }
                    .clipped()
                }
                // Proper frame constraints to prevent overflow and ensure proper positioning
                .frame(maxWidth: .infinity,
                       maxHeight: isCollapsed ? tipHeight : geo.size.height,
                       alignment: .bottom)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                )
                // Removed border and shadow per design request
                .clipped() // Ensure the entire sheet is clipped to its bounds
                .offset(y: {
                    // Smooth offset calculation with bounds checking
                    let proposed = yPositions[currentIndex] + dragOffset
                    let minY = yPositions.last ?? 0
                    let maxY = yPositions.first ?? 0
                    let clamped = min(max(proposed, minY), maxY)
                    
                    // Add slight resistance at edges to prevent overshooting
                    if proposed < minY {
                        return minY + (proposed - minY) * 0.3
                    } else if proposed > maxY {
                        return maxY + (proposed - maxY) * 0.3
                    }
                    // Snap slightly past the next index to avoid perceived "float"
                    return clamped.rounded()
                }())
                .zIndex(1)
                // Slightly snappier spring to reduce floating feel
                .animation(.spring(response: 0.32, dampingFraction: 0.9, blendDuration: 0), value: currentIndex)
                .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85, blendDuration: 0), value: dragOffset)
            }
        }
        .ignoresSafeArea(edges: .bottom) // Allow BottomSheet to extend to bottom edge
    }
}
