import 'package:isar_community/isar.dart'; 

// Этот инклюд нужен для генератора кода. Файл schemas.g.dart создастся автоматически.
part 'schemas.g.dart';

@Collection()
class UserProfile {
  Id id = Isar.autoIncrement; // Локальный ID для Isar

  @Index(unique: true, replace: true)
  late String authId;        // Уникальный ID из вашей системы авторизации (серверный)
  late String login;
  String? email;

bool isSynced = false; 

  // Связь "Пользователь имеет много Аллергенов"
  final allergens = IsarLinks<Allergen>();
}

@Collection()
class Allergen {
  Id id = Isar.autoIncrement;

  bool isSynced = false; 

  @Index(unique: true)
  late String name; // Например: 'nuts', 'lactose', 'gluten'
}

@Collection()
class Ingredient{
  Id id = Isar.autoIncrement;
  @Index(unique: true)
  late String ingrName;

}

@Collection()
class Recipe {
  Id id = Isar.autoIncrement;
  
  late String title;
  late String description;
  late String authorId; 
  late String authorName;
  late String cuisine;
  String? videoLink;
  int? viewsCount;
  String? localMainImage;
  String? cloudMainImageUrl;

  
  List<String> allergenGroups = [];
  
  List<String> textIngredients = []; 
  
  List<String> categoryTypes = [];
  List<String>? localAdditionalImages; 
  List<String>? cloudAdditionalImageUrls;
 
  
  bool isSynced = false; 
  
  String? serverRecipeId;
}

