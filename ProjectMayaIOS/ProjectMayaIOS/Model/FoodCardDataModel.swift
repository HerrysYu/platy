import SwiftUI
import Combine

struct Ingredient: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let isAlert: Bool
}

struct Review: Identifiable {
    let id = UUID()
    let username: String
    let source: String
    let comment: String
    let highlight: String // 关键字高亮
    let avatarURL: String
}

struct Dish {
    let title: String
    let subtitle: String
    let ingredients: [Ingredient]
    let images: [String]
    let description: String
    let tags: [String]
    let reviews: [Review]
}
