import SwiftUI
import AppKit

/// A view that renders rich text (RTF) data as formatted text.
struct RichTextRepresentation: NSViewRepresentable {
    let data: Data
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        
        // Load and display the RTF content
        if let attributedString = NSAttributedString(rtf: data, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attributedString)
        } else if let plainText = String(data: data, encoding: .utf8) {
            textView.string = plainText
        }
        
        scrollView.documentView = textView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Update is handled by init
    }
}
