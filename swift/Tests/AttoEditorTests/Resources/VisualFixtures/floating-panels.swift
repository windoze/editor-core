struct PaletteFixture {
    let primaryValue: Int

    func renderLine() -> String {
        print(primaryValue)
        return "primary"
    }
}
