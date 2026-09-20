# Platform-specific review guidance

## Web

Collect desktop and relevant responsive states. Check pointer, keyboard, focus, hover, form submission, navigation, loading/error states, scroll containment, and responsive breakpoints that changed. If the user asked for browser behavior, use a real browser for acceptance rather than treating a static screenshot as sufficient.

## Desktop apps

Review window sizing, sidebar/toolbar density, menus, keyboard shortcuts, focus order, resize behavior, modal/sheet behavior, and native window states that are part of the requested flow. For Electron, Tauri, or native desktop clients, verify the actual app runtime when available.

## iOS / iPadOS

Respect the app's existing SwiftUI/UIKit language and the product design brief. Review Dynamic Type risk, safe areas, sheets, navigation stacks, keyboard avoidance, scrolling, tap targets, disabled states, and device-size changes relevant to the changed screen. Device or simulator interaction is the acceptance source when available.

## Android

Respect the existing Compose/View design system and project conventions. Review back navigation, keyboard/insets, scroll behavior, state restoration where relevant, touch targets, disabled states, and affected device sizes. Emulator or physical-device interaction is the acceptance source when available.

## Shared mobile rule

A static mobile mock is excellent for discussing layout and hierarchy, but it does not establish that typing, scrolling, gestures, navigation, or state transitions work. Keep those claims tied to real runtime evidence.
