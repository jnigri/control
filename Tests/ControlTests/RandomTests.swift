import CoreGraphics
import Testing
@testable import Control

// Long random sessions: windows open and close, keys are pressed, windows are dragged, monitors
// come and go, videos go full screen, the screen locks. After every step the same simple rules must hold.

extension ControlTests {
    @Test(arguments: 1...30)
    func aLongRandomSessionNeverBreaksTheRules(seed: Int) {
        var random = Seeded(seed: UInt64(seed))
        func chance(_ percent: Int) -> Bool { Int.random(in: 0..<100, using: &random) < percent }
        let keys = ["1", "2", "3", "M", "0", "9"]
        let directions: [Direction] = [.left, .down, .up, .right]
        let layouts = [[mainMonitor], [mainMonitor, rightMonitor], [mainMonitor, monitor(3, y: 820)],
                       [mainMonitor, rightMonitor, monitor(3, x: -1000, y: 300)]]
        var next = 0

        for step in 0..<300 {
            let reported = fake.windows()
            let visible = visibleDesks()
            // Past a handful of windows per desk, tiles get too thin to mean anything.
            let crowded = allDesks.contains { $0.tiled.count > 5 }
            let action = crowded ? 3 : Int.random(in: 0..<21, using: &random)
            switch action {
            case 0, 1, 2:
                next += 1
                let new = window(next)
                if chance(15) { fake.minimums[new] = CGSize(width: 600, height: 500) }   // an app that refuses to shrink
                fake.opens(next, on: fake.screens.randomElement(using: &random)!, dialog: chance(20), app: "app.\(next % 5)")
            case 3 where !reported.isEmpty:
                let busiest = allDesks.max { $0.tiled.count < $1.tiled.count }!.tiled
                fake.closes((crowded ? busiest : reported).randomElement(using: &random)!)
            case 4, 5 where !reported.isEmpty:
                // Click a window you can see.
                if let window = visible.flatMap(\.desk.windows).randomElement(using: &random) { fake.focus(window) }
                refresh()
                // Or pick any window, with Command + Tab, a while after the last one closed: its desk shows.
                if chance(50), let window = allDesks.flatMap(\.windows).randomElement(using: &random), !isCovered(desk(of: window)!) {
                    fake.now = fake.now.addingTimeInterval(closeTime)
                    fake.focus(window)
                    refresh()
                    #expect(visibleDesks().contains { $0.desk === desk(of: window) }, "seed \(seed), step \(step)")
                }
            case 6, 7: show(keys.randomElement(using: &random)!)
            case 8: send(to: keys.randomElement(using: &random)!)
            case 9: show(previous)
            case 10: moveFocus(directions.randomElement(using: &random)!)
            case 11, 12: swap(directions.randomElement(using: &random)!)
            case 13: resize(by: chance(50) ? resizeStep : -resizeStep)
            case 14: chance(50) ? toggleFullscreen() : toggleFloating()
            case 15:
                // Drag a window somewhere, or drag one of its edges.
                guard let window = visible.flatMap(\.desk.windows).randomElement(using: &random) else { break }
                var frame = fake.frames[window]!
                let screen = fake.screens.randomElement(using: &random)!.frame
                let pointer = CGPoint(x: .random(in: screen.minX...screen.maxX, using: &random),
                                      y: .random(in: screen.minY...screen.maxY, using: &random))
                if chance(50) {
                    frame.origin = CGPoint(x: pointer.x - 50, y: pointer.y - 10)
                } else {
                    frame = rect(frame.minX + (chance(50) ? .random(in: -300...300, using: &random) : 0), frame.minY,
                                 max(60, frame.width + .random(in: -300...300, using: &random)),
                                 max(60, frame.height + (chance(50) ? .random(in: -300...300, using: &random) : 0)))
                }
                // Part of the window stays on a monitor: the pointer cannot leave them.
                guard fake.screens.contains(where: { $0.area.intersection(frame).width > 40 && $0.area.intersection(frame).height > 40 }) else { break }
                fake.drags(window, to: frame, pointer: chance(80) ? pointer : CGPoint(x: frame.maxX, y: frame.midY))
            case 16:
                fake.plugs(layouts.randomElement(using: &random)!)
                if chance(30) { show(keys.randomElement(using: &random)!) }   // a key before Control hears about it
                refresh()
            case 17 where !reported.isEmpty:
                // A window goes full screen on its monitor, a few things happen, and it comes back.
                guard let window = visible.flatMap(\.desk.tiled).randomElement(using: &random),
                      let screen = fake.screens.first(where: { $0.frame.intersects(fake.frames[window]!) }) else { break }
                let old = fake.entersFullScreen(window, on: screen)
                if chance(50) { show(keys.randomElement(using: &random)!) }
                if chance(50) { swap(directions.randomElement(using: &random)!) }
                if chance(30) { next += 1; fake.opens(next, on: fake.screens.randomElement(using: &random)!) }
                if chance(20), let other = fake.open.filter({ $0 != window }).randomElement(using: &random) { fake.closes(other) }
                if chance(10) { fake.plugs(layouts.randomElement(using: &random)!) }
                refresh()
                fake.leavesFullScreen(window, backTo: old)
            case 18:
                // The screen locks or the Mac sleeps: apps report nothing, events still come, monitors
                // may come and go. On waking up, apps take a moment to report their windows again.
                chance(50) ? (locked = true) : (asleep = true)
                let before = fake.frames
                fake.unreported = Set(fake.open)
                refresh()
                show(keys.randomElement(using: &random)!)
                if chance(30) { fake.plugs(layouts.randomElement(using: &random)!) }
                locked = false
                asleep = false
                resume()
                fake.unreported = Set(fake.open.filter { _ in chance(50) })
                refresh()
                fake.unreported = []
                refresh()
                fake.now = fake.now.addingTimeInterval(catchUpTime)
                refresh()
                #expect(Set(fake.frames.keys) == Set(before.keys))
            case 19:
                // Control crashes and starts again: every window is found on its desk.
                let before = Dictionary(uniqueKeysWithValues: allDesks.map { ($0.name, Set($0.windows)) })
                restart(on: fake)
                #expect(Dictionary(uniqueKeysWithValues: allDesks.map { ($0.name, Set($0.windows)) }) == before, "seed \(seed), step \(step)")
            default:
                refresh()
            }
            expectRules(fake, "seed \(seed), step \(step), action \(action)")
        }
    }
}

