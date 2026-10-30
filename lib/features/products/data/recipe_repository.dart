import 'dart:io';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p; // Для удобной работы с путями файлов
import 'package:path_provider/path_provider.dart';
import '../../allergens/data/models/schemas.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/services/network_service/network_api_conroller.dart';
import 'package:flutter/foundation.dart';




class RecipeRepository {
  final Isar _isar;
   final SyncService _syncService;

  RecipeRepository(this._isar, this._syncService);

  /// Сохранить новый рецепт с локальным фото смартфона и привязкой к аллергенам
  Future<void> saveRecipe({
    required String title,
    required String description,
    required String currentUserId,
    required String authorName,
    required List<String> categories,
    required String cuisine,
    File? pickedMainImageFile,       // Файл фотографии, выбранный из галереи
    List<File>? pickedAdditionalImagesFiles,
    required List<String> selectedAllergens,    // Список аллергенов в этом рецепте
    required List<String> textIngredients, //Список ингредиентов из рецепта
    String? videoLink, 
    
      }) async {

  
  final Directory appDocDir = await getApplicationDocumentsDirectory();
  
  // 1. Մշակում ենք գլխավոր նկարը
  String? localMainImagePath;
  if (pickedMainImageFile != null && await pickedMainImageFile.exists()) {
    final String mainName = p.basename(pickedMainImageFile.path);
    localMainImagePath = p.join(appDocDir.path, 'main_$mainName');
    await pickedMainImageFile.copy(localMainImagePath); // Պատճենում ենք սմարթֆոնի պահոց
  }

  // 2. Մշակում ենք լրացուցիչ նկարները (մինչև 3 հատ)
  List<String> localAdditionalImagesPaths = [];
  if (pickedAdditionalImagesFiles != null) {
    for (var file in pickedAdditionalImagesFiles) {
      if (await file.exists()) {
        final String addName = p.basename(file.path);
        final String savedPath = p.join(appDocDir.path, 'add_$addName');
        await file.copy(savedPath); // Պատճենում ենք ամեն մի ֆայլը
        localAdditionalImagesPaths.add(savedPath); // Պահում ենք տեղական հասցեն
      }
    }
  }

  // 3. Ստեղծում ենք Isar օբյեկտը
  final recipe = Recipe()
    ..title = title
    ..description = description
    ..authorId =  currentUserId //?? "Anonymous"
    ..authorName = authorName //?? "Guest"
    ..categoryTypes = categories // Գրվում է որպես List<String> Isar-ում
    ..textIngredients = textIngredients
    ..cuisine = cuisine
    ..serverRecipeId = 'local_${DateTime.now().millisecondsSinceEpoch}' 
    ..localMainImage = localMainImagePath
    ..localAdditionalImages = localAdditionalImagesPaths // Գրվում է որպես List<String> Isar-ում
    ..videoLink = videoLink
    ..allergenGroups = selectedAllergens
     ..isSynced = false;

  // 4. Պահպանում ենք Isar NoSQL տեղական բազայում
  await _isar.writeTxn(() async {
    await _isar.recipes.put(recipe);
 
    
  });

  stdout.writeln("📦 Ռեցեպտը հաջողությամբ պահվեց Isar-ում: Հիմնական նկար + ${localAdditionalImagesPaths.length} լրացուցիչ նկար:");

  final user = await _isar.userProfiles.where().findFirst();
  if (user != null) {
    // Вызываем ваш метод, который прописан в SyncService
    await _syncService.syncRecipes(user); 
  }

      }



