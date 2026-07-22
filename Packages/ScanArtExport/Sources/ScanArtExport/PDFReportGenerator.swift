import UIKit
import CoreImage
import ScanArtAlgorithms
import ScanArtCore

/// Everything the report needs, gathered up-front so the generator itself
/// has no dependency on SwiftData / the persistence layer — callers (the
/// Reports feature) assemble this from a `Project` + `ScanRecord` +
/// `ThicknessResult` + computed `ThicknessStatistics`.
public struct ReportContent {
    public let project: Project
    public let scan: ScanRecord
    public let statistics: ThicknessStatistics
    public let volumeCubicMeters: Double
    public let colorMapper: ThicknessColorMapper
    public let companyLogo: UIImage?
    public let photos: [UIImage]
    public let signatureImage: UIImage?

    public init(
        project: Project,
        scan: ScanRecord,
        statistics: ThicknessStatistics,
        volumeCubicMeters: Double,
        colorMapper: ThicknessColorMapper,
        companyLogo: UIImage? = nil,
        photos: [UIImage] = [],
        signatureImage: UIImage? = nil
    ) {
        self.project = project
        self.scan = scan
        self.statistics = statistics
        self.volumeCubicMeters = volumeCubicMeters
        self.colorMapper = colorMapper
        self.companyLogo = companyLogo
        self.photos = photos
        self.signatureImage = signatureImage
    }
}

public enum PDFReportGenerator {
    private static let pageSize = CGSize(width: 612, height: 792) // US Letter, 72dpi
    private static let margin: CGFloat = 48

    public static func generate(_ content: ReportContent, to url: URL) throws {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Plaster Thickness Report — \(content.project.name)",
            kCGPDFContextCreator as String: "Scan Art"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)

        let data = renderer.pdfData { context in
            drawTitlePage(context: context, content: content)
            drawStatisticsPage(context: context, content: content)
            drawLegendPage(context: context, content: content)
            if !content.photos.isEmpty {
                drawPhotosPage(context: context, content: content)
            }
            drawSignOffPage(context: context, content: content)
        }
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Page 1: Title

    private static func drawTitlePage(context: UIGraphicsPDFRendererContext, content: ReportContent) {
        context.beginPage()
        var y = margin

        if let logo = content.companyLogo {
            let logoSize = CGSize(width: 80, height: 80 * logo.size.height / max(logo.size.width, 1))
            logo.draw(in: CGRect(origin: CGPoint(x: pageSize.width - margin - logoSize.width, y: margin), size: logoSize))
        }

        y = drawText("Plaster Thickness Report", at: CGPoint(x: margin, y: y), font: .boldSystemFont(ofSize: 26), color: .black)
        y = drawText(content.project.name, at: CGPoint(x: margin, y: y + 6), font: .systemFont(ofSize: 18), color: .darkGray)
        y += 24

        let unit = content.project.unit
        let rows: [(String, String)] = [
            ("Customer", content.project.customerName),
            ("Site", content.project.siteName),
            ("Building", content.project.buildingName),
            ("Room", content.project.roomName),
            ("Floor", content.project.floorNumber),
            ("Engineer", content.project.engineerName),
            ("Scan", content.scan.displayName),
            ("Date", DateFormatter.reportDate.string(from: content.scan.dateCreated)),
            ("Desired Thickness", unit.format(mm: content.project.desiredThicknessMM)),
            ("Tolerance", "± " + unit.format(mm: content.project.toleranceMM))
        ]
        for (label, value) in rows where !value.isEmpty {
            y = drawKeyValueRow(label: label, value: value, at: y)
        }

        if !content.project.notes.isEmpty {
            y += 16
            y = drawText("Notes", at: CGPoint(x: margin, y: y), font: .boldSystemFont(ofSize: 13), color: .black)
            y = drawWrappedText(content.project.notes, at: CGPoint(x: margin, y: y + 4), width: pageSize.width - margin * 2, font: .systemFont(ofSize: 11), color: .darkGray)
        }
    }

