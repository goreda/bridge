// UI/ExportMenu.swift
// The one-page "encode" menu model (owner layout 2026-11-26 22:15): export; separator; dimmed "settings" heading; x264, x265; separator; resolutions; separator; gor, crf 12..22. Lowercase labels, no archive wording.
// Uses: Foundation, Platform/ExportProfile, Picture/ExportSettings
// Engine: none
import Foundation

/// One row in the model. The AppKit binding maps rows to NSMenuItems; the
/// model carries the tags so rebuild hygiene (tag-or-clear) is decided here.
public struct ExportMenuRow: Equatable {
    public enum RowKind: Equatable {
        /// The "export" action row (tag 7403), first row of the encode page.
        case action
        /// The "encode" menu parent item (tag 7414).
        case settingsSubmenu
        /// The dimmed, non-selectable "settings" section heading (tag 7415).
        case heading
        /// A selectable option inside the submenu.
        case option
        /// A group separator. Separators are tagged so a rebuild can find and
        /// clear them; untagged separators accumulate across rebuilds.
        case separator
    }

    public let kind: RowKind
    public let title: String
    public let tag: Int
    public let isChecked: Bool
    public let isEnabled: Bool
    /// Why the row is disabled, for the binding to surface (tooltip/subtitle).
    /// Nil when enabled.
    public let disabledReason: String?
    /// The option value this row selects, when kind == .option.
    public let representedValue: String?

    public static func separator(tag: Int) -> ExportMenuRow {
        ExportMenuRow(kind: .separator, title: "", tag: tag,
                      isChecked: false, isEnabled: false,
                      disabledReason: nil, representedValue: nil)
    }
}

/// Whether a coordinator/render/encode route exists for Export As Seen.
/// Invariant: the action may enable only when a route is present.
public enum ExportEncodeRoute: Equatable {
    case unavailable(reason: String)
    // An accepted route adds: case available(routeID: String)
}

/// Tags reserved by this model. Rebuild hygiene depends on every dynamic row
/// and separator carrying one of these tags.
public enum ExportMenuTags {
    public static let action = 7403              // "Export As Seen" action item
    public static let separatorCodec = 7411      // between the export row and the settings heading
    public static let settingsHeading = 7415     // dimmed "settings" section heading
    public static let separatorResolution = 7412 // before the resolution group
    public static let separatorQuality = 7413    // before the quality group
    public static let settingsSubmenu = 7414     // the "encode" menu row
}

/// Builds the action row plus the Export Settings submenu rows from a profile
/// and the current source state. Pure model: no AppKit, no menu wiring.
public struct ExportMenu {

    /// The user's stored selection. Checkmarks follow this profile exactly,
    /// even when the selection is currently unusable (x264 under HDR):
    /// the UI never silently substitutes another codec.
    public let profile: ExportProfile

    /// Tri-state HDR knowledge of the current source. nil = UNKNOWN.
    /// UNKNOWN is never defaulted to SDR.
    public let sourceHDR: Bool?

    /// The encode route state. Without an accepted route the action is
    /// always disabled and says why.
    public let encodeRoute: ExportEncodeRoute

    public init(profile: ExportProfile, sourceHDR: Bool?, encodeRoute: ExportEncodeRoute) {
        self.profile = profile
        self.sourceHDR = sourceHDR
        self.encodeRoute = encodeRoute
    }

    // MARK: - Owner-designated option sets and labels

    /// Quality rows in menu order: the "gor" quality first, then the CRF
    /// presets in the contract's allowed set order.
    /// Codec rows in the owner's order: x264 first, then x265.
    public static let codecRows: [ExportCodec] = [.x264, .x265]

    public static let menuTitle = "encode"
    public static let exportTitle = "export"
    public static let settingsHeadingTitle = "settings"

    public static let qualityRows: [ExportQuality] =
        [.gor] + ExportQuality.allowedCRF.map { .crf($0) }

    public static func codecTitle(_ codec: ExportCodec) -> String {
        codec.rawValue // "x265" / "x264"
    }

