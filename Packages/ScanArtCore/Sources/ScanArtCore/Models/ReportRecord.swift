import Foundation
import SwiftData

/// Metadata for a generated PDF report. The PDF itself lives in the project's
/// Reports/ folder; this row lets the Reports screen list history without
/// re-reading every PDF from disk.
@Model
public final class ReportRecord {
    @Attribute(.unique) public var id: UUID
    public var project: Project?

    public var title: String
    public var pdfFileName: String
    public var generatedDate: Date
    /// IDs of the ScanRecords included in this report (usually the original +
    /// one rescan, but a report can cover a whole timeline).
    public var includedScanIDs: [UUID]
    public var engineerName: String
    public var customerName: String

    public init(
        id: UUID = UUID(),
        title: String,
        pdfFileName: String,
        includedScanIDs: [UUID],
        engineerName: String,
        customerName: String
    ) {
        self.id = id
        self.title = title
        self.pdfFileName = pdfFileName
        self.generatedDate = Date()
        self.includedScanIDs = includedScanIDs
        self.engineerName = engineerName
        self.customerName = customerName
    }
}