    // MARK: - Page 2: Statistics

    private static func drawStatisticsPage(context: UIGraphicsPDFRendererContext, content: ReportContent) {
        context.beginPage()
        var y = margin
        y = drawText("Measurement Summary", at: CGPoint(x: margin, y: y), font: .boldSystemFont(ofSize: 20), color: .black)
        y += 16

        let unit = content.project.unit
        let stats = content.statistics
        let volumeUnit = VolumeUnit.cubicMeters
        let rows: [(String, String)] = [
            ("Average Thickness", unit.format(mm: stats.averageMM, decimals: 2)),
            ("Minimum Thickness", unit.format(mm: stats.minimumMM, decimals: 2)),
            ("Maximum Thickness", unit.format(mm: stats.maximumMM, decimals: 2)),
            ("Median Thickness", unit.format(mm: stats.medianMM, decimals: 2)),
            ("Standard Deviation", unit.format(mm: stats.standardDeviationMM, decimals: 2)),
            ("Surface Area", String(format: "%.2f m²", content.scan.surfaceAreaSquareMeters)),
            ("Plaster Volume", String(format: "%.4f %@", volumeUnit.convert(fromCubicMeters: content.volumeCubicMeters), volumeUnit.symbol)),
            ("Coverage", String(format: "%.1f%%", stats.coveragePercent)),
            ("Within Tolerance", String(format: "%.1f%%", stats.withinTolerancePercent)),
            ("Out of Tolerance", String(format: "%.1f%%", stats.outOfTolerancePercent))
        ]
        for (label, value) in rows {
            y = drawKeyValueRow(label: label, value: value, at: y)
        }

        y += 20
        y = drawText("Thickness Distribution", at: CGPoint(x: margin, y: y), font: .boldSystemFont(ofSize: 14), color: .black)
        drawHistogram(stats.histogram, at: CGPoint(x: margin, y: y + 10), size: CGSize(width: pageSize.width - margin * 2, height: 160))
    }

    private static func drawHistogram(_ bins: [HistogramBin], at origin: CGPoint, size: CGSize) {
        guard let maxCount = bins.map(\.count).max(), maxCount > 0 else { return }
        let barWidth = size.width / CGFloat(max(bins.count, 1))
        let path = UIBezierPath(rect: CGRect(origin: origin, size: size))
        UIColor(white: 0.92, alpha: 1).setFill()
        path.fill()

        for (i, bin) in bins.enumerated() {
            let barHeight = size.height * CGFloat(bin.count) / CGFloat(maxCount)
            let rect = CGRect(x: origin.x + CGFloat(i) * barWidth + 1, y: origin.y + size.height - barHeight, width: max(barWidth - 2, 1), height: barHeight)
            UIColor(red: 0.20, green: 0.55, blue: 0.85, alpha: 1).setFill()
            UIBezierPath(rect: rect).fill()
        }
        UIColor(white: 0.6, alpha: 1).setStroke()
        UIBezierPath(rect: CGRect(origin: origin, size: size)).stroke()
    }

    // MARK: - Page 3: Legend

    private static func drawLegendPage(context: UIGraphicsPDFRendererContext, content: ReportContent) {
        context.beginPage()
        var y = margin
        y = drawText("Color Legend", at: CGPoint(x: margin, y: y), font: .boldSystemFont(ofSize: 20), color: .black)
        y += 16

        let unit = content.project.unit
        for stop in content.colorMapper.stops {
            let swatchRect = CGRect(x: margin, y: y, width: 28, height: 18)
            UIColor(red: stop.color.r, green: stop.color.g, blue: stop.color.b, alpha: 1).setFill()
            UIBezierPath(roundedRect: swatchRect, cornerRadius: 3).fill()
            _ = drawText("\(stop.label) — \(unit.format(mm: stop.thicknessMM))", at: CGPoint(x: margin + 40, y: y), font: .systemFont(ofSize: 12), color: .black)
            y += 26
        }
    }

