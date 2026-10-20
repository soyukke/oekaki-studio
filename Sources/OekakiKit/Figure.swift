import CoreGraphics
import Foundation

/// The outline of the face below the round part of the head.
public enum FaceShape: String, Codable, CaseIterable, Identifiable {
    case round
    case egg
    case long
    case pointed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .round: return L("丸", "Round")
        case .egg: return L("たまご", "Egg")
        case .long: return L("面長", "Long")
        case .pointed: return L("逆三角", "Pointed")
        }
    }

    /// How far below the centre of the head the chin is, in head radii.
    var chin: Double {
        switch self {
        case .round: return 1.1
        case .egg: return 1.25
        case .long: return 1.45
        case .pointed: return 1.3
        }
    }

    /// The corner of the jaw on one side, in head radii.
    fileprivate var jaw: (x: Double, y: Double) {
        switch self {
        case .round: return (0.72, -0.82)
        case .egg: return (0.58, -0.95)
        case .long: return (0.6, -1.15)
        case .pointed: return (0.66, -0.72)
        }
    }
}

/// How the limbs are bent. Angles are in degrees.
///
/// Arms and legs are listed left then right as seen on the canvas. For each
/// limb a positive angle points away from the body, so a pose and its mirror
/// image use the same numbers on both sides.
public struct FigurePose: Codable, Equatable {
    /// The lean of the body from upright; positive leans to the right.
    public var torso: Double
    /// The tilt of the head from the line of the body.
    public var neck: Double
    /// The upper arm, from hanging straight down.
    public var upperArm: [Double]
    /// The bend at the elbow.
    public var foreArm: [Double]
    /// The thigh, from straight down.
    public var thigh: [Double]
    /// The bend at the knee.
    public var shin: [Double]

    public init(torso: Double = 0, neck: Double = 0, upperArm: [Double], foreArm: [Double], thigh: [Double], shin: [Double]) {
        self.torso = torso
        self.neck = neck
        self.upperArm = upperArm
        self.foreArm = foreArm
        self.thigh = thigh
        self.shin = shin
    }

    public static let standing = FigurePose(upperArm: [12, 12], foreArm: [8, 8], thigh: [4, 4], shin: [0, 0])
    public static let waving = FigurePose(upperArm: [12, 95], foreArm: [8, 80], thigh: [4, 4], shin: [0, 0])
    public static let peace = FigurePose(neck: -8, upperArm: [12, 22], foreArm: [8, 150], thigh: [4, 4], shin: [0, 0])
    public static let handsOnHips = FigurePose(upperArm: [42, 42], foreArm: [-88, -88], thigh: [7, 7], shin: [0, 0])
    public static let cheering = FigurePose(upperArm: [160, 160], foreArm: [6, 6], thigh: [6, 6], shin: [0, 0])
    public static let tilting = FigurePose(torso: -3, neck: 16, upperArm: [14, 10], foreArm: [-30, 10], thigh: [2, 8], shin: [0, -6])
}

/// A simple jointed doll drawn under the picture, to plan the pose and
/// proportions before sketching. It is a guide only: it is never part of
/// the picture, its export, or what the tools treat as lines.
public struct Figure: Codable, Equatable {
    /// The middle of the hips, where the figure is held to move it, in canvas pixels.
    public var x: Double
    public var y: Double
    /// From the top of the head to the ankles when standing straight, in canvas pixels.
    public var height: Double
    /// How many heads tall the figure is, from 2 (chibi) to 8.
    public var heads: Double = 6
    /// Widths and sizes, 1 being the usual.
    public var shoulders: Double = 1
    /// 0 is flat.
    public var bust: Double = 0.25
    public var hips: Double = 1
    public var legs: Double = 1
    public var face: FaceShape = .egg
    /// Where the face looks: turned right is positive, up is positive. Degrees.
    public var yaw: Double = 0
    public var pitch: Double = 0
    public var pose: FigurePose = .standing
    public var isVisible = true

    public static let headRange: ClosedRange<Double> = 2...8
    public static let shoulderRange: ClosedRange<Double> = 0.6...1.4
    public static let bustRange: ClosedRange<Double> = 0...1
    public static let hipRange: ClosedRange<Double> = 0.6...1.4
    public static let legRange: ClosedRange<Double> = 0.85...1.15
    public static let yawRange: ClosedRange<Double> = -80...80
    public static let pitchRange: ClosedRange<Double> = -40...40

