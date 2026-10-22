import Foundation

/// Ponto 2D em metros, no sistema de coordenadas da planta.
///
/// Planta: `x = X do mundo ARKit`, `y = Z do mundo ARKit`, vista de cima, sem espelhamento.
/// O eixo `y` aponta para baixo na tela (compatível com SVG).
public struct Point2D: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2D(x: 0, y: 0)

    public static func + (a: Point2D, b: Point2D) -> Point2D { Point2D(x: a.x + b.x, y: a.y + b.y) }
    public static func - (a: Point2D, b: Point2D) -> Point2D { Point2D(x: a.x - b.x, y: a.y - b.y) }
    public static func * (a: Point2D, k: Double) -> Point2D { Point2D(x: a.x * k, y: a.y * k) }

    public var length: Double { (x * x + y * y).squareRoot() }

    public var normalized: Point2D {
        let l = length
        return l > 1e-12 ? Point2D(x: x / l, y: y / l) : .zero
    }

    public func dot(_ o: Point2D) -> Double { x * o.x + y * o.y }
    public func cross(_ o: Point2D) -> Double { x * o.y - y * o.x }
    public func distance(to o: Point2D) -> Double { (self - o).length }

    /// Vetor perpendicular (rotação de +90° no sistema com y para baixo).
    public var perpendicular: Point2D { Point2D(x: -y, y: x) }
}

/// Transformação rígida 2D (rotação em radianos + translação). Usada para posicionar
/// uma captura na planta do projeto (identidade na versão 1: uma captura por projeto).
public struct Transform2D: Codable, Equatable, Sendable {
    public var rotation: Double
    public var translation: Point2D

    public init(rotation: Double = 0, translation: Point2D = .zero) {
        self.rotation = rotation
        self.translation = translation
    }

    public static let identity = Transform2D()

    public func apply(_ p: Point2D) -> Point2D {
        let c = cos(rotation), s = sin(rotation)
        return Point2D(x: c * p.x - s * p.y + translation.x, y: s * p.x + c * p.y + translation.y)
    }

    /// Aplica só a parte rotacional (para direções).
    public func applyDirection(_ d: Point2D) -> Point2D {
        let c = cos(rotation), s = sin(rotation)
        return Point2D(x: c * d.x - s * d.y, y: s * d.x + c * d.y)
    }
}

public struct Bounds2D: Codable, Equatable, Sendable {
    public var min: Point2D
    public var max: Point2D

    public init(min: Point2D, max: Point2D) {
        self.min = min
        self.max = max
    }

    public var width: Double { max.x - min.x }
    public var height: Double { max.y - min.y }
    public var center: Point2D { Point2D(x: (min.x + max.x) / 2, y: (min.y + max.y) / 2) }

    public init?(points: [Point2D]) {
        guard let first = points.first else { return nil }
        var lo = first, hi = first
        for p in points {
            lo.x = Swift.min(lo.x, p.x); lo.y = Swift.min(lo.y, p.y)
            hi.x = Swift.max(hi.x, p.x); hi.y = Swift.max(hi.y, p.y)
        }
        self.init(min: lo, max: hi)
    }

    public func union(_ o: Bounds2D) -> Bounds2D {
        Bounds2D(min: Point2D(x: Swift.min(min.x, o.min.x), y: Swift.min(min.y, o.min.y)),
                 max: Point2D(x: Swift.max(max.x, o.max.x), y: Swift.max(max.y, o.max.y)))
    }
}

public enum Geometry {
    /// Área com sinal (fórmula do cadarço).
    public static func signedArea(_ poly: [Point2D]) -> Double {
        guard poly.count >= 3 else { return 0 }
        var sum = 0.0
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    /// Distância de um ponto a um segmento e o parâmetro (0...1) do ponto mais próximo.
    public static func distance(from p: Point2D, toSegment a: Point2D, _ b: Point2D) -> (distance: Double, t: Double) {
        let ab = b - a
        let len2 = ab.dot(ab)
        guard len2 > 1e-18 else { return (p.distance(to: a), 0) }
        let t = Swift.max(0, Swift.min(1, (p - a).dot(ab) / len2))
        return (p.distance(to: a + ab * t), t)
    }

    /// Fecho convexo (monotone chain). Retorna em ordem anti-horária no sistema matemático.
    public static func convexHull(_ points: [Point2D]) -> [Point2D] {
        let pts = Array(Set(points)).sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard pts.count > 2 else { return pts }
        func turn(_ o: Point2D, _ a: Point2D, _ b: Point2D) -> Double { (a - o).cross(b - o) }
        var lower: [Point2D] = []
        for p in pts {
            while lower.count >= 2 && turn(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [Point2D] = []
        for p in pts.reversed() {
            while upper.count >= 2 && turn(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }
}
