import CoreGraphics
import Foundation

extension Library {
    /// What changed from `old`, in words, or nil when nothing did.
    func change(from old: Library) -> String? {
        guard old.revision != revision else { return nil }
        if let made = components.first(where: { new in !old.components.contains { $0.id == new.id } }) {
            return L("部品「\(made.name)」を作った", "Made the part \"\(made.name)\"")
        }
        if components.count == old.components.count {
            for (a, b) in zip(old.components, components) where a.id == b.id && a.name != b.name {
                return L("部品の名前を「\(b.name)」にした", "Renamed a part to \"\(b.name)\"")
            }
        }
        if page != old.page {
            guard let page else { return L("コマ割りをやめた", "Stopped dividing the page") }
            if page.root.count != old.page?.root.count {
                return L("コマを切った（\(page.root.count) コマ）", "Cut a panel (\(page.root.count) panels)")
            }
            return L("コマの枠や間を変えた", "Changed the panel frames")
        }
        if currentTheme != old.currentTheme, let theme = themes.first(where: { $0.id == currentTheme }) {
            return L("色の組を「\(theme.name)」にした", "Switched the colours to \"\(theme.name)\"")
        }
        if let saved = themes.first(where: { new in !old.themes.contains { $0.id == new.id } }) {
            return L("今の色を色の組「\(saved.name)」として残した", "Kept the colours as \"\(saved.name)\"")
        }
        if let added = swatches.first(where: { new in !old.swatches.contains { $0.id == new.id } }) {
            return L("色に「\(added.name)」と名前を付けた", "Named a colour \"\(added.name)\"")
        }
        for swatch in swatches {
            guard let before = old.swatch(swatch.id) else { continue }
            if before.name != swatch.name {
                return L("色の名前を「\(swatch.name)」にした", "Renamed a colour to \"\(swatch.name)\"")
            }
            if before.color != swatch.color {
                return L("「\(swatch.name)」の色を変えた", "Changed the colour \"\(swatch.name)\"")
            }
        }
        if swatches.count < old.swatches.count {
            return L("色の名前を消した", "Removed a colour name")
        }
        return nil
    }

    /// Every named colour's value.
    var colors: [UUID: RGBA] {
        Dictionary(uniqueKeysWithValues: swatches.map { ($0.id, $0.color) })
    }
}
