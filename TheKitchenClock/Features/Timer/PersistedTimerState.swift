import Foundation

enum PersistedTimerState: Codable, Equatable {
    case ready
    case running(deadline: Date)
    case paused(remainingSeconds: Int64)
    case finished

    private enum CodingKeys: String, CodingKey {
        case kind
        case deadline
        case remainingSeconds
    }

    private enum Kind: String, Codable {
        case ready
        case running
        case paused
        case finished
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .ready:
            self = .ready
        case .running:
            self = .running(deadline: try container.decode(Date.self, forKey: .deadline))
        case .paused:
            self = .paused(remainingSeconds: try container.decode(Int64.self, forKey: .remainingSeconds))
        case .finished:
            self = .finished
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .ready:
            try container.encode(Kind.ready, forKey: .kind)
        case .running(let deadline):
            try container.encode(Kind.running, forKey: .kind)
            try container.encode(deadline, forKey: .deadline)
        case .paused(let remainingSeconds):
            try container.encode(Kind.paused, forKey: .kind)
            try container.encode(remainingSeconds, forKey: .remainingSeconds)
        case .finished:
            try container.encode(Kind.finished, forKey: .kind)
        }
    }
}
