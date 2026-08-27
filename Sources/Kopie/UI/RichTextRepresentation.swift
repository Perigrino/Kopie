import SwiftUI
import AppKit

/// A view that renders rich text (RTF or HTML) data as formatted text.
/// Designed to work inside SwiftUI `ScrollView` — does NOT embed its own
/// `NSScrollView`, which would cause nested-scrolling and zero-height issues.
struct RichTextRepresentation: NSViewRepresentable {
    let data: Data
    let isHTML: Bool

    init(data: Data, isHTML: Bool = false) {
        self.data = data
        self.isHTML = isHTML
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.lineFragmentPadding = 0

        // Let the text view resize vertically to fit all content, and track
        // the container width so lines wrap correctly.
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        // Start with a very tall container so all text lays out.
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude)

        // Parse the rich text data.
        var attributedString: NSAttributedString?

        if isHTML {
            attributedString = NSAttributedString(html: data, documentAttributes: nil)
        } else {
            attributedString = NSAttributedString(rtf: data, documentAttributes: nil)
        }

        // Fallbacks: try the other format if the primary one failed.
        if attributedString == nil && !isHTML {
            attributedString = NSAttributedString(html: data, documentAttributes: nil)
        }
        if attributedString == nil && isHTML {
            attributedString = NSAttributedString(rtf: data, documentAttributes: nil)
        }

        if let attrStr = attributedString {
            textView.textStorage?.setAttributedString(attrStr)
        } else if let plainText = String(data: data, encoding: .utf8) {
            textView.string = plainText
        }

        // Force layout so sizeThatFits has accurate metrics on the first call.
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        // Data is baked in at init; nothing to update.
    }

    func sizeThatFits(_ proposedSize: ProposedViewSize,
                      nsView: NSTextView,
                      context: Context) -> CGSize {
        let width = proposedSize.width ?? 300
        guard let lm = nsView.layoutManager, let tc = nsView.textContainer else {
            return CGSize(width: width, height: 44)
        }
        // Match the text container width to the proposed width (minus insets).
        tc.size = NSSize(width: width - nsView.textContainerInset.width * 2,
                         height: CGFloat.greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let usedHeight = lm.usedRect(for: tc).height
        let totalHeight = usedHeight + nsView.textContainerInset.height * 2
        return CGSize(width: width, height: max(totalHeight, 44))
    }
}
