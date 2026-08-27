import SwiftUI
import AppKit

/// A view that renders rich text (RTF or HTML) data as formatted text.
struct RichTextRepresentation: NSViewRepresentable {
    let data: Data
    let isHTML: Bool
    
    init(data: Data, isHTML: Bool = false) {
        self.data = data
        self.isHTML = isHTML
    }
    
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
        
        // Load and display the rich text content
        var attributedString: NSAttributedString? = nil
        
        if isHTML {
            // Try HTML first
            attributedString = NSAttributedString(html: data, documentAttributes: nil)
        } else {
            // Try RTF
            attributedString = NSAttributedString(rtf: data, documentAttributes: nil)
        }
        
        // Fallback to plain text if rich text parsing fails
        if let attrStr = attributedString {
            textView.textStorage?.setAttributedString(attrStr)
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
