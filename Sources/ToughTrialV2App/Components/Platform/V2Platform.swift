import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Native presentation differences live here; domain actions are shared.
@MainActor
enum V2Platform {
    static func endEditing() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #else
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
    static func isImage(_ data: Data) -> Bool {
        #if os(iOS)
        UIImage(data: data) != nil
        #else
        NSImage(data: data) != nil
        #endif
    }
}

enum V2InputKeyboard { case decimalPad, URL, emailAddress, numberPad, `default` }
enum V2InputCapitalization { case never, characters, words, sentences }
extension View {
    @ViewBuilder func v2InlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    @ViewBuilder func v2KeyboardType(_ type: V2InputKeyboard) -> some View {
        #if os(iOS)
        keyboardType(type == .decimalPad ? .decimalPad : type == .URL ? .URL : type == .emailAddress ? .emailAddress : type == .numberPad ? .numberPad : .default)
        #else
        self
        #endif
    }
    @ViewBuilder func v2Autocapitalization(_ type: V2InputCapitalization) -> some View {
        #if os(iOS)
        textInputAutocapitalization(type == .never ? .never : type == .characters ? .characters : type == .words ? .words : .sentences)
        #else
        self
        #endif
    }
    @ViewBuilder func v2FullScreenCover<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        #else
        sheet(item: item, onDismiss: onDismiss) { item in content(item).frame(minWidth: 760, minHeight: 580) }
        #endif
    }
    @ViewBuilder func v2FullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #else
        sheet(isPresented: isPresented, onDismiss: onDismiss) { content().frame(minWidth: 760, minHeight: 580) }
        #endif
    }
}
extension ToolbarItemPlacement {
    static var v2Trailing: Self {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
    static var v2Leading: Self {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }
}

extension View {
    func v2Sheet<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        sheet(item: item, onDismiss: onDismiss) { value in
            #if os(macOS)
            content(value).frame(minWidth: 560, minHeight: 580)
            #else
            content(value)
            #endif
        }
    }
    func v2Sheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            #if os(macOS)
            content().frame(minWidth: 560, minHeight: 580)
            #else
            content()
            #endif
        }
    }
}

extension View {
    @ViewBuilder func v2NavigationPicker() -> some View {
        #if os(iOS)
        pickerStyle(.navigationLink)
        #else
        pickerStyle(.menu)
        #endif
    }
}

extension View {
    @ViewBuilder func v2GroupedList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }
}
