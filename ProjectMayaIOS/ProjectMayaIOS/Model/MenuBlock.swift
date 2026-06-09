//
//  MenuBlock.swift
//  ProjectMayaIOS
//
//  Created by Herrys Yu on 2025-06-28.
//

struct MenuBlocks: Codable {
    let blockList: BlockList
    
    init(BlockList: BlockList) {
        self.blockList = BlockList
    }
    
    func isValid() -> Bool {
        return true
    }
}
