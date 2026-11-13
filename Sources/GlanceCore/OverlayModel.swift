import Foundation

/// Where the current request is.
public enum Phase: Equatable, Sendable {
    /// Nothing asked yet.
    case empty
    /// Taking the screenshot. Nothing is drawn, so nothing of ours can end up in it.
    case capturing(id: Int)
    /// Screenshot taken, waiting for the AI.
    case working(id: Int)
    case ready(id: Int, answer: Answer)
    case failed(id: Int, message: String)
}

/// What the overlay should draw right now.
public enum Visible: Equatable, Sendable {
    case nothing
    case working
    case answer(Answer)
    case error(String)
}

/// The two-hotkey behaviour, as a plain value so it can be tested.
///
/// * The SWITCH (hotkey 2) decides whether anything is drawn. Off means off:
///   nothing appears, not even an answer that arrives while it is off.
/// * A NEW CAPTURE (hotkey 1) throws the old answer away immediately and starts
///   over, whatever the switch says. When the new answer arrives it is shown
///   only if the switch is on; flipping the switch on later reveals it.
/// * Every capture gets a new id. A reply carrying an older id is ignored, so a
///   slow reply to an earlier capture can never replace a newer one.
public struct OverlayModel: Equatable, Sendable {
    public private(set) var switchOn: Bool
    public private(set) var phase: Phase = .empty
    private var lastID = 0

    public init(switchOn: Bool = true) {
        self.switchOn = switchOn
    }

    @discardableResult
    public mutating func beginCapture() -> Int {
        lastID += 1
        phase = .capturing(id: lastID)
        return lastID
    }

    /// The screenshot for `id` is taken. Returns false if `id` is stale.
    @discardableResult
    public mutating func captured(id: Int) -> Bool {
        guard phase == .capturing(id: id) else { return false }
        phase = .working(id: id)
        return true
    }

    /// Returns false (and changes nothing) if `id` is no longer the request in flight.
    @discardableResult
    public mutating func finish(id: Int, answer: Answer) -> Bool {
        guard isInFlight(id) else { return false }
        phase = .ready(id: id, answer: answer)
        return true
    }

    @discardableResult
    public mutating func fail(id: Int, message: String) -> Bool {
        guard isInFlight(id) else { return false }
        phase = .failed(id: id, message: message)
        return true
    }

    public mutating func toggleSwitch() {
        switchOn.toggle()
    }

    public mutating func setSwitch(_ on: Bool) {
        switchOn = on
    }

    public var isBusy: Bool {
        switch phase {
        case .capturing, .working: return true
        default: return false
        }
    }

    public var currentAnswer: Answer? {
        if case .ready(_, let answer) = phase { return answer }
        return nil
    }

    public var visible: Visible {
        guard switchOn else { return .nothing }
        switch phase {
        case .empty, .capturing: return .nothing
        case .working: return .working
        case .ready(_, let answer): return .answer(answer)
        case .failed(_, let message): return .error(message)
        }
    }

    private func isInFlight(_ id: Int) -> Bool {
        phase == .capturing(id: id) || phase == .working(id: id)
    }
}
