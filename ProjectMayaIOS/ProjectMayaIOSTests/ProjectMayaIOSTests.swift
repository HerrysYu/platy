//
//  ProjectMayaIOSTests.swift
//  ProjectMayaIOSTests
//
//  Created by Hongji Fu on 5/23/25.
//

import Testing
@testable import ProjectMayaIOS

struct ProjectMayaIOSTests {

    @Test func dishNameSanitizerRemovesOCRMetadata() {
        let cases = [
            ("金针菇..", "金针菇"),
            ("…金针菇⋯", "金针菇"),
            ("金针菇---12元/份", "金针菇"),
            ("金针菇---12元-", "金针菇"),
            ("金针菇……￥12.00", "金针菇"),
            ("金针菇......12", "金针菇"),
            ("金针菇......12--", "金针菇"),
            ("金针菇--", "金针菇"),
            ("金针菇 时价", "金针菇"),
            ("金针菇 时价--", "金针菇"),
            ("...", "")
        ]

        for (input, expected) in cases {
            #expect(DishNameSanitizer.clean(input) == expected)
        }
    }

    @Test func dishNameSanitizerPreservesLegitimateNames() {
        let names = [
            "Dr. Pepper",
            "A&W",
            "7-UP",
            "-18°C冰淇淋",
            "C++",
            "#1套餐",
            "酸菜鱼/水煮鱼",
            "クリーム・ブリュレ"
        ]

        for name in names {
            #expect(DishNameSanitizer.clean(name) == name)
        }
    }

}