    public init(x: Double, y: Double, height: Double) {
        self.x = x
        self.y = y
        self.height = height
    }

    /// A standing figure filling most of the height of a canvas, in the middle.
    public static func standing(in size: CGSize) -> Figure {
        var figure = Figure(x: size.width / 2, y: 0, height: size.height * 0.8)
        figure.placeTop(at: size.height * 0.1)
        return figure
    }

    /// Moves the figure up or down so the top of the head is at `top`.
    public mutating func placeTop(at top: Double) {
        let joints = self.joints
        y += top - (joints.head.y - joints.headRadius)
    }

    // MARK: Measurements

    /// The head from its top to the chin.
    var headLength: Double { height / heads }
    var headRadius: Double { headLength / (1 + face.chin) }
    /// From the chin to the ankles.
    var bodyLength: Double { height - headLength }
    var neckLength: Double { bodyLength * 0.05 }
    var legLength: Double { bodyLength * 0.58 * legs }
    var torsoLength: Double { bodyLength - neckLength - legLength }
    var upperArmLength: Double { bodyLength * 0.24 }
    var foreArmLength: Double { bodyLength * 0.22 }
    var shoulderHalf: Double { (headLength * 0.3 + bodyLength * 0.07) * shoulders }
    var hipHalf: Double { (headLength * 0.22 + bodyLength * 0.06) * hips }
    var armWidth: Double { headLength * 0.06 + bodyLength * 0.024 }
    var legWidth: Double { headLength * 0.08 + bodyLength * 0.038 }

    // MARK: Joints

    /// Where every joint is, in canvas pixels.
    public struct Joints {
        public var pelvis: CGPoint
        public var chest: CGPoint
        public var neckTop: CGPoint
        public var head: CGPoint
        public var headRadius: Double
        /// The direction the top of the head points, in degrees from upright.
        public var headAngle: Double
        public var shoulder: [CGPoint]
        public var elbow: [CGPoint]
        public var wrist: [CGPoint]
        public var hip: [CGPoint]
        public var knee: [CGPoint]
        public var ankle: [CGPoint]
        public var torsoAngle: Double
        public var foreArmAngle: [Double]
        public var shinAngle: [Double]
    }

    /// The parts that can be held and moved.
    public enum Part: Equatable {
        case pelvis, chest, head
        case elbow(Int), wrist(Int), knee(Int), ankle(Int)
    }

