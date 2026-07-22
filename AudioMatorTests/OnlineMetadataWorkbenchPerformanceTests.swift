import AppKit
import SwiftUI
import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class OnlineMetadataWorkbenchPerformanceTests: XCTestCase {
    func testAppKitTrackSelectionValuesStayAlignedWithSeparatorMenuItem() {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.addItem(withTitle: "Unassigned")
        popUp.menu?.addItem(.separator())
        popUp.addItem(withTitle: "Track One")
        popUp.addItem(withTitle: "Track Two")

        let values = OnlineMetadataWorkbenchPopUpMapping.selectionValues(for: [101, 202])

        XCTAssertEqual(values.count, popUp.numberOfItems)
        XCTAssertNil(values[0])
        XCTAssertNil(values[1])
        XCTAssertEqual(values[2], 101)
        XCTAssertEqual(values[3], 202)

        popUp.selectItem(at: 2)
        XCTAssertEqual(popUp.titleOfSelectedItem, "Track One")
        XCTAssertEqual(values[popUp.indexOfSelectedItem], 101)

        popUp.selectItem(at: 3)
        XCTAssertEqual(popUp.titleOfSelectedItem, "Track Two")
        XCTAssertEqual(values[popUp.indexOfSelectedItem], 202)
    }

    func testDeferredSelectionMenuDoesNotBuildOptionsBeforeOpening() {
        let options = (0..<100).map(Option.init(id:))
        let deferredCounter = InvocationCounter()
        let pickerCounter = InvocationCounter()

        render(
            DeferredSelectionMenu(
                options: options,
                selection: .constant(0),
                selectionValue: \.id,
                optionTitle: { option in
                    deferredCounter.count += 1
                    return "Track \(option.id)"
                }
            )
        )

        render(
            Picker("Track", selection: .constant(0)) {
                ForEach(options) { option in
                    CountedPickerOption(option: option, counter: pickerCounter)
                }
            }
            .pickerStyle(.menu)
        )

        XCTAssertLessThan(deferredCounter.count, options.count)
        XCTAssertGreaterThanOrEqual(pickerCounter.count, options.count)
    }

    private func render<Content: View>(_ content: Content) {
        let host = NSHostingView(rootView: content.frame(width: 400, height: 100))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
    }
}

private struct Option: Identifiable {
    let id: Int
}

@MainActor
private final class InvocationCounter {
    var count = 0
}

private struct CountedPickerOption: View {
    let option: Option
    let counter: InvocationCounter

    var body: some View {
        let _ = incrementCounter()
        Text("Track \(option.id)")
            .tag(option.id)
    }

    @MainActor
    private func incrementCounter() {
        counter.count += 1
    }
}
#endif
