import Foundation
import FloorPlanCore

extension Double {
    /// Metros no formato do idioma do aparelho (ex.: `3,42 m`).
    var metersText: String { "\(formatted(.number.precision(.fractionLength(2)))) m" }
    var areaText: String { "\(formatted(.number.precision(.fractionLength(2)))) m²" }
}

extension Opening.Kind {
    var label: String {
        switch self {
        case .door: return "Porta"
        case .window: return "Janela"
        case .opening: return "Abertura"
        }
    }
}

extension ReviewIssue {
    var title: String {
        switch kind {
        case .lowConfidence: return "Baixa confiança"
        case .incompleteEdges: return "Parede incompleta"
        case .curvedWall: return "Parede curva"
        case .openCorner: return "Canto aberto"
        case .orphanOpening: return "Abertura sem parede"
        case .openRoomOutline: return "Contorno do ambiente aberto"
        case .shortWall: return "Parede muito curta descartada"
        case .invalidSurface: return "Superfície inválida"
        case .noWalls: return "Nenhuma parede"
        }
    }

    var detail: String {
        switch kind {
        case .lowConfidence: return "O RoomPlan classificou este elemento com baixa confiança. Confira posição e tipo."
        case .incompleteEdges: return "As extremidades desta parede não foram totalmente escaneadas; o comprimento pode estar errado."
        case .curvedWall: return "Paredes curvas são aproximadas por um segmento reto. Ajuste manualmente se necessário."
        case .openCorner: return "A ponta desta parede não encontra outra parede. Ajuste o canto ou adicione a parede que falta."
        case .orphanOpening: return "Esta porta/janela/abertura não pôde ser associada a uma parede e não aparece na planta."
        case .openRoomOutline: return "As paredes não formam um contorno fechado; o contorno foi estimado a partir do piso."
        case .shortWall: return "Uma superfície de parede com menos de 10 cm foi tratada como ruído."
        case .invalidSurface: return "Uma superfície com dados inválidos foi ignorada."
        case .noWalls: return "A captura não contém paredes. Escaneie novamente."
        }
    }
}