/// What must be true whenever Control has caught up with the Mac.
func expectRules(_ fake: FakeMac, _ when: String) {
    let comment = Comment(rawValue: when)
    let shown = visibleDesks()

    // Every open window is on exactly one desk, and no desk holds a closed window.
    let held = allDesks.flatMap(\.windows)
    #expect(held.count == Set(held).count, comment)
    #expect(Set(held) == Set(fake.open), comment)
    #expect(shown.count == fake.screens.count, comment)

    for desk in allDesks {
        expectSound(desk, in: mainMonitor.area)
        #expect(desk.fullscreen.map(desk.tiled.contains) ?? true, comment)
        #expect(desk.lastFocused.map(desk.windows.contains) ?? true, comment)
        #expect(Set(desk.tiled).isDisjoint(with: desk.floating), comment)

        if let area = shown.first(where: { $0.desk === desk })?.area {
            // On screen: every tiled window is exactly on its tile, and no window is parked.
            // (An app that refuses to shrink keeps its place, but sticks out.)
            let frames = fake.frames.filter { desk.tiled.contains($0.key) }.mapValues { CGRect(origin: $0.origin, size: .zero) }
            let tiles = desk.layout(in: area)
            for (window, tile) in tiles {
                let least = fake.minimums[window] ?? .zero
                #expect(same(fake.frames[window]!.size.width, max(tile.width, least.width)), comment)
                #expect(same(fake.frames[window]!.size.height, max(tile.height, least.height)), comment)
            }
            #expect(desk.floating.allSatisfy { visibleArea(of: $0, on: fake) > 1 }, "\(when): a floating window is out of sight: desk \(desk.name) \(desk.floating.map { fake.frames[$0]! }) screens \(fake.screens.map(\.frame)) covered \(covered)")
            #expect(same(tiles.mapValues { CGRect(origin: $0.origin, size: .zero) }, frames), "\(when): desk \(desk.name) wants \(desk.layout(in: area).values.sorted { $0.minX < $1.minX }) has \(frames.values.sorted { $0.minX < $1.minX })")
            #expect(desk.windows.allSatisfy { hidden[$0] == nil }, comment)
        } else {
            // Off screen: one point shows, no more (and no less, or macOS would move the window back).
            for window in desk.windows {
                #expect(hidden[window] != nil, comment)
                #expect(visibleArea(of: window, on: fake) == 1, comment)
            }
        }
    }
}
