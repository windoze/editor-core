import Foundation

extension AttoEditorAreaViewController {
    func _lspWorkbenchDockItemsForTesting() -> [AttoLspWorkbenchDockView.Item] {
        lspWorkbenchDockView?.currentItems ?? []
    }

    func _lspWorkbenchDockSelectedItemForTesting() -> AttoLspWorkbenchDockView.Item? {
        lspWorkbenchDockView?.selectedItem
    }

    @discardableResult
    func _selectLspWorkbenchDockItemForTesting(id: String) -> Bool {
        lspWorkbenchDockView?.selectItem(id: id) ?? false
    }

    func _lspWorkbenchDockRowCountForTesting() -> Int {
        lspWorkbenchDockView?.rowCount ?? 0
    }

    func _lspWorkbenchDockIsVisibleForTesting() -> Bool {
        lspWorkbenchDockView?.isVisible == true
    }
}
