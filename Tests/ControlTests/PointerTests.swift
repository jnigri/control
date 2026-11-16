import CoreGraphics
import Testing
@testable import Control

// The mouse pointer follows the focus to another window, and goes to the middle of an empty desk.

func middle(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

extension ControlTests {
    @Test func switchingToAnotherWindowPutsThePointerInTheMiddleOfIt() {
        let a = fake.opens(1), b = fake.opens(2)
        #expect(fake.pointer == middle(rightHalf))
        // Command + Tab back to the first app.
        fake.focused = a
        refresh()
        #expect(fake.pointer == middle(leftHalf))
        // Option + L.
        moveFocus(.right)
        refresh()
        #expect(fake.focused == b)
        #expect(fake.pointer == middle(rightHalf))
    }

    /// A click on a window gives it the focus. The pointer stays where the user clicked.
    @Test func clickingAWindowLeavesThePointerAlone() {
        let a = fake.opens(1)
        fake.opens(2)
        fake.clicks(a, at: CGPoint(x: 30, y: 40))
        #expect(fake.pointer == CGPoint(x: 30, y: 40))
    }

    /// A click in the Dock gives the focus to a window away from the pointer.
    @Test func clickingAnAppInTheDockPutsThePointerOnItsWindow() {
        let a = fake.opens(1)
        fake.opens(2)
        fake.clicks(a, at: CGPoint(x: 500, y: 815))
        #expect(fake.pointer == middle(leftHalf))
    }

    @Test func pickingAnAppOnAnotherDeskPutsThePointerOnItsWindowOnceShown() {
        let a = fake.opens(1)
        show("2")
        fake.opens(2)
        fake.pointer = CGPoint(x: 999, y: 819)
        fake.focused = a
        refresh()
        #expect(current == "1")
        #expect(fake.pointer == middle(whole))
    }

    /// Before, the pointer stayed put when it was already over the window: a window alone on its
    /// desk covers the spot where the pointer was on the desk before.
    @Test func showingADeskWithOneWindowPutsThePointerInTheMiddleOfIt() {
        let a = fake.opens(1)
        fake.opens(2)
        fake.focused = a
        refresh()
        show("2")
        let c = fake.opens(3)
        show("1")
        refresh()   // macOS says the focus moved
        #expect(fake.focused == a)
        #expect(fake.pointer == middle(leftHalf))
        show("2")
        refresh()
        #expect(fake.focused == c)
        #expect(fake.pointer == middle(whole))
    }

    @Test func showingAnEmptyDeskPutsThePointerInItsMiddle() {
        fake.opens(1)
        show("2")
        #expect(fake.pointer == middle(mainMonitor.area))
    }

    @Test func showingAnEmptyDeskOfAnExtraMonitorPutsThePointerInItsMiddle() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1)
        show("0")
        #expect(fake.pointer == middle(rightMonitor.area))
        // The focus stays where it was.
        #expect(fake.focused == a)
    }

    @Test func goingFullscreenAndBackPutsThePointerInTheMiddleOfTheWindow() {
        fake.opens(1)
        fake.opens(2)
        toggleFullscreen()
        #expect(fake.pointer == middle(mainMonitor.area))
        toggleFullscreen()
        #expect(fake.pointer == middle(rightHalf))
    }

    @Test func movingTheFocusedWindowTakesThePointerAlong() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1)
        fake.opens(2)
        fake.focused = a
        refresh()
        swap(.right)
        #expect(fake.pointer == middle(rightHalf))
        swap(.left)
        #expect(fake.pointer == middle(leftHalf))
        toggleFloating()
        #expect(fake.pointer == middle(fake.frames[a]!))
        send(to: "0")
        #expect(fake.pointer == middle(fake.frames[a]!))
        #expect(rightMonitor.area.contains(fake.pointer))
    }

    /// Closing a window: macOS picks the next one on its own. The user did not switch windows.
    @Test func closingAWindowLeavesThePointerAlone() {
        let a = fake.opens(1), b = fake.opens(2)
        fake.pointer = CGPoint(x: 900, y: 50)
        fake.closes(b)
        #expect(fake.focused == a)
        #expect(fake.pointer == CGPoint(x: 900, y: 50))
    }

    /// With the setting off, nothing moves the pointer.
    @Test func withTheSettingOffThePointerStaysPut() {
        let old = config
        defer { config = old }
        config.centerPointer = false
        let a = fake.opens(1)
        fake.opens(2)
        let corner = CGPoint(x: 999, y: 819)
        #expect(fake.pointer == corner)
        fake.focused = a
        refresh()
        moveFocus(.right)
        refresh()
        toggleFullscreen()
        swap(.left)
        show("2")
        #expect(fake.pointer == corner)
    }
}