    // MARK: - Page 4: Photos (optional)

    private static func drawPhotosPage(context: UIGraphicsPDFRendererContext, content: ReportContent) {
        context.beginPage()
        var y = margin
        y = drawText("Photos & Screenshots", at: CGPoint(x: margin, y: y), font: .boldSystemFont(ofSize: 20), color: .black)
        y += 12

        let columns = 2
        let spacing: CGFloat = 12
        let cellWidth = (pageSize.width - margin * 2 - spacing) / CGFloat(columns)
        for (i, photo) in content.photos.prefix(6).enumerated() {
            let col = i % columns
            let row = i / columns
            let cellHeight = cellWidth * (photo.size.height / max(photo.size.width, 1))
            let origin = CGPoint(x: margin + CGFloat(col) * (cellWidth + spacing), y: y + CGFloat(row) * (cellHeight + spacing))
            photo.draw(in: CGRect(origin: origin, size: CGSize(width: cellWidth, height: cellHeight)))
        }
    }

    // MARK: - Final page: Sign-off + QR

    private static func drawSignOffPage(context: UIGraphicsPDFRendererContext, content: ReportContent) {
        context.beginPage()
        var y = margin
        y = drawText("Sign-Off", at: CGPoint(x: margin, y: y), font: .boldSystemFont(ofSize: 20), color: .black)
        y += 24

        y = drawKeyValueRow(label: "Engineer", value: content.project.engineerName, at: y)
        y = drawKeyValueRow(label: "Date", value: DateFormatter.reportDate.string(from: Date()), at: y)
        y += 20

        if let signature = content.signatureImage {
            let sigSize = CGSize(width: 200, height: 200 * signature.size.height / max(signature.size.width, 1))
            signature.draw(in: CGRect(origin: CGPoint(x: margin, y: y), size: sigSize))
        } else {
            UIColor.lightGray.setStroke()
            let line = UIBezierPath()
            line.move(to: CGPoint(x: margin, y: y + 40))
            line.addLine(to: CGPoint(x: margin + 220, y: y + 40))
            line.stroke()
            _ = drawText("Signature", at: CGPoint(x: margin, y: y + 44), font: .systemFont(ofSize: 10), color: .gray)
        }

        if let qr = QRCodeGenerator.generate(from: "scanart://project/\(content.project.id.uuidString)/scan/\(content.scan.id.uuidString)") {
            let qrSize = CGSize(width: 90, height: 90)
            qr.draw(in: CGRect(x: pageSize.width - margin - qrSize.width, y: y, width: qrSize.width, height: qrSize.height))
        }
    }

    // MARK: - Drawing primitives

    @discardableResult
    private static func drawText(_ text: String, at point: CGPoint, font: UIFont, color: UIColor) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: point, withAttributes: attributes)
        return point.y + font.lineHeight + 4
    }

    private static func drawWrappedText(_ text: String, at point: CGPoint, width: CGFloat, font: UIFont, color: UIColor) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let rect = CGRect(x: point.x, y: point.y, width: width, height: 300)
        (text as NSString).draw(in: rect, withAttributes: attributes)
        let bounding = (text as NSString).boundingRect(with: CGSize(width: width, height: 1000), options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
        return point.y + bounding.height + 8
    }

    private static func drawKeyValueRow(label: String, value: String, at y: CGFloat) -> CGFloat {
        _ = drawText(label + ":", at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 12, weight: .semibold), color: .darkGray)
        _ = drawText(value, at: CGPoint(x: margin + 160, y: y), font: .systemFont(ofSize: 12), color: .black)
        return y + 20
    }
}

enum QRCodeGenerator {
    static func generate(from string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

extension DateFormatter {
    static let reportDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
