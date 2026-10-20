import CoreGraphics
import Foundation
import OekakiKit

/// The family restaurant behind her, in canvas units: a big window behind her
/// head with a summer day outside, the wall and a lamp on the left, the high
/// back of the booth behind her shoulders, the table in front with a float on it.
/// Painted without lines and then blurred, so it sits far behind her.
enum Room {
    static let windowLeft: CGFloat = 380
    static let mullion: CGFloat = 700
    static let transom: CGFloat = 150
    static let sill: CGFloat = 612
    static let boothTop: CGFloat = 640
    static let tableEdge = "M -20 1092 C 300 1084, 700 1082, 1020 1090"
    static let lamp = CGPoint(x: 170, y: 190)

    static var roughLines: [String] {
        [
            "M \(windowLeft) -10 L \(windowLeft) \(sill)", "M \(mullion) -10 L \(mullion) \(sill)",
            "M \(windowLeft) \(transom) L 1010 \(transom)",
            "M -20 \(boothTop) C 300 \(boothTop - 12), 700 \(boothTop - 12), 1020 \(boothTop)",
            tableEdge, "M 40 880 L 56 1166 L 176 1166 L 192 880",
        ]
    }

    static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> String {
        "M \(x) \(y) L \(x + w) \(y) L \(x + w) \(y + h) L \(x) \(y + h) Z"
    }

