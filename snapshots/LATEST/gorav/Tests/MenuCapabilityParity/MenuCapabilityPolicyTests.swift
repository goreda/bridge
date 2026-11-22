@main
struct MenuCapabilityPolicyTests {
    static func main() {
        var count = 0
        func check(_ value: Bool, _ name: String) {
            precondition(value, name); count += 1
        }
        let all = Set(MenuPlaybackAction.allCases)
        for state in PlayerLifecycleState.allCases {
            for action in MenuPlaybackAction.allCases {
                let empty = MenuCapabilitySnapshot(lifecycle: state)
                check(!MenuCapabilityPolicy.decision(for: action, snapshot: empty).isEnabled,
                      "absent dependency never enables \(state)/\(action)")
                for blocked in [
                    MenuCapabilitySnapshot(lifecycle: state, available: all, fenced: true),
                    MenuCapabilitySnapshot(lifecycle: state, available: all, tornDown: true),
                    MenuCapabilitySnapshot(lifecycle: state, available: all, handoffPending: true)
                ] {
                    check(!MenuCapabilityPolicy.decision(for: action, snapshot: blocked).isEnabled,
                          "blocked session never enables \(state)/\(action)")
                }
                let snapshot = MenuCapabilitySnapshot(lifecycle: state, available: all)
                // Literal oracle, deliberately independent of allows().
                // c1431906 PlayerControlPlane.swift:47-60 defines legal engine states.
                // The archived gor MenuActions.swift:33-40 at
                // Documentation/kni-ocr-desk/gorav-project-backup-20261018-r1/
                // documents/bce-MenuActions.swift binds toggle pause and seeks.
                // That archive supplies action intent, not current host UI proof.
                let expected: [PlayerLifecycleState: Set<MenuPlaybackAction>] = [
                    .playing: [.pause, .seek, .volume, .audioTrack, .audioDelay,
                               .subtitleSelect, .subtitleDelay, .subtitleVisibility, .hostTransform],
                    .paused: [.resume, .seek, .volume, .audioTrack, .audioDelay,
                              .subtitleSelect, .subtitleDelay, .subtitleVisibility, .hostTransform]
                ]
                let allowed = expected[state, default: []].contains(action)
                check(MenuCapabilityPolicy.decision(for: action, snapshot: snapshot).isEnabled == allowed,
                      "production lifecycle parity \(state)/\(action)")
            }
        }
        for state in [PlayerLifecycleState.playing, .paused] {
            let prepared = MenuCapabilitySnapshot(lifecycle: state, available: all, preparedTimeline: true)
            check(MenuCapabilityPolicy.decision(for: .seek, snapshot: prepared) == .disabled(.preparedTimelineOwnsSeek),
                  "prepared video owns seek")
            check(MenuCapabilityPolicy.decision(for: .volume, snapshot: prepared).isEnabled,
                  "prepared timeline does not remove audio control")
        }
        let volumeOnly = MenuCapabilitySnapshot(lifecycle: .playing, available: [.volume])
        check(MenuCapabilityPolicy.decision(for: .volume, snapshot: volumeOnly).isEnabled, "volume installed")
        check(MenuCapabilityPolicy.decision(for: .audioTrack, snapshot: volumeOnly) == .disabled(.dependencyUnavailable),
              "volume does not imply track switching")
        print("PASS MenuCapabilityPolicy \(count) checks; production policy and lifecycle source, no host UI claim")
    }
}
