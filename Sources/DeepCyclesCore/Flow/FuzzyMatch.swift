/// The command palette's matcher.
package enum FuzzyMatch {
    /// True when `text` contains `query`, or contains its characters in order ("gtw" → "go to week").
    /// Case-insensitive. An empty query matches everything.
    package static func matches(_ query: String, in text: String) -> Bool {
        let q = query.lowercased()
        let t = text.lowercased()
        if q.isEmpty || t.contains(q) { return true }
        var it = t.makeIterator()
        for ch in q {
            var found = false
            while let c = it.next() {
                if c == ch { found = true; break }
            }
            if !found { return false }
        }
        return true
    }
}
