import Testing

// Small assertion helpers keep source locations while supporting throwing solver expressions.
func expectThrows(_ expression: @autoclosure () throws -> Any, sourceLocation: SourceLocation = #_sourceLocation) {
    do { _ = try expression(); Issue.record("Expected an error", sourceLocation: sourceLocation) }
    catch {}
}
func expectNoThrow(_ expression: @autoclosure () throws -> Any, sourceLocation: SourceLocation = #_sourceLocation) {
    do { _ = try expression() }
    catch { Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation) }
}
func expectEqual<T: Equatable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(a == b, sourceLocation: sourceLocation)
}
func expectEqual(_ a: Float, _ b: Float, accuracy: Float, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(a - b) <= accuracy, sourceLocation: sourceLocation)
}
func expectLess<T: Comparable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(a < b, sourceLocation: sourceLocation)
}
func expectLessEqual<T: Comparable>(_ a: T, _ b: T, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(a <= b, "\(message)", sourceLocation: sourceLocation)
}
func expectGreater<T: Comparable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(a > b, sourceLocation: sourceLocation)
}
func expectGreaterEqual<T: Comparable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(a >= b, sourceLocation: sourceLocation)
}
func expectTrue(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value, sourceLocation: sourceLocation)
}
func expectNotNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value != nil, sourceLocation: sourceLocation)
}