  /// 🔄 2. ԹԱՐՄԱՑՆԵԼ ԳՈՅՈՒԹՅՈՒՆ ՈՒՆԵՑՈՂ ՌԵՑԵՊՏԸ (UPDATE EXISTING RECIPE)
  Future<void> updateRecipe({
    required String serverRecipeId,
    required String title,
    required String description,
    required List<String> categories,
    required String cuisine,
    File? pickedMainImageFile,       
    List<File>? pickedAdditionalImagesFiles,
    required List<String> selectedAllergens,    
    required List<String> textIngredients, 
    String? videoLink, 
    int? existingViewsCount, // 🎯 ՈՒՂՂՎԱԾ Է ՏԱՌԱՍԽԱԼԸ
  }) async {
    final recipe = await _isar.recipes
        .filter()
        .serverRecipeIdEqualTo(serverRecipeId)
        .findFirst();

    if (recipe == null) return;

    final Directory appDocDir = await getApplicationDocumentsDirectory();
    
    debugPrint ('application is on the path: ${appDocDir.path}');
    
    if (pickedMainImageFile != null && await pickedMainImageFile.exists()) {
      final String mainName = p.basename(pickedMainImageFile.path);
      final String localMainImagePath = p.join(appDocDir.path, 'main_$mainName');
      await pickedMainImageFile.copy(localMainImagePath);
      recipe.localMainImage = localMainImagePath;
      recipe.cloudMainImageUrl = null;
    }

    if (pickedAdditionalImagesFiles != null) {
      for (final oldPath in recipe.localAdditionalImages ?? <String>[]) {
        if (oldPath.startsWith('http')) continue;
        final oldFile = File(oldPath);
        if (await oldFile.exists()) await oldFile.delete();
      }

      final localAdditionalImagesPaths = <String>[];
      for (final file in pickedAdditionalImagesFiles) {
        if (!await file.exists()) continue;
        final savedPath = p.join(appDocDir.path, 'add_${p.basename(file.path)}');
        await file.copy(savedPath);
        localAdditionalImagesPaths.add(savedPath);
      }
      recipe.localAdditionalImages = localAdditionalImagesPaths;
      recipe.cloudAdditionalImageUrls = null;
    }


    recipe.title = title;
    recipe.description = description;
    recipe.categoryTypes = categories;
    recipe.cuisine = cuisine;
    recipe.videoLink = videoLink;
    recipe.allergenGroups = selectedAllergens;
    recipe.textIngredients = textIngredients; // 🎯 ԱՎԵԼԱՑՎԱԾ Է
    recipe.viewsCount = existingViewsCount ?? 0;
    recipe.isSynced = false;
    
    await _isar.writeTxn(() async {
      await _isar.recipes.put(recipe);
    });

    stdout.writeln("recipe was updated in local db");

    final userWhoUpdate = await _isar.userProfiles.where().findFirst();
    if (userWhoUpdate != null) {
      await _syncService.syncRecipes(userWhoUpdate);
    }
  }

  /// 🗑️ 3. ՊՈԼՆՈԵ ՈՒԴԱԼԵՆԻԵ ՌԵՑԵՊՏԱ (ISAR + ФАЙЛЫ + ОБЛАКО APPWRITE)
  Future<void> deleteRecipe(int localId) async {
    final recipe = await _isar.recipes.get(localId);
    if (recipe == null) return;

    final String? localMainImage = recipe.localMainImage;
    final List<String>? localAdditionalImages = recipe.localAdditionalImages;
    final String? serverRecipeId = recipe.serverRecipeId;

    if (localMainImage != null && !localMainImage.startsWith('http')) {
      final file = File(localMainImage);
      if (await file.exists()) await file.delete();
    }
    if (localAdditionalImages != null) {
      for (var path in localAdditionalImages) {
        if (path.startsWith('http')) continue;
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }

    await _isar.writeTxn(() async {
      await _isar.recipes.delete(localId);
    });
    stdout.writeln("🗑️ Рецепт полностью удален локально со смартфона!");

    if (serverRecipeId != null &&
        serverRecipeId.isNotEmpty &&
        !serverRecipeId.startsWith('local_')) {
      final String? cloudMainUrl = recipe.cloudMainImageUrl ??
          (localMainImage?.startsWith('http') ?? false ? localMainImage : null);
      final cloudAdditionalUrls = <String> {
        ...?recipe.cloudAdditionalImageUrls,
        ...?localAdditionalImages?.where((path) => path.startsWith('http')),
        };

      if (cloudMainUrl != null) {
        await NetworkApiController.deleteFileFromStorage(cloudMainUrl);
      }
      for (var url in cloudAdditionalUrls) {
        await NetworkApiController.deleteFileFromStorage(url);
      }

      await NetworkApiController.deleteRecipeFromCloud(serverRecipeId);
    }
  }

  Future<List<Recipe>> getMyLocalRecipes(String currentUserId) async {
    return await _isar.recipes
        .filter()
        .authorIdEqualTo(currentUserId)
        .findAll();
  }

  /// 🛡️ 4. ՍԱՌՆԱՐԱՆԻ ՖԻԼՏՐԱՑԻԱ. ՍՏԱՆԱԼ ՕԳՏԱՏԻՐՈՋ ՀԱՄԱՐ ԱՆՎՏԱՆԳ ՌԵՑԵՊՏՆԵՐԸ
  Future<List<Recipe>> getSafeRecipesForUser(UserProfile user) async {
    if (!user.allergens.isLoaded) {
      await user.allergens.load();
    }
    
    final userAllergenNames = user.allergens.map((a) => a.name).toList();

    final allRecipes = await _isar.recipes.where().findAll();
    final List<Recipe> safeRecipes = [];

    for (var recipe in allRecipes) {
      // 🎯 ՈՒՂՂՎԱԾ Է ՏԻՊԵՐԻ ԽՆԴԻՐԸ. Ոչ մի .load() այլևս պետք չէ:
      // Ուղղակի ստուգում ենք՝ արդյո՞ք ռեցեպտի տեքստային ալերգենների մեջ կա օգտատիրոջ արգելված տառերից
      final hasConflict = recipe.allergenGroups.any((name) => userAllergenNames.contains(name));
      
      if (!hasConflict) {
        safeRecipes.add(recipe);
      }
    }

    return safeRecipes;
  }

  Future<List<Recipe>> getAllLocalRecipes() async {
    return await _isar.recipes.where().findAll();
  }

      }