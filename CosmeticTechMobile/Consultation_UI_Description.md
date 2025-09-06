# Consultation Details Meeting Screen - Status Card and Approve/Reject UI

## Overview
This document describes the exact UI implementation for the consultation details meeting screen, specifically focusing on the status card that displays consultation status and the approve/reject buttons functionality.

## Status Card (`StatusCardView`)

### Visual Structure
- **Container**: Rounded rectangle with 12px corner radius
- **Background**: System background color with a subtle border
- **Border**: 1px stroke using the status color with 20% opacity
- **Padding**: 14px internal spacing

### Content Layout
The status card uses an HStack with 12px spacing between elements:

#### 1. Left Icon Section
- **Circular Background**: 36x36px circle filled with status color at 15% opacity
- **Icon**: SF Symbol centered in the circle, colored with the status color
- **Icons Used**:
  - ✅ `checkmark.seal.fill` (green) for approved consultations
  - ❌ `xmark.seal.fill` (red) for rejected consultations
  - ⏰ `clock.badge.questionmark` (orange) for waiting approval
  - ⌛ `hourglass` (green/red) for processing states
  - ⚠️ `exclamationmark.triangle.fill` (orange) for errors

#### 2. Text Content Section
- **Layout**: VStack with 4px spacing between elements
- **Title**: Headline font, status message
  - Examples: "Consultation Approved", "Waiting for Approval"
- **Subtitle**: Subheadline font, secondary color, descriptive text
- **Spinner**: Optional ProgressView (0.8 scale) when `showsSpinner` is true

#### 3. Right Section
- **Spacer**: Pushes content to the left side

## Approve/Reject Buttons (`ConsultFormOverlayView`)

### Button Container
- **Layout**: HStack with 12px spacing between buttons
- **Visibility**: Displayed below consultation form fields when `showsButtons` is true

### Accept Button
- **Style**: `.borderedProminent` button style
- **Color**: Green tint
- **Text**: 
  - Normal state: "Accept"
  - Processing state: "Accepting..."
- **Icon**: Optional ProgressView (0.8 scale) when `isAccepting` is true
- **State**: Disabled when either button is processing

### Reject Button
- **Style**: `.bordered` button style
- **Color**: Red tint
- **Text**:
  - Normal state: "Reject"
  - Processing state: "Rejecting..."
- **Icon**: Optional ProgressView (0.8 scale) when `isRejecting` is true
- **State**: Disabled when either button is processing

## Status Card Display Logic

### Priority System
The status cards are conditionally shown based on the following priority:

#### 1. Script Status from API (Highest Priority)
- **Approved**: Green status card with "Consultation Approved"
- **Rejected**: Red status card with "Consultation Rejected"
- **Other Statuses**: Orange status card with "Waiting for Approval"

#### 2. Action State (When No Script Status)
- **Processing States**:
  - `processingApprove`: Shows spinner with "Approving consultation..."
  - `processingReject`: Shows spinner with "Rejecting consultation..."
- **Success States**: No card shown (buttons remain visible)
- **Failure State**: Orange error card with failure message

## Layout and Positioning

### Spacing and Padding
- **Status Cards**: 12px top padding below consultation form
- **Horizontal Padding**: 
  - Status cards: 12px
  - Main content: 16px
- **Bottom Spacing**: 48px clear space to ensure buttons are fully scrollable above safe area

### Visual Hierarchy
1. Consultation form fields
2. Approve/Reject buttons (when applicable)
3. Status cards (conditionally displayed)
4. Bottom spacer for safe area

## State Management

### Button States
- **Enabled**: When consultation is pending approval
- **Disabled**: When either approve or reject action is processing
- **Hidden**: When consultation has already been approved or rejected

### Status Transitions
- **Pending → Processing**: Shows loading state with spinner
- **Processing → Success**: Hides status card, shows success alert
- **Processing → Failure**: Shows error status card with retry option

## Accessibility Features
- **Loading States**: Visual feedback with spinners and disabled buttons
- **Color Coding**: Consistent color scheme for different statuses
- **Clear Messaging**: Descriptive text for each state
- **Touch Targets**: Adequate button sizes for mobile interaction

## Technical Implementation Notes
- **SwiftUI**: Built using SwiftUI with proper state management
- **Reactive Updates**: UI updates based on `ConsultActionState` enum
- **Async Operations**: Handles API calls for status updates
- **Error Handling**: Graceful fallbacks for failed operations
