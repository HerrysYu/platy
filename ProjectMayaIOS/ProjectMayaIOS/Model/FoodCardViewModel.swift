import SwiftUI
class DishViewModel: ObservableObject {
    @Published var dish: Dish?
    @Published var isLoading = true
    
    init() {
        loadData()
    }
    
    func loadData() {
        // 模拟异步加载
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.dish = Dish(
                title: "Chicken Croquettes",
                subtitle: "チキンクロケット",
                ingredients: [
                    Ingredient(name: "Chicken", isAlert: false),
                    Ingredient(name: "Potato", isAlert: false),
                    Ingredient(name: "Butter", isAlert: false),
                    Ingredient(name: "Flour", isAlert: true),
                    Ingredient(name: "Milk/Cream", isAlert: false),
                    Ingredient(name: "Onion", isAlert: false),
                    Ingredient(name: "Eggs", isAlert: false),
                    Ingredient(name: "Breadcrumbs", isAlert: true),
                    Ingredient(name: "Cabbage", isAlert: false),
                    Ingredient(name: "Cherry Tomato", isAlert: false)
                ],
                images: [
                    "croquette1", "croquette2", "croquette3"
                ],
                description: "Crispy chicken croquettes with a creamy mashed potato and minced chicken filling. Lightly seasoned, tender inside with a golden, crunchy crust—comforting and satisfying, similar to classic potato croquettes.",
                tags: ["Crispy (24)", "Creamy (12)", "Sharing (5)"],
                reviews: [
                    Review(username: "SeattleBites89", source: "Google Review", comment: "Crispy outside, creamy inside! Loved the contrast with the fresh shredded cabbage and sweet cherry tomatoes.", highlight: "Crispy outside, creamy inside!", avatarURL: "avatar1"),
                    Review(username: "WanderFoodie_Jen", source: "Trip Advisor", comment: "crunchy shell, smooth filling. Four pieces were perfect for sharing. Would totally order again!", highlight: "crunchy shell", avatarURL: "avatar2")
                ]
            )
            self.isLoading = false
        }
    }
}

