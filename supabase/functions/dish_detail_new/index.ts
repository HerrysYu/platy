import { startDishDetailServer } from "../_shared/dish_detail_api_gemini.ts";

startDishDetailServer({
  functionName: "dish_detail_new",
  apiKeyEnv: "DISH_DETAIL_NEW_API_KEY",
  baseUrl: "https://run.v3.cm",
  fallbackBaseUrls: [],
  model: "gemini-3.6-flash",
  fallbackModels: [],
  useBearerAuth: true,
  useCamelCaseSearchTool: true,
  useNativeActionEndpoints: true,
});