    /// Labels come from the persistence/API owner's helpers so the menu and
    /// the store never drift: "Source", "CRF 12 Archive", "gor", "CRF N".
    public static func resolutionTitle(_ resolution: ExportResolution) -> String {
        ExportSettings.resolutionTitle(resolution).lowercased()   // "source", "480p" ...
    }

    /// "gor", "crf 12" ... "crf 22": lowercase, no archive wording.
    public static func qualityTitle(_ quality: ExportQuality) -> String {
        switch quality {
        case .gor: return "gor"
        case .crf(let c): return "crf \(c)"
        }
    }

    // MARK: - HDR / codec compatibility

    /// Refusal shown when an HDR source meets the 8-bit codec.
    public static let x264HDRDisabledReason = "x264 is 8-bit and is disabled for HDR sources"

    private static func codecCanCarryHDR(_ codec: ExportCodec) -> Bool {
        codec == .x265
    }

    // MARK: - Action availability

    /// The gate that applies once an encode route exists.
    /// Order: HDR knowledge, then codec/HDR compatibility.
    /// A nil sourceHDR (UNKNOWN) blocks the action; it is never treated as SDR.
    public static func postRouteDisabledReason(sourceHDR: Bool?, profile: ExportProfile) -> String? {
        guard let hdr = sourceHDR else {
            return "Source HDR state is unknown"
        }
        if hdr && !codecCanCarryHDR(profile.codec) {
            return x264HDRDisabledReason
        }
        return nil
    }

    /// The reason the Export As Seen action is disabled, or nil when it can run.
    /// The route check comes first: without an accepted route the action is
    /// always unavailable and says so. The action reports its state; it never
    /// fakes progress or success.
    public var actionDisabledReason: String? {
        switch encodeRoute {
        case .unavailable(let reason):
            return "export is not available: \(reason)"
        }
        // When an `.available` route case lands, the gate becomes:
        // return Self.postRouteDisabledReason(sourceHDR: sourceHDR, profile: profile)
    }

    /// The "Export As Seen" action row.
    public var actionRow: ExportMenuRow {
        let reason = actionDisabledReason
        return ExportMenuRow(
            kind: .action,
            title: Self.exportTitle,
            tag: ExportMenuTags.action,
            isChecked: false,
            isEnabled: reason == nil,
            disabledReason: reason,
            representedValue: nil
        )
    }

    // MARK: - Settings submenu

    /// Whether a codec row accepts a new selection. Unavailable combinations
    /// (x264 under known-HDR) stay visible and stay checked if already
    /// selected, but refuse new selection with a reason. HDR-UNKNOWN blocks
    /// nothing in the settings menu; it only blocks the action.
    private func codecDisabledReason(_ codec: ExportCodec) -> String? {
        if sourceHDR == true && !Self.codecCanCarryHDR(codec) {
            return Self.x264HDRDisabledReason
        }
        return nil
    }

    /// The one-page encode menu rows. The first row is the "encode" parent (consumers drop it); the rest is the page:
    /// export, separator, dimmed "settings" heading, codecs, separator, resolutions, separator, qualities.
    public var settingsRows: [ExportMenuRow] {
        let export = actionRow
        var rows: [ExportMenuRow] = [
            ExportMenuRow(kind: .settingsSubmenu, title: Self.menuTitle, tag: ExportMenuTags.settingsSubmenu,
                          isChecked: false, isEnabled: true,
                          disabledReason: nil, representedValue: nil),
            export,
            .separator(tag: ExportMenuTags.separatorCodec),
            ExportMenuRow(kind: .heading, title: Self.settingsHeadingTitle, tag: ExportMenuTags.settingsHeading,
                          isChecked: false, isEnabled: false,
                          disabledReason: nil, representedValue: nil),
        ]
        for codec in Self.codecRows {
            let reason = codecDisabledReason(codec)
            rows.append(ExportMenuRow(
                kind: .option,
                title: Self.codecTitle(codec),
                tag: 0,
                isChecked: profile.codec == codec,
                isEnabled: reason == nil,
                disabledReason: reason,
                representedValue: "codec.\(codec.rawValue)"
            ))
        }
        rows.append(.separator(tag: ExportMenuTags.separatorResolution))
        for resolution in ExportResolution.allCases {
            rows.append(ExportMenuRow(
                kind: .option,
                title: Self.resolutionTitle(resolution),
                tag: 0,
                isChecked: profile.resolution == resolution,
                isEnabled: true,
                disabledReason: nil,
                representedValue: "resolution.\(resolution.rawValue)"
            ))
        }
        rows.append(.separator(tag: ExportMenuTags.separatorQuality))
        for quality in Self.qualityRows {
            rows.append(ExportMenuRow(
                kind: .option,
                title: Self.qualityTitle(quality),
                tag: 0,
                isChecked: profile.quality == quality,
                isEnabled: true,
                disabledReason: nil,
                representedValue: "quality.\(ExportSettings.text(quality))"
            ))
        }
        return rows
    }
}

