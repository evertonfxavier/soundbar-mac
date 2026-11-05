import AppKit
import SwiftUI

/// Makes the menu window exactly as big as the menu.
///
/// The window of a `MenuBarExtra` grows when the content grows, but does not shrink when it does: after a section is
/// folded the window stays as tall as it was and the content sits in the lower part of it, under an empty strip. Put
/// this as the `background` of the content: the background is exactly as big as the content, so each time its size
/// changes the window is brought to it, with its top edge (the one under the menu bar) staying where it is.
struct WindowFitter: NSViewRepresentable {
    func makeNSView(context: Context) -> FitView { FitView() }
    func updateNSView(_ view: FitView, context: Context) {}

    final class FitView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            fit()
        }

        override func layout() {
            super.layout()
            fit()
        }

        /// Later in the run loop: resizing a window while it is laying out its content makes it lay out again.
        private func fit() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                let size = self.bounds.size
                guard size.width > 0, size.height > 0 else { return }
                let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
                var frame = window.frame
                guard abs(frame.height - target.height) > 0.5 || abs(frame.width - target.width) > 0.5 else { return }
                frame.origin.x += (frame.width - target.width) / 2
                frame.origin.y += frame.height - target.height
                frame.size = target
                window.setFrame(frame, display: true, animate: false)
            }
        }
    }
}
