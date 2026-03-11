; Minimal indentation rules for the Rust fixture.
;
; Capture conventions used by `TreeSitterIndenter`:
; - `@indent` increases indentation for lines inside the captured node.
; - `@outdent` decreases indentation when the captured token begins a line.

(block) @indent

["}" "]" ")"] @outdent

