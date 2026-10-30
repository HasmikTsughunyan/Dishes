import 'dart:io';
//import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:isar_community/isar.dart';
//import 'package:http/http.dart' as http;
import '../../features/allergens/data/models/schemas.dart';
import '../../core/services/network_service/network_api_conroller.dart';
import 'package:flutter/foundation.dart';

//import 'package:my_cookbook/features/auth/data/auth_repository.dart';

class SyncService {
  final Isar _isar;

  SyncService(this._isar) {
    _initConnectivityListener();
  }

  void _initConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      debugPrint("I am online");
      if (results.isNotEmpty && results.first != ConnectivityResult.none) {
        debugPrint("🌐 Интернет появился! Запускаем фоновую синхронизацию...");
        syncDataWithServer();
      }
    });
  }

  Future<void> syncDataWithServer() async {
    try {
      final user = await _isar.userProfiles.where().findFirst();
      debugPrint('The user is: ${user?.login} (ID: ${user?.authId})');
      if (user == null) {
        debugPrint(" The sync process is stopped, the user is not found");
        return;
      }
      // await _syncAllergens(user);
      await syncRecipes(user);
    } catch (e) {
      stdout.writeln("❌ Ошибка при синхронизации: $e");
    }
  }

  // 🎯 ԿԱՏԱՐՅԱԼ ՈՒՂՂՎԱԾ ՏԱՐԲԵՐԱԿ. Միացնում է ձեր եղած բոլոր դաշտերը Isar-ի և Tables-ի հետ
  Future<void> fetchAndSyncFromServer(String userId, String userLogin) async {
    try {
      // 1. ՈՒՂՂՎԱԾ Է. Եթե պրոֆիլը դեռ չկա Isar-ում (առաջին սթարթն է), մենք այն ստեղծում ենք, այլ ոչ թե return անում!
      var user = await _isar.userProfiles.where().findFirst();
      await _isar.writeTxn(() async {
        if (user != null) {
          user.authId = userId;
          user.login = userLogin;
          await _isar.userProfiles.put(user);
        } else {
          final newUser = UserProfile()
            ..authId = userId
            ..login = userLogin;
          await _isar.userProfiles.put(newUser);
        }
      });

      // 2. ՈՒՂՂՎԱԾ Է. Փոխանցում ենք տեքստային userLogin-ը, որպեսզի Appwrite-ը ճիշտ ֆիլտրի
      final List<dynamic> remoteRecipes =
          await NetworkApiController.fetchMyAuthoredRecipes(userId);

      if (remoteRecipes.isNotEmpty) {
        await _isar.writeTxn(() async {
          for (var remoteData in remoteRecipes) {
            // 🎯 ՈՒՂՂՎԱԾ Է. Appwrite Tables-ում ID-ն միշտ '\$id' է!
            final String? sId = (remoteData['\$id'] ?? remoteData['id'])
                ?.toString();
            if (sId == null || sId.isEmpty || sId == 'null') continue;

            final String? mainImageUrl =
                remoteData['main_image']?.toString() ??
                remoteData['photo_url']?.toString();
            final List<String> additionalImageUrls =
                (remoteData['additional_images'] is List)
                ? List<String>.from(remoteData['additional_images'])
                : (remoteData['additionalimg'] is List)
                ? List<String>.from(remoteData['additionalimg'])
                : <String>[];

            var localRecipe = await _isar.recipes
                .filter()
                .serverRecipeIdEqualTo(sId)
                .findFirst();

            if (localRecipe != null) {
              localRecipe.title = remoteData['title'] ?? localRecipe.title;
              localRecipe.description =
                  remoteData['instructions'] ?? remoteData['description'] ?? '';
              localRecipe.cloudMainImageUrl =
                  mainImageUrl == null || mainImageUrl.isEmpty
                  ? null
                  : mainImageUrl;
              localRecipe.cloudAdditionalImageUrls = additionalImageUrls;
              localRecipe.authorId = userId;
              localRecipe.authorName = userLogin;
              localRecipe.cuisine = remoteData['cuisine'];
              localRecipe.viewsCount = remoteData['views_count'];
              localRecipe.videoLink = remoteData['video_link'];
              localRecipe.textIngredients = List<String>.from(
                remoteData['ingredient_list'] ??
                    remoteData['ingredients_list'] ??
                    remoteData['ingredientList'] ??
                    [],
              );
              localRecipe.categoryTypes = List<String>.from(
                remoteData['category_type'] ??
                    remoteData['categoryTypes'] ??
                    [],
              );
              localRecipe.allergenGroups = List<String>.from(
                remoteData['allergen_groups'] ??
                    remoteData['allergenGroups'] ??
                    [],
              );

              if (localRecipe.localMainImage?.startsWith('http') ?? false) {
                localRecipe.localMainImage = null;
              }
              localRecipe.localAdditionalImages = localRecipe
                  .localAdditionalImages
                  ?.where((path) => !path.startsWith('http'))
                  .toList();
              localRecipe.isSynced = true;
              await _isar.recipes.put(localRecipe);
            } else {
              final newRecipe = Recipe()
                ..serverRecipeId = sId
                ..title = remoteData['title'] ?? 'Без названия'
                ..description =
                    remoteData['instructions'] ??
                    remoteData['description'] ??
                    ''
                ..authorId = userId
                ..authorName = userLogin
                ..cuisine = remoteData['cuisine'] ?? 'Не указано'
                ..viewsCount = remoteData['views_count'] ?? 0
                ..videoLink = remoteData['video_link'] ?? ''
                ..allergenGroups = List<String>.from(
                  remoteData['allergen_groups'] ??
                      remoteData['allergenGroups'] ??
                      [],
                )
                ..textIngredients = List<String>.from(
                  remoteData['ingredient_list'] ??
                      remoteData['ingredients_list'] ??
                      remoteData['ingredientList'] ??
                      [],
                )
                ..categoryTypes = List<String>.from(
                  remoteData['category_type'] ??
                      remoteData['categoryTypes'] ??
                      [],
                )
                ..cloudMainImageUrl =
                    mainImageUrl == null || mainImageUrl.isEmpty
                    ? null
                    : mainImageUrl
                ..cloudAdditionalImageUrls = additionalImageUrls
                ..isSynced = true;

              await _isar.recipes.put(newRecipe);
            }
          }
        });
        debugPrint(
          "🔄 Ռեցեպտները հաջողությամբ ներբեռնվեցին Appwrite Cloud-ից դեպի Isar!",
        );
      }
    } catch (e) {
      debugPrint("❌ Չհաջողվեց սինխրոնացնել ամպի տվյալները Isar-ի հետ: $e");
    }
  }

  Future<void> syncRecipes(UserProfile user) async {
    debugPrint('syncRecipes is working for ${user.authId}');
    final unsyncedRecipes = await _isar.recipes
        .filter()
        .isSyncedEqualTo(false)
        .authorIdEqualTo(user.authId)
        .findAll();

    debugPrint(
      " Գտնվելէ ոչ սինխրոնացված բաղադրատոմսեր ${unsyncedRecipes.length} հատ։",
    );

    for (var recipe in unsyncedRecipes) {
      try {
        // 🎯 ՈՒՂՂՎԱԾ Է ՏԻՊԵՐԻ ԽՆԴԻՐԸ. Ոչ մի .load() կամ .map() այլևս պետք չէ!
        // Վերցնում ենք պատրաստի List<String> զանգվածները անմիջապես ռեցեպտի միջից
        final List<String> allergenNames = recipe.allergenGroups;
        final List<String> textIngredients = List<String>.from(
          recipe.textIngredients,
        );

        // 1. ԳԼԽԱՎՈՐ ՆԿԱՐԻ ԲԵՌՆՈՒՄ ԱՄՊԱՅԻՆ STORAGE
        String? cloudMainImageUrl = recipe.cloudMainImageUrl;
        final localMainImage = recipe.localMainImage;
        if (localMainImage != null && localMainImage.startsWith('http')) {
          cloudMainImageUrl ??= localMainImage;
          recipe.localMainImage = null;
        } else if (localMainImage != null &&
            (cloudMainImageUrl == null || cloudMainImageUrl.isEmpty)) {
          final mainFile = File(localMainImage);
          if (await mainFile.exists()) {
            cloudMainImageUrl = await NetworkApiController.uploadFileToStorage(
              mainFile,
            );
          }
        }

        // 2. ԼՐԱՑՈՒՑԻՉ ՆԿԱՐՆԵՐԻ ԲԵՌՆՈՒՄ ԱՄՊԱՅԻՆ STORAGE (Մինչև 3 հատ)
        final List<String> cloudAdditionalImagesUrls = [];
        final localAdditionalImages = recipe.localAdditionalImages ?? [];
        final previousCloudUrls = recipe.cloudAdditionalImageUrls ?? [];
        for (var index = 0; index < localAdditionalImages.length; index++) {
          final localPath = localAdditionalImages[index];
          if (localPath.startsWith('http')) {
            cloudAdditionalImagesUrls.add(localPath);
            continue;
          }

          if (index < previousCloudUrls.length &&
              previousCloudUrls[index].isNotEmpty) {
            cloudAdditionalImagesUrls.add(previousCloudUrls[index]);
            continue;
          }

          final additionalFile = File(localPath);
          if (await additionalFile.exists()) {
            final url = await NetworkApiController.uploadFileToStorage(
              additionalFile,
            );
            if (url != null) cloudAdditionalImagesUrls.add(url);
          }
        }
        if (localAdditionalImages.isEmpty) {
          cloudAdditionalImagesUrls.addAll(previousCloudUrls);
        }

        recipe.cloudMainImageUrl = cloudMainImageUrl;
        recipe.cloudAdditionalImageUrls = cloudAdditionalImagesUrls;
        recipe.localAdditionalImages = localAdditionalImages
            .where((path) => !path.startsWith('http'))
            .toList();

        String? finalServerId;

        if (recipe.serverRecipeId != null &&
            !recipe.serverRecipeId!.startsWith('local_')) {
          // 🎯 ՈՒՂՂՎԱԾ Է (UPDATE ՌԵԺԻՄ). Փոխանցում ենք ID-ն որպես String (առանց սխալ int parse-ի!)
          final bool isUpdated = await NetworkApiController.updateRecipeInCloud(
            serverRecipeId: recipe.serverRecipeId!,
            title: recipe.title,
            instructions: recipe.description,
            ingredientList: textIngredients,
            imageUrl: cloudMainImageUrl,
            additionalimg: cloudAdditionalImagesUrls,
            allergenGroups: allergenNames,
            categories: recipe.categoryTypes,
            cuisine: recipe.cuisine,
            viewsCount: recipe.viewsCount,
            source: recipe.videoLink,
            authorname: recipe.authorName,
            userAuthId: recipe.authorId,
          );

          if (isUpdated) {
            finalServerId = recipe.serverRecipeId;
          }
        } else {
          finalServerId = await NetworkApiController.uploadUserRecipeToCloud(
            recipe: recipe,
            userAuthId: user.authId,
            userLogin: user.login,
            textIngredients: textIngredients,
            allergenNames: allergenNames,
            mainImageUrl: cloudMainImageUrl,
            additionalImageUrls: cloudAdditionalImagesUrls,
            title: recipe.title,
            instructions: recipe.description,
            cuisine: recipe.cuisine,
            viewsCount: recipe.viewsCount,
            source: recipe.videoLink,
            categories: recipe.categoryTypes,
          );
        }
        debugPrint(' await for uploadRecipeToCloud with:  $finalServerId');
        if (finalServerId != null) {
          await _isar.writeTxn(() async {
            recipe.serverRecipeId = finalServerId;
            recipe.isSynced = true;
            await _isar.recipes.put(recipe);
          });
          stdout.writeln(
            "✨ Рецепт '${recipe.title}' успешно синхронизирован с Appwrite TablesDB!",
          );
        }
      } catch (e) {
        if (e is AppwriteException) {
          debugPrint(
            'server մերժել է սինխրոնիզացիան․ (կոդ ${e.code}): ${e.message}',
          );
          stdout.writeln(
            "server մերժել է սինխրոնիզացիան․ (կոդ ${e.code}): ${e.message}",
          );
        } else {
          debugPrint('background sync error for $recipe.title: $e');
          stdout.writeln(
            "❌ Ошибка фоновой синхронизации рецепта '${recipe.title}': $e",
          );
        }
      }
    }
  }
}