    /// The point `length` away from `from` in the direction `angle`, where 0 is up
    /// and angles grow clockwise on the canvas.
    static func step(_ from: CGPoint, _ angle: Double, _ length: Double) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: from.x + sin(radians) * length, y: from.y - cos(radians) * length)
    }

    static func angle(from: CGPoint, to: CGPoint) -> Double {
        atan2(to.x - from.x, -(to.y - from.y)) * 180 / .pi
    }

    /// Side 0 is the left on the canvas; outward there is a larger angle.
    private static func outward(_ side: Int) -> Double { side == 0 ? 1 : -1 }

    public var joints: Joints {
        let pelvis = CGPoint(x: x, y: y)
        let torso = pose.torso
        let chest = Self.step(pelvis, torso, torsoLength)
        let headAngle = torso + pose.neck
        let neckTop = Self.step(chest, headAngle, neckLength)
        let radius = headRadius
        let head = Self.step(neckTop, headAngle, radius * face.chin)
        // The hips tilt half as much as the body leans.
        let hipLine = torso / 2
        var joints = Joints(
            pelvis: pelvis, chest: chest, neckTop: neckTop, head: head, headRadius: radius, headAngle: headAngle,
            shoulder: [], elbow: [], wrist: [], hip: [], knee: [], ankle: [], torsoAngle: torso, foreArmAngle: [], shinAngle: []
        )
        for side in 0..<2 {
            let out = Self.outward(side)
            let shoulder = Self.step(chest, torso - 90 * out, shoulderHalf)
            let upper = torso + 180 + pose.upperArm[side] * out
            let elbow = Self.step(shoulder, upper, upperArmLength)
            let fore = upper + pose.foreArm[side] * out
            joints.shoulder.append(shoulder)
            joints.elbow.append(elbow)
            joints.wrist.append(Self.step(elbow, fore, foreArmLength))
            joints.foreArmAngle.append(fore)

            let hip = Self.step(pelvis, hipLine - 90 * out, hipHalf * 0.75)
            let thigh = 180 + pose.thigh[side] * out
            let knee = Self.step(hip, thigh, legLength / 2)
            let shin = thigh + pose.shin[side] * out
            joints.hip.append(hip)
            joints.knee.append(knee)
            joints.ankle.append(Self.step(knee, shin, legLength / 2))
            joints.shinAngle.append(shin)
        }
        return joints
    }

    /// Where each part that can be held is.
    public var handles: [(part: Part, point: CGPoint)] {
        let joints = self.joints
        var handles: [(Part, CGPoint)] = [(.head, joints.head), (.chest, joints.chest), (.pelvis, joints.pelvis)]
        for side in 0..<2 {
            handles += [
                (.elbow(side), joints.elbow[side]), (.wrist(side), joints.wrist[side]),
                (.knee(side), joints.knee[side]), (.ankle(side), joints.ankle[side]),
            ]
        }
        return handles
    }

    /// The part held at `point`, if one is within `reach`.
    public func part(at point: CGPoint, reach: Double) -> Part? {
        var best: (part: Part, distance: Double)?
        for handle in handles {
            let distance = Double(hypot(handle.point.x - point.x, handle.point.y - point.y))
            if distance <= reach, distance < (best?.distance ?? .infinity) {
                best = (handle.part, distance)
            }
        }
        return best?.part
    }

    // MARK: Posing

    /// Moves `part` towards `point`, keeping every bone its length.
    /// The hips move the whole figure; `grab` is where they were held from.
    public mutating func move(_ part: Part, to point: CGPoint, grab: CGVector = .zero) {
        let joints = self.joints
        switch part {
        case .pelvis:
            x = point.x - grab.dx
            y = point.y - grab.dy
        case .chest:
            pose.torso = Self.normalized(Self.angle(from: joints.pelvis, to: point))
        case .head:
            pose.neck = Self.normalized(Self.angle(from: joints.chest, to: point) - pose.torso)
        case .elbow(let side):
            let upper = Self.angle(from: joints.shoulder[side], to: point)
            pose.upperArm[side] = Self.normalized((upper - pose.torso - 180) * Self.outward(side))
        case .wrist(let side):
            let (upper, lower) = Self.reach(
                from: joints.shoulder[side], to: point, lengths: (upperArmLength, foreArmLength), bentLike: joints.elbow[side]
            )
            pose.upperArm[side] = Self.normalized((upper - pose.torso - 180) * Self.outward(side))
            pose.foreArm[side] = Self.normalized((lower - upper) * Self.outward(side))
        case .knee(let side):
            let thigh = Self.angle(from: joints.hip[side], to: point)
            pose.thigh[side] = Self.normalized((thigh - 180) * Self.outward(side))
        case .ankle(let side):
            let (thigh, shin) = Self.reach(
                from: joints.hip[side], to: point, lengths: (legLength / 2, legLength / 2), bentLike: joints.knee[side]
            )
            pose.thigh[side] = Self.normalized((thigh - 180) * Self.outward(side))
            pose.shin[side] = Self.normalized((shin - thigh) * Self.outward(side))
        }
    }

    /// Angles for a two-bone limb from `base` whose end reaches `target`, or
    /// points straight at it when it is too far. Of the two ways to bend, the
    /// one with the middle joint nearer where it was is kept.
    static func reach(
        from base: CGPoint, to target: CGPoint, lengths: (Double, Double), bentLike middle: CGPoint
    ) -> (Double, Double) {
        let (a, b) = lengths
        let distance = min(max(hypot(target.x - base.x, target.y - base.y), abs(a - b) + 0.001), a + b - 0.001)
        let toward = angle(from: base, to: target)
        let cosine = (a * a + distance * distance - b * b) / (2 * a * distance)
        let opening = acos(max(-1, min(1, cosine))) * 180 / .pi
        let end = step(base, toward, distance)
        let choices = [toward + opening, toward - opening].map { upper -> (Double, Double, Double) in
            let joint = step(base, upper, a)
            return (upper, angle(from: joint, to: end), hypot(joint.x - middle.x, joint.y - middle.y))
        }
        let chosen = choices[0].2 <= choices[1].2 ? choices[0] : choices[1]
        return (chosen.0, chosen.1)
    }

    /// The same angle within -180...180.
    static func normalized(_ angle: Double) -> Double {
        var value = angle.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value <= -180 { value += 360 }
        return value
    }

    /// Changes the pose, keeping the hips in place.
    public mutating func apply(_ pose: FigurePose) {
        self.pose = pose
    }

    // MARK: Drawing

    /// The guide colour: a light blue that reads as "not part of the picture".
    public static let ink = CGColor(srgbRed: 0.24, green: 0.56, blue: 0.92, alpha: 0.9)
    static let tint = CGColor(srgbRed: 0.24, green: 0.56, blue: 0.92, alpha: 0.07)

    /// Draws the figure into a context whose y axis points down.
    public func draw(in context: CGContext) {
        let joints = self.joints
        let line = max(2, height / 320)
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(line)
        context.setStrokeColor(Self.ink)
        context.setFillColor(Self.tint)

        for side in 0..<2 {
            limb(joints.hip[side], joints.knee[side], joints.ankle[side], width: legWidth, in: context)
            // A foot that points outwards a little.
            let out = Self.outward(side)
            let toe = Self.step(joints.ankle[side], joints.shinAngle[side] + 70 * out, headLength * 0.45)
            capsule([joints.ankle[side], toe], width: legWidth * 0.6, in: context)
        }

        // The body as illustrators block it in: the chest as an upside-down
        // trapezoid, the hips as a trapezoid shaped like shorts, and the waist
        // between them. Each is laid out across and down its own part of the body.
        func frame(_ origin: CGPoint, _ angle: Double) -> (Double, Double) -> CGPoint {
            let radians = angle * .pi / 180
            return { across, down in
                CGPoint(
                    x: origin.x + across * cos(radians) - down * sin(radians),
                    y: origin.y + across * sin(radians) + down * cos(radians)
                )
            }
        }
        let chest = frame(joints.chest, joints.torsoAngle)
        let hips = frame(joints.pelvis, joints.torsoAngle / 2)
        let top = shoulderHalf * 0.95
        let ribs = torsoLength * 0.55
        let ribWidth = shoulderHalf * 0.72
        let chestShape = CGMutablePath()
        chestShape.move(to: chest(-top, 0))
        chestShape.addLine(to: chest(top, 0))
        chestShape.addQuadCurve(to: chest(ribWidth, ribs), control: chest(top, ribs * 0.5))
        chestShape.addQuadCurve(to: chest(-ribWidth, ribs), control: chest(0, ribs * 1.15))
        chestShape.addQuadCurve(to: chest(-top, 0), control: chest(-top, ribs * 0.5))
        chestShape.closeSubpath()
        shape(chestShape, in: context)

        let waist = torsoLength * 0.2
        let hipTop = hipHalf * 0.82
        let hipWide = hipHalf * 1.08
        let crotch = torsoLength * 0.17
        let hipShape = CGMutablePath()
        hipShape.addLines(between: [
            hips(-hipTop, -waist), hips(hipTop, -waist), hips(hipWide, 0),
            hips(hipHalf * 0.22, crotch), hips(-hipHalf * 0.22, crotch), hips(-hipWide, 0),
        ])
        hipShape.closeSubpath()
        shape(hipShape, in: context)

        // The sides of the waist curve in a little between the ribs and the hips.
        let spineMiddle = CGPoint(x: (chest(0, ribs).x + hips(0, -waist).x) / 2, y: (chest(0, ribs).y + hips(0, -waist).y) / 2)
        for sign in [-1.0, 1.0] {
            let from = chest(ribWidth * sign, ribs)
            let to = hips(hipTop * sign, -waist)
            let middle = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            let away = Double(hypot(middle.x - spineMiddle.x, middle.y - spineMiddle.y))
            let pinch = min(ribWidth, hipTop) * 0.85 / max(away, 0.001)
            context.move(to: from)
            context.addQuadCurve(
                to: to,
                control: CGPoint(x: spineMiddle.x + (middle.x - spineMiddle.x) * pinch, y: spineMiddle.y + (middle.y - spineMiddle.y) * pinch)
            )
            context.strokePath()
        }
        // The centre line down the front of the body.
        context.saveGState()
        context.setLineWidth(max(1, line * 0.6))
        context.addLines(between: [chest(0, 0), chest(0, ribs), spineMiddle, hips(0, crotch)])
        context.strokePath()
        context.restoreGState()

        if bust > 0.02 {
            // The underside of each breast, as a curve on the chest.
            let size = min(shoulderHalf * (0.16 + bust * 0.3), torsoLength * (0.08 + bust * 0.14))
            for sign in [-1.0, 1.0] {
                let center = (shoulderHalf * 0.45 * sign, torsoLength * 0.3)
                context.addLines(between: stride(from: 10.0, through: 170, by: 10).map { degrees in
                    let radians = degrees * .pi / 180
                    return chest(center.0 + size * cos(radians), center.1 + size * sin(radians))
                })
                context.strokePath()
            }
        }

        capsule([joints.chest, joints.neckTop], width: armWidth * 1.1, in: context)
        for side in 0..<2 {
            limb(joints.shoulder[side], joints.elbow[side], joints.wrist[side], width: armWidth, in: context)
            let hand = Self.step(joints.wrist[side], joints.foreArmAngle[side], headLength * 0.18)
            ellipse(center: hand, radii: (headLength * 0.12, headLength * 0.18), angle: joints.foreArmAngle[side], in: context)
        }

        drawHead(in: context, center: joints.head, radius: joints.headRadius, roll: joints.headAngle)
        context.restoreGState()
    }

    /// The head on its own: a ball with the centre line and eye line on it,
    /// and the jaw of the chosen face shape. The y axis points down.
    public func drawHead(in context: CGContext, center: CGPoint, radius: Double, roll: Double = 0) {
        let yaw = self.yaw * .pi / 180
        let pitch = self.pitch * .pi / 180
        let roll = roll * .pi / 180
        // Head space: x to the right, y up, z towards the viewer.
        func place(_ x: Double, _ y: Double, _ z: Double) -> (point: CGPoint, depth: Double) {
            let y1 = y * cos(pitch) + z * sin(pitch)
            let z1 = -y * sin(pitch) + z * cos(pitch)
            let x2 = x * cos(yaw) + z1 * sin(yaw)
            let z2 = -x * sin(yaw) + z1 * cos(yaw)
            let dx = x2 * radius
            let dy = -y1 * radius
            return (CGPoint(x: center.x + dx * cos(roll) - dy * sin(roll), y: center.y + dx * sin(roll) + dy * cos(roll)), z2)
        }
        /// Strokes only the parts that face the viewer.
        func trace(_ points: [(point: CGPoint, depth: Double)]) {
            var drawing = false
            for item in points {
                if item.depth < -0.02 {
                    drawing = false
                } else if drawing {
                    context.addLine(to: item.point)
                } else {
                    context.move(to: item.point)
                    drawing = true
                }
            }
            context.strokePath()
        }

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(max(1.5, radius / 40))
        context.setStrokeColor(Self.ink)
        context.setFillColor(Self.tint)
        let ball = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fillEllipse(in: ball)
        context.strokeEllipse(in: ball)

        let steps = 48
        // The eye line, a little below the middle of the ball.
        let eye = -0.12
        let ring = (1 - eye * eye).squareRoot()
        trace((0...steps).map { index in
            let t: Double = Double(index) / Double(steps) * 2 * .pi
            return place(ring * sin(t), eye, ring * cos(t))
        })
        // The centre line, over the top of the head and down the front to the chin.
        let chin = face.chin
        var middle = (0...steps).map { index -> (point: CGPoint, depth: Double) in
            let sweep: Double = .pi / 2 + 0.35
            let t: Double = .pi / 2 - Double(index) / Double(steps) * sweep
            return place(0, sin(t), cos(t))
        }
        middle.append(place(0, -chin, 0.42))
        trace(middle)

        // The ears, on the sides of the head between the eye line and the
        // bottom of the ball, drawn only on a side that can be seen.
        for side in [-1.0, 1.0] {
            let ear = (0...24).map { index -> (point: CGPoint, depth: Double) in
                let t: Double = Double(index) / 24 * 2 * .pi
                let spot = place(side * 0.97, -0.3 + 0.2 * sin(t), -0.08 + 0.12 * cos(t))
                // Drawn once the head has turned enough to show that side;
                // from the front an ear is only a sliver at the edge.
                return (spot.point, place(side, 0, 0).depth - 0.25)
            }
            trace(ear)
        }

        // The outline of the face: one line from a side of the ball, round the
        // chin, to the other side, whichever way the head turns. Each end
        // starts on the edge of the ball so the line joins it.
        let jaw = face.jaw
        func onEdge(_ point: CGPoint) -> CGPoint {
            let dx = Double(point.x - center.x)
            let dy = Double(point.y - center.y)
            let length = max((dx * dx + dy * dy).squareRoot(), 0.001)
            return CGPoint(x: center.x + dx / length * radius, y: center.y + dy / length * radius)
        }
        // Each side runs from the cheek to the chin. A side turned away
        // starts on the edge of the ball, where the cheek is last seen.
        let chinPoint = place(0, -chin, 0.42).point
        var sides: [[CGPoint]] = []
        for side in [-1.0, 1.0] {
            let cheek = place(side * 0.95, -0.2, 0.1).point
            let start = place(side, 0, 0).depth < -0.05 ? onEdge(cheek) : cheek
            let corner = place(side * jaw.x, jaw.y, 0.38)
            // A jaw corner turned behind the chin is hidden; the line then runs straight to the chin.
            sides.append(corner.depth > -0.05 ? [start, corner.point, chinPoint] : [start, chinPoint])
        }
        // A pointed chin is a corner; the other shapes pass round it in one curve.
        let lines = face == .pointed ? sides : [sides[0] + sides[1].reversed().dropFirst()]
        for points in lines {
            let curve = Self.smoothCurve(through: points.map { (Double($0.x), Double($0.y), 0) })
            context.addLines(between: curve.map { CGPoint(x: $0.0, y: $0.1) })
            context.strokePath()
        }
        context.restoreGState()
    }

    /// A Catmull-Rom curve through the points, ten samples per span.
    private static func smoothCurve(through points: [(Double, Double, Double)]) -> [(Double, Double, Double)] {
        guard points.count > 1 else { return points }
        var result: [(Double, Double, Double)] = []
        for index in 0..<points.count - 1 {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            for sample in 0..<10 {
                let t = Double(sample) / 10
                func blend(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                    let linear: Double = (c - a) * t
                    let square: Double = (2 * a - 5 * b + 4 * c - d) * t * t
                    let cube: Double = (3 * b - a - 3 * c + d) * t * t * t
                    return 0.5 * (2 * b + linear + square + cube)
                }
                result.append((blend(p0.0, p1.0, p2.0, p3.0), blend(p0.1, p1.1, p2.1, p3.1), blend(p0.2, p1.2, p2.2, p3.2)))
            }
        }
        result.append(points[points.count - 1])
        return result
    }

    private func limb(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, width: Double, in context: CGContext) {
        capsule([a, b], width: width, in: context)
        capsule([b, c], width: width * 0.85, in: context)
    }

    /// A rounded bar along the points, outlined and lightly filled.
    private func capsule(_ points: [CGPoint], width: Double, in context: CGContext) {
        let spine = CGMutablePath()
        spine.addLines(between: points)
        let outline = spine.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
        context.addPath(outline)
        context.fillPath()
        context.addPath(outline)
        context.strokePath()
    }

    private func shape(_ path: CGPath, in context: CGContext) {
        context.addPath(path)
        context.fillPath()
        context.addPath(path)
        context.strokePath()
    }

    private func ellipse(center: CGPoint, radii: (Double, Double), angle: Double, in context: CGContext) {
        var transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle * .pi / 180)
        let path = CGPath(
            ellipseIn: CGRect(x: -radii.0, y: -radii.1, width: radii.0 * 2, height: radii.1 * 2), transform: &transform
        )
        context.addPath(path)
        context.fillPath()
        context.addPath(path)
        context.strokePath()
    }
}
