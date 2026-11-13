import Foundation

public struct TimeoutError: Error, Equatable {
    public init() {}
}

public struct NoServiceError: Error, Equatable {
    public init() {}
}

public enum AnswerSource: String, Sendable {
    case cloud
    case local
}

public struct HedgePolicy: Sendable {
    /// How long to wait for the cloud before giving up on it.
    public var cloudTimeout: Double
    /// How long the cloud gets before the backup is started alongside it.
    public var hedgeDelay: Double
    /// Hard limit for the backup once it has started.
    public var localTimeout: Double

    public init(cloudTimeout: Double, hedgeDelay: Double, localTimeout: Double) {
        self.cloudTimeout = cloudTimeout
        self.hedgeDelay = hedgeDelay
        self.localTimeout = localTimeout
    }
}

public typealias Job<T> = @Sendable () async throws -> T

/// Runs `operation`, throwing `TimeoutError` if it takes longer than `seconds`.
/// The operation is cancelled when the time runs out.
public func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping Job<T>) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: nanoseconds(seconds))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw TimeoutError() }
        return first
    }
}

/// "Cloud first, backup only if the cloud is slow."
///
/// * The cloud request starts immediately.
/// * The backup (`local`) starts only once the cloud has taken `hedgeDelay`
///   seconds, or straight away if the cloud fails sooner. So a fast cloud
///   never pays for the backup at all.
/// * Once both are running, the first SUCCESSFUL answer wins and the other is
///   cancelled. A failure only ends the race when the other side has failed too.
/// * If one side is missing (no key, or no local model yet), the other simply runs alone.
/// * Cancelling the calling task cancels everything.
public func runHedged<T: Sendable>(cloud: Job<T>?, local: Job<T>?, policy: HedgePolicy) async throws -> (T, AnswerSource) {
    guard cloud != nil || local != nil else { throw NoServiceError() }

    return try await withThrowingTaskGroup(of: HedgeEvent<T>.self) { group in
        var localStarted = false
        var cloudPending = false
        var cloudError: Error?
        var localError: Error?

        if let cloud {
            cloudPending = true
            group.addTask { .cloud(await outcome { try await withTimeout(seconds: policy.cloudTimeout, cloud) }) }
            if local != nil {
                group.addTask {
                    try? await Task.sleep(nanoseconds: nanoseconds(policy.hedgeDelay))
                    return .hedgeTimer
                }
            }
        } else if let local {
            localStarted = true
            group.addTask { .local(await outcome { try await withTimeout(seconds: policy.localTimeout, local) }) }
        }

        while let event = try await group.next() {
            try Task.checkCancellation()
            switch event {
            case .cloud(.success(let value)):
                group.cancelAll()
                return (value, .cloud)

            case .cloud(.failure(let error)):
                cloudPending = false
                cloudError = error
                if let local, !localStarted {
                    localStarted = true
                    group.addTask { .local(await outcome { try await withTimeout(seconds: policy.localTimeout, local) }) }
                } else if !localStarted || localError != nil {
                    group.cancelAll()
                    throw error
                }

            case .hedgeTimer:
                if let local, !localStarted, cloudPending {
                    localStarted = true
                    group.addTask { .local(await outcome { try await withTimeout(seconds: policy.localTimeout, local) }) }
                }

            case .local(.success(let value)):
                group.cancelAll()
                return (value, .local)

            case .local(.failure(let error)):
                localError = error
                if !cloudPending {
                    group.cancelAll()
                    throw cloudError ?? error
                }
            }
        }

        try Task.checkCancellation()
        throw cloudError ?? localError ?? NoServiceError()
    }
}

enum HedgeEvent<T: Sendable>: Sendable {
    case cloud(Result<T, Error>)
    case local(Result<T, Error>)
    case hedgeTimer
}

func outcome<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}

func nanoseconds(_ seconds: Double) -> UInt64 {
    UInt64(max(0, seconds) * 1_000_000_000)
}