// MARK: - Idempotent install (surface sync)

extension ExportMenu {

    /// One item on a menu surface, reduced to what a sync decision needs.
    /// The AppKit binding maps NSMenuItems to and from this shape; the sync
    /// itself stays pure and testable.
    public struct SurfaceItem: Equatable {
        public var tag: Int
        public var title: String
        public var isSeparator: Bool
        public var isChecked: Bool
        public var isEnabled: Bool
        public var disabledReason: String?
        public var representedValue: String?
        /// Non-nil when the item carries a submenu (the settings row).
        public var submenu: [SurfaceItem]?

        public init(tag: Int, title: String, isSeparator: Bool = false, isChecked: Bool = false,
                    isEnabled: Bool = true, disabledReason: String? = nil,
                    representedValue: String? = nil, submenu: [SurfaceItem]? = nil) {
            self.tag = tag; self.title = title; self.isSeparator = isSeparator
            self.isChecked = isChecked; self.isEnabled = isEnabled
            self.disabledReason = disabledReason; self.representedValue = representedValue
            self.submenu = submenu
        }
    }

    /// Tags this model owns on the top-level surface. Any other tag is an
    /// unrelated item and is never touched.
    public static let ownedSurfaceTags: [Int] =
        [ExportMenuTags.action, ExportMenuTags.settingsSubmenu]

    /// Tags that only an earlier layout put on the top-level surface (the standalone action row). They are removed on sync; the action now lives inside the encode page.
    public static let legacySurfaceTags: [Int] = [ExportMenuTags.action]

    /// Syncs a menu surface with this model. Invariants:
    /// - After sync, the surface carries exactly one encode item (tag 7414) and no standalone action row (tag 7403; the export action is the first row inside the encode page). Duplicate owned items from
    ///   an earlier untagged or repeated install are removed, first kept.
    /// - Owned items found on the surface are updated in place at their
    ///   current position; missing owned items are appended (action, then
    ///   settings). Unrelated items are preserved untouched and in order.
    /// - The settings submenu's contents are fully owned and replaced as a
    ///   block on every sync: separators keep their tags, option checkmarks
    ///   follow the model's current profile. Re-running sync with fresh
    ///   settings is how state sync reaches an installed menu.
    /// - Idempotent: sync(sync(surface)) == sync(surface).
    public static func sync(surface: [SurfaceItem], with model: ExportMenu) -> [SurfaceItem] {
        let settingsItem = SurfaceItem(
            tag: ExportMenuTags.settingsSubmenu,
            title: menuTitle,
            submenu: model.settingsRows.dropFirst().map { row in
                SurfaceItem(
                    tag: row.tag,
                    title: row.title,
                    isSeparator: row.kind == .separator,
                    isChecked: row.isChecked,
                    isEnabled: row.isEnabled,
                    disabledReason: row.disabledReason,
                    representedValue: row.representedValue
                )
            }
        )

        var result: [SurfaceItem] = []
        var seen = false
        for item in surface {
            if legacySurfaceTags.contains(item.tag) { continue }   // old standalone action row: dropped
            if item.tag == ExportMenuTags.settingsSubmenu {
                guard !seen else { continue }                      // duplicate encode item: drop
                seen = true
                result.append(settingsItem)                        // update in place at the existing position
            } else {
                result.append(item)                                // unrelated: preserved untouched
            }
        }
        if !seen { result.append(settingsItem) }
        return result
    }
}
