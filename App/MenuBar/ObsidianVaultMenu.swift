import AppKit
import OtterCore

/// The "Use Obsidian Vault ▸" submenu: the vaults Obsidian knows about, most recently opened first.
/// Choosing one points the default folder destination at the vault's root, the same way "Choose
/// Folder…" does. Read from `obsidian.json` each time the submenu opens, never polled. Temporary
/// until T10's Add menu.
@MainActor
final class ObsidianVaultMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu(title: "Use Obsidian Vault")
    private let folderChooser: FolderChooser

    init(folderChooser: FolderChooser) {
        self.folderChooser = folderChooser
        super.init()
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let vaults = VaultDiscovery.vaults()
        guard !vaults.isEmpty else {
            let item = menu.addItem(withTitle: "No Vaults Found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return
        }
        for vault in vaults {
            let item = menu.addItem(withTitle: vault.name, action: #selector(useVault(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = vault.path
            item.toolTip = (vault.path.path as NSString).abbreviatingWithTildeInPath
        }
    }

    @objc private func useVault(_ sender: NSMenuItem) {
        guard let root = sender.representedObject as? URL else {
            return
        }
        folderChooser.use(root)
    }
}
