import CoreGraphics

// Settings. Edit and rebuild.

let gap: CGFloat = 8                // space around each tiled window, in points
let resizeStep: CGFloat = 0.05      // how much Option + Minus / Equal moves a split
let deskKeys = "123456789ABCDEGIMNOPQRSTUVWXYZ".map(String.init)  // every letter except F, H, J, K, L
