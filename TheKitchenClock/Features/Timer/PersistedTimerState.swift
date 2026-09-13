import Foundation

enum PersistedTimerState: Codable, Equatable {
    case ready
    case running(deadline: Date)
    case finished

    private enum CodingKeys: String, CodingKey {
        case kind
        case deadline
    }

    private enum Kind: String, Codable {
        case ready
        case running
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
        case .finished:
            try container.encode(Kind.finished, forKey: .kind)
        }
    }
}
