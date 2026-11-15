import CoreGraphics
import Testing
@testable import Control

// macOS's own full screen mode (the green button, or a video player's full screen button).
// The window moves to a Space of its own, and apps stop reporting the windows left behind.

extension ControlTests {
    /// The bug: a video going full screen made every other window look closed. When the video
    /// came back, they were all new windows, tiled again in whatever order.
    @Test func aFullScreenVideoKeepsTheLayout() {
        let a = fake.opens(1), b = fake.opens(2), c = fake.opens(3)
        fake.focus(a)
        refresh()
        resize(by: 0.2)
        let before = fake.frames

        let old = fake.entersFullScreen(b)
        #expect(fake.unreported == [a, c])
        #expect(desks["1"]!.tiled == [a, b, c])
        #expect(fake.frames[b] == mainMonitor.frame)   // we do not fight the video
        refresh()
        #expect(desks["1"]!.tiled == [a, b, c])

        fake.leavesFullScreen(b, backTo: old)
        #expect(fake.frames == before)
        #expect(covered.isEmpty)
    }

    @Test func windowsOnHiddenDesksSurviveAFullScreenVideo() {
        let a = fake.opens(1)
        let d = fake.opens(4)
        send(to: "2")
        show("1")
        let old = fake.entersFullScreen(a)
        #expect(fake.unreported == [d])   // parked with one point on the main monitor
        #expect(desks["2"]!.tiled == [d])
        fake.leavesFullScreen(a, backTo: old)
        show("2")
        #expect(fake.frames[d] == whole)
    }

    /// Some players put the video in a new window that is born full screen.
    @Test func aWindowBornFullScreenIsNotTiled() {
        let a = fake.opens(1), b = fake.opens(2)
        let before = fake.frames
        let video = window(9)
        fake.open.append(video)
        fake.frames[video] = mainMonitor.frame
        _ = fake.entersFullScreen(video)
        #expect(desk(of: video) == nil)
        #expect(desks["1"]!.tiled == [a, b])
        fake.closes(video)
        fake.unreported = []
        refresh()
        #expect(fake.frames == before)
    }

    /// Once it is a normal window, it tiles like any other.
    @Test func aWindowThatLeavesFullScreenForTheFirstTimeIsTiled() {
        let a = fake.opens(1)
        let video = window(9)
        fake.open.append(video)
        fake.frames[video] = mainMonitor.frame
        _ = fake.entersFullScreen(video)
        fake.leavesFullScreen(video, backTo: rect(100, 100, 400, 300))
        #expect(fake.frames == [a: leftHalf, video: rightHalf])
    }

    @Test func keysPressedDuringAFullScreenVideoWaitUntilItEnds() {
        let a = fake.opens(1), b = fake.opens(2)
        let old = fake.entersFullScreen(a)
        let during = fake.frames
        show("2")
        refresh()
        #expect(fake.frames == during)   // nothing moves under the video
        fake.leavesFullScreen(a, backTo: old)
        #expect(current == "2")
        #expect(visibleArea(of: a, on: fake) <= 1)
        #expect(visibleArea(of: b, on: fake) <= 1)
        show("1")
        #expect(fake.frames == [a: leftHalf, b: rightHalf])
    }

    @Test func theOtherMonitorKeepsTilingDuringAFullScreenVideo() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1), b = fake.opens(2)
        let x = fake.opens(3, on: rightMonitor)
        let old = fake.entersFullScreen(a)
        #expect(fake.unreported == [b])
        #expect(covered == [1])

        // Work goes on next to the video.
        let y = fake.opens(4, on: rightMonitor)
        #expect(fake.frames[x] == leftHalf.offsetBy(dx: 1000, dy: 0))
        #expect(fake.frames[y] == rightHalf.offsetBy(dx: 1000, dy: 0))
        fake.closes(x)
        #expect(fake.frames[y] == whole.offsetBy(dx: 1000, dy: 0))
        #expect(fake.frames[a] == mainMonitor.frame)

        fake.leavesFullScreen(a, backTo: old)
        #expect(fake.frames == [a: leftHalf, b: rightHalf, y: whole.offsetBy(dx: 1000, dy: 0)])
    }

    @Test func aFullScreenVideoOnTheOtherMonitorLeavesTheMainOneAlone() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1)
        let x = fake.opens(2, on: rightMonitor), y = fake.opens(3, on: rightMonitor)
        let old = fake.entersFullScreen(x, on: rightMonitor)
        #expect(fake.unreported == [y])
        #expect(monitorDesks[2]!.tiled == [x, y])
        let b = fake.opens(4)
        #expect(fake.frames[a] == leftHalf)
        #expect(fake.frames[b] == rightHalf)
        fake.leavesFullScreen(x, backTo: old)
        #expect(fake.frames[x] == leftHalf.offsetBy(dx: 1000, dy: 0))
        #expect(fake.frames[y] == rightHalf.offsetBy(dx: 1000, dy: 0))
    }

    /// With "Displays have separate Spaces" off, a full screen window blanks every monitor.
    @Test func withoutSeparateSpacesAFullScreenVideoCoversEveryMonitor() {
        fake.screens = [mainMonitor, rightMonitor]
        fake.separateSpaces = false
        let a = fake.opens(1)
        let x = fake.opens(2, on: rightMonitor), y = fake.opens(3, on: rightMonitor)
        let before = fake.frames
        let old = fake.entersFullScreen(a)
        #expect(fake.unreported == [x, y])
        #expect(monitorDesks[2]!.tiled == [x, y])
        fake.leavesFullScreen(a, backTo: old)
        #expect(fake.frames == before)
    }

    /// With a monitor on each side, hidden windows are parked on a side monitor's corner.
    /// A video there must not make them look closed.
    @Test func windowsParkedOnAnotherMonitorSurviveAFullScreenVideoThere() {
        fake.screens = [mainMonitor, rightMonitor, monitor(3, x: -1000)]
        let a = fake.opens(1)
        let dialog = fake.opens(2, dialog: true)
        show("2")
        #expect(rightMonitor.frame.intersects(fake.frames[a]!))
        let x = fake.opens(3, on: rightMonitor)
        let old = fake.entersFullScreen(x, on: rightMonitor)
        #expect(fake.unreported == [a, dialog])
        fake.leavesFullScreen(x, backTo: old)
        show("1")
        #expect(fake.frames[a] == whole)
        #expect(fake.frames[dialog] == rect(300, 270, 400, 300))
    }

    /// A window closed behind the video is noticed when the video ends.
    @Test func aWindowClosedBehindAFullScreenVideoLeavesAfterwards() {
        let a = fake.opens(1), b = fake.opens(2)
        let old = fake.entersFullScreen(a)
        fake.closes(b)
        fake.leavesFullScreen(a, backTo: old)
        #expect(fake.frames == [a: whole])
    }
}
