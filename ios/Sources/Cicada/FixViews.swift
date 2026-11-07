import SwiftUI

/// 改正听错的词 on iPhone and iPad: a line as shown, its fixed words with the Mac's dotted underline.
enum FixedText {
    /// The line with its applied fixes; each fixed word dotted, a word still waiting (这样改对吗？)
    /// on a pale wash as heard. The Mac's `TranscriptParagraphs.joinFixed` for one line.
    static func attributed(_ l: TranscriptLine) -> AttributedString {
        let (text, marks) = Correction.apply(l.fixes ?? [], to: l.src)
        var a = AttributedString(text)
        for m in marks {
            guard let lo = AttributedString.Index(m.lowerBound, within: a), let hi = AttributedString.Index(m.upperBound, within: a) else { continue }
            a[lo..<hi].underlineStyle = Text.LineStyle(pattern: .dot, color: Ink.tertiary)
        }
        for f in l.fixes ?? [] where f.ask == true {
            if let r = a.range(of: f.from) { a[r].backgroundColor = Ink.accentWash }
        }
        return a
    }
}
