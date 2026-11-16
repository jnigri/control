import CoreGraphics

// Settings. Edit and rebuild.

let gap: CGFloat = 8                // space around each tiled window, in points
let resizeStep: CGFloat = 0.05      // how much Option + Minus / Equal moves a split
let deskKeys = "1234567890ABCDEGIMNOPQRSTUVWXYZ".map(String.init)  // every letter except F, H, J, K, L
let monitorDeskKeys = "098765432".map(String.init)  // the desk each extra monitor takes, in the order they are plugged