    /// Outside: the sky, pale and bright toward the sun, trees in full leaf.
    static func outside(_ a: Artist, _ c: Bite.Colors) {
        a.gradient(.linear, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 420), c.skyTop, c.skyLow)
        var sun = c.sun
        sun.a = 0
        a.gradient(.radial, from: CGPoint(x: 860, y: 90), to: CGPoint(x: 860 + 520, y: 90), c.glow, sun)
        // Trees across the street, in soft round masses.
        var random = SplitMix(seed: 21)
        // Shade inside the trees first, then their sunlit tops.
        for _ in 0..<26 {
            let x = windowLeft - 20 + random.next() * 660
            let y = 400 + random.next() * 220
            let r = 46 + random.next() * 60
            a.shape(PathData.arc(center: CGPoint(x: x, y: y), rx: r, ry: r * 0.86, from: 0, to: 360, spacing: 3), c.treeShade.mixed(with: c.treeShade.mixed(with: RGBA(hex: 0x203A30), 0.5), 0.4 * random.next()))
        }
        for _ in 0..<22 {
            let x = windowLeft - 20 + random.next() * 660
            let y = 350 + random.next() * 160
            let r = 30 + random.next() * 44
            a.shape(PathData.arc(center: CGPoint(x: x, y: y), rx: r, ry: r * 0.86, from: 0, to: 360, spacing: 3), c.treeLight.mixed(with: c.skyLow, 0.35 * random.next()))
        }
        if c.night {
            // The town's lights through the leaves.
            for index in 0..<36 {
                let x = windowLeft + random.next() * 630
                let y = 300 + random.next() * 300
                let r = 3 + random.next() * 7
                let tone = [RGBA(hex: 0xFFD27A), RGBA(hex: 0xFFF0C8), RGBA(hex: 0xFF9A7A), RGBA(hex: 0x9AD8FF)][index % 4]
                a.shape(PathData.arc(center: CGPoint(x: x, y: y), rx: r, ry: r, from: 0, to: 360, spacing: 1), tone)
            }
        }
        // A pale building far off, and the light flooding over everything.
        a.shape(rect(windowLeft, 300, 200, 160), RGBA(hex: 0xF4EFE6))
        a.shape(rect(windowLeft + 26, 330, 40, 30), RGBA(hex: 0xD9E6EE))
        a.shape(rect(windowLeft + 100, 330, 40, 30), RGBA(hex: 0xD9E6EE))
    }

    /// The room: the wall and window frame, the lamp, the booth behind her.
    static func room(_ a: Artist, _ c: Bite.Colors) {
        // The wall, left of the window and under the sill.
        a.shape("M -20 -20 L \(windowLeft) -20 L \(windowLeft) \(sill) L 1020 \(sill) L 1020 1270 L -20 1270 Z", c.wall)
        // The window frame: posts, a bar across the top panes, the sill.
        let frame = RGBA(hex: 0xFFFBF4)
        a.shape(rect(windowLeft - 14, -20, 26, sill + 20), frame)
        a.shape(rect(mullion - 10, -20, 20, sill + 20), frame)
        a.shape(rect(windowLeft, transom - 8, 640, 16), frame)
        a.shape(rect(windowLeft - 20, sill - 12, 660, 28), frame)
        // Wainscot on the wall under the lamp.
        a.shape(rect(-20, 470, windowLeft, 160), c.wood.mixed(with: c.wall, 0.45))
        a.shape(rect(-20, 462, windowLeft, 12), c.wood)
        // The lamp hanging on its cord.
        a.shape(rect(lamp.x - 2, -20, 4, lamp.y - 40), RGBA(hex: 0x5A4A44))
        a.shape("M \(lamp.x - 78) \(lamp.y + 22) C \(lamp.x - 70) \(lamp.y - 40), \(lamp.x - 30) \(lamp.y - 62), \(lamp.x) \(lamp.y - 62) C \(lamp.x + 30) \(lamp.y - 62), \(lamp.x + 70) \(lamp.y - 40), \(lamp.x + 78) \(lamp.y + 22) Z", c.wood.mixed(with: RGBA(hex: 0x2E2420), 0.3))
        a.shape(PathData.arc(center: CGPoint(x: lamp.x, y: lamp.y + 22), rx: 78, ry: 14, from: 0, to: 360, spacing: 2), c.lamp)
        // A menu board on the wall.
        a.shape(rect(30, 250, 150, 190), RGBA(hex: 0x3C4A3E))
        a.shape(rect(38, 258, 134, 174), RGBA(hex: 0x4E6152))
        for row in 0..<5 {
            a.shape(rect(52, 280 + CGFloat(row) * 30, 70 + CGFloat(row % 2) * 30, 6), RGBA(hex: 0xF2EEE2).withAlpha(0.8))
        }
        // The booth's high back, behind her: deep red, padded in long rolls.
        a.shape("M -20 \(boothTop) C 300 \(boothTop - 12), 700 \(boothTop - 12), 1020 \(boothTop) L 1020 1270 L -20 1270 Z", c.booth)
        a.shape("M -20 \(boothTop - 22) C 300 \(boothTop - 34), 700 \(boothTop - 34), 1020 \(boothTop - 22) L 1020 \(boothTop) C 700 \(boothTop - 12), 300 \(boothTop - 12), -20 \(boothTop) Z", c.wood)
        for x in stride(from: 40, through: 980, by: 118) as StrideThrough<CGFloat> {
            a.ribbon("M \(x) \(boothTop + 6) C \(x - 4) 800, \(x - 2) 1000, \(x + 4) 1270", c.boothShade, width: Ribbon.between(6, 10))
        }
        // Plants along the sill, left and right of her.
        let leaf = c.leaves.mixed(with: RGBA(hex: 0x3E7A52), 0.4)
        for (x, flip) in [(410.0, -1.0), (930.0, 1.0)] as [(CGFloat, CGFloat)] {
            a.shape(rect(x - 34, sill - 70, 68, 60), RGBA(hex: 0xEDE6DA))
            for k in 0..<7 {
                let angle = (-150 + CGFloat(k) * 20) * .pi / 180
                let tip = CGPoint(x: x + cos(angle) * 110 * flip, y: sill - 70 + sin(angle) * 110)
                a.ribbon("M \(x) \(sill - 66) Q \(x + (tip.x - x) * 0.4) \(tip.y + 30), \(tip.x) \(tip.y)", leaf, width: Ribbon.leaf(22))
            }
        }
    }

    static func shading(_ a: Artist, _ c: Bite.Colors) {
        // The room is dimmer than the day outside; darker low down and away from the window.
        var clear = c.wallShade
        clear.a = 0
        a.gradient(.linear, from: CGPoint(x: 900, y: 300), to: CGPoint(x: 0, y: 900), clear, c.wallShade)
        a.shape("M -20 \(boothTop) C 300 \(boothTop - 12), 700 \(boothTop - 12), 1020 \(boothTop) L 1020 \(boothTop + 40) C 700 \(boothTop + 28), 300 \(boothTop + 28), -20 \(boothTop + 40) Z", c.boothShade.over(c.booth))
        // Her own shadow on the booth behind her.
        a.line("M 300 700 C 340 820, 380 960, 400 1270", Pen(width: 360, color: c.boothShade.over(c.booth), start: 0.05, end: 0.05, floor: 1, opacity: 0.6, softness: 1))
    }

    static func lights(_ a: Artist, _ c: Bite.Colors) {
        // A little haze over the whole room, so it sits back behind her.
        a.shape(rect(-20, -20, 1040, 1290), c.glow.withAlpha(0.16))
        // The lamp's warm pool on the wall, and the window's light along the sill and the booth's edge.
        var clear = c.lamp
        clear.a = 0
        a.gradient(.radial, from: CGPoint(x: lamp.x, y: lamp.y + 40), to: CGPoint(x: lamp.x + 300, y: lamp.y + 40), c.lamp.withAlpha(0.7), clear)
        a.line("M \(windowLeft) \(sill + 4) L 1010 \(sill + 4)", Pen(width: 10, color: c.glow, start: 0.1, end: 0.1, floor: 1, opacity: 0.9, softness: 0.6))
        a.line("M 600 \(boothTop - 22) C 760 \(boothTop - 30), 900 \(boothTop - 30), 1010 \(boothTop - 22)", Pen(width: 8, color: c.glow, start: 0.4, end: 0.1, floor: 0.3, opacity: 0.9))
    }

    /// Round lights out of focus, in the window and round the lamp.
    static func bokeh(_ a: Artist, _ c: Bite.Colors) {
        var random = SplitMix(seed: 33)
        for index in 0..<14 {
            let x = windowLeft + 40 + random.next() * 560
            let y = 260 + random.next() * 330
            let r = 10 + random.next() * 26
            // Sun through leaves: warm white, some a little green.
            let tone = index % 3 == 0 ? c.leaves.mixed(with: c.glow, 0.6) : c.glow
            a.shape(PathData.arc(center: CGPoint(x: x, y: y), rx: r, ry: r, from: 0, to: 360, spacing: 2), tone.withAlpha(0.12 + 0.16 * random.next()))
        }
        // The lamp's bulb, round and soft.
        for (dx, dy, r) in [(0.0, 26.0, 26.0), (-40, 40, 12), (44, 44, 10)] as [(CGFloat, CGFloat, CGFloat)] {
            a.shape(PathData.arc(center: CGPoint(x: lamp.x + dx, y: lamp.y + dy), rx: r, ry: r, from: 0, to: 360, spacing: 2), c.lamp.withAlpha(0.35))
        }
    }

    // MARK: The table and the float on it

    /// The tumbler: round at the rim and the foot, narrowing to the foot.
    static let glass = "M 36 896 C 42 980, 50 1060, 58 1146 C 80 1158, 152 1158, 174 1146 C 182 1060, 190 980, 196 896"
    static let rim = "M 36 896 C 50 882, 182 882, 196 896 C 182 910, 50 910, 36 896 Z"

    static func table(_ a: Artist, _ c: Bite.Colors) {
        // The table's top, seen from a little above, running back to her.
        a.shape("M -20 1092 C 300 1084, 700 1082, 1020 1090 L 1020 1270 L -20 1270 Z", c.table)
        a.shape("M -20 1084 C 300 1076, 700 1074, 1020 1082 L 1020 1094 C 700 1086, 300 1088, -20 1096 Z", c.wood.mixed(with: c.table, 0.35))
        // The float: green soda, a scoop of vanilla, a cherry, a straw.
        a.shape(PathData.join([glass, "M 196 896 C 182 910, 50 910, 36 896"]) + " Z", c.soda.mixed(with: c.wall, 0.25).withAlpha(0.92))
        a.shape("M 44 898 C 38 856, 78 828, 116 830 C 156 828, 194 854, 188 898 C 158 912, 74 912, 44 898 Z", RGBA(hex: 0xFFF8EC))
        a.ribbon("M 158 1030 L 180 766", RGBA(hex: 0xF25A6A), width: { _ in 10 })
        a.shape(PathData.arc(center: CGPoint(x: 90, y: 824), rx: 15, ry: 15, from: 0, to: 360, spacing: 1), RGBA(hex: 0xE23A4A))
        a.ribbon("M 94 812 Q 102 786, 120 776", RGBA(hex: 0x5A6A3A), width: { _ in 2.4 })
        // The dish she took the bite from, at the back of the table: a stemmed
        // glass coupe of mint chip with a spoonful gone from its top.
        a.shape("M 676 1150 L 704 1150 L 700 1136 L 680 1136 Z", RGBA(hex: 0xEAF2F4).withAlpha(0.9))
        a.shape(PathData.arc(center: CGPoint(x: 690, y: 1151), rx: 30, ry: 6, from: 0, to: 360, spacing: 1), RGBA(hex: 0xF2F8FA))
        a.shape("M 640 1102 C 646 1122, 666 1136, 690 1136 C 714 1136, 734 1122, 740 1102 Z", RGBA(hex: 0xE8F2F4).withAlpha(0.9))
        a.shape("M 646 1102 C 646 1078, 668 1062, 690 1062 C 714 1062, 736 1078, 734 1102 C 712 1110, 668 1110, 646 1102 Z", c.cream)
        a.shape("M 668 1076 C 678 1068, 702 1068, 712 1076 C 704 1084, 676 1084, 668 1076 Z", c.creamShade.mixed(with: c.cream, 0.4))
        for (x, y) in [(660.0, 1092.0), (686, 1088), (712, 1094), (724, 1082), (698, 1100)] as [(CGFloat, CGFloat)] {
            a.shape("M \(x - 4) \(y) L \(x - 1) \(y - 2) L \(x + 4) \(y - 1) L \(x + 1) \(y + 1.5) Z", c.chip)
        }
        a.shape(PathData.arc(center: CGPoint(x: 690, y: 1102), rx: 50, ry: 8, from: 0, to: 180, spacing: 1), RGBA(hex: 0xF4FAFB).withAlpha(0.8))
        // The call button every table has, by the soda: a little white box, a round button set in its top.
        a.shape("M 212 1112 L 276 1112 C 280 1112, 282 1115, 282 1119 L 282 1132 C 282 1136, 280 1139, 276 1139 L 212 1139 C 208 1139, 206 1136, 206 1132 L 206 1119 C 206 1115, 208 1112, 212 1112 Z", RGBA(hex: 0xE6E0D8))
        a.shape("M 214 1100 L 274 1100 C 280 1100, 283 1105, 282 1112 L 206 1112 C 205 1105, 208 1100, 214 1100 Z", RGBA(hex: 0xFBF8F3))
        a.shape(PathData.arc(center: CGPoint(x: 244, y: 1106), rx: 15, ry: 4.2, from: 0, to: 360, spacing: 1), RGBA(hex: 0xF0654C))
    }

    static func tableShading(_ a: Artist, _ c: Bite.Colors) {
        // The glass is lit from behind: bright along its right side, bubbles rising.
        a.ribbon("M 186 910 C 182 1000, 178 1090, 172 1160", RGBA(hex: 0xFFFFFF).withAlpha(0.8), width: Ribbon.leaf(8))
        a.ribbon("M 56 920 C 60 1000, 64 1080, 70 1150", RGBA(hex: 0xFFFFFF).withAlpha(0.5), width: Ribbon.leaf(5))
        var random = SplitMix(seed: 8)
        for _ in 0..<16 {
            let x = 70 + random.next() * 100, y = 930 + random.next() * 220
            a.shape(PathData.arc(center: CGPoint(x: x, y: y), rx: 2 + random.next() * 3, ry: 2 + random.next() * 3, from: 0, to: 360, spacing: 1), RGBA(hex: 0xFFFFFF).withAlpha(0.85))
        }
        // The glass's foot, round on the table; its shadow, and hers, falling toward the viewer.
        a.line("M 58 1146 C 80 1162, 152 1162, 174 1146", Pen(width: 3, color: RGBA(hex: 0xFFFFFF).withAlpha(0.8), start: 0.2, end: 0.2, floor: 0.4))
        a.line("M 54 1150 C 80 1164, 152 1164, 196 1154", Pen(width: 16, color: c.tableShade, start: 0.2, end: 0.2, floor: 0.4, opacity: 0.9, softness: 1))
        a.line("M 200 1110 C 450 1104, 700 1102, 960 1110", Pen(width: 44, color: c.tableShade, start: 0.2, end: 0.2, floor: 0.4, opacity: 0.6, softness: 1))
        // The window, a long bright gleam on the table, and the soda's green in it.
        a.line("M 640 1130 C 720 1140, 800 1150, 860 1160", Pen(width: 22, color: RGBA(hex: 0xFFFFFF), start: 0.3, end: 0.3, floor: 0.2, opacity: 0.5, softness: 1))
        a.line("M 116 1164 L 116 1230", Pen(width: 70, color: c.soda, start: 0.1, end: 0.6, floor: 0.2, opacity: 0.22, softness: 1))
        // Where her elbow rests, tight and dark, and her forearm's shadow
        // falling away from the window, toward the viewer and to the left.
        let contact = RGBA(hex: 0xA8978F)
        a.line("M 884 1198 C 912 1208, 958 1208, 988 1196", Pen(width: 12, color: contact, start: 0.25, end: 0.25, floor: 0.3, opacity: 0.9, softness: 0.7))
        a.line("M 930 1206 C 900 1222, 868 1236, 826 1246", Pen(width: 40, color: c.tableShade, start: 0.2, end: 0.5, floor: 0.2, opacity: 0.5, softness: 1))
        // The coupe: the window caught in its glass, its shadow to the left.
        a.line("M 734 1104 C 730 1118, 722 1128, 712 1134", Pen(width: 3, color: RGBA(hex: 0xFFFFFF), start: 0.3, end: 0.3, floor: 0.2, opacity: 0.8))
        a.line("M 668 1154 C 650 1160, 630 1164, 610 1166", Pen(width: 12, color: c.tableShade, start: 0.2, end: 0.5, floor: 0.3, opacity: 0.6, softness: 1))
        // The call button: its shadow to the left, light on its top.
        a.line("M 206 1138 C 190 1142, 176 1144, 160 1146", Pen(width: 8, color: contact, start: 0.2, end: 0.5, floor: 0.3, opacity: 0.6, softness: 1))
        a.shape(PathData.arc(center: CGPoint(x: 248, y: 1104), rx: 6, ry: 1.6, from: 0, to: 360, spacing: 0.6), RGBA(hex: 0xFFD8C8))
    }
}
