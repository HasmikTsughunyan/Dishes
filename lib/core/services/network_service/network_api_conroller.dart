import 'dart:convert';
import 'dart:io';
import 'package:appwrite/appwrite.dart';
import '../../../features/allergens/data/models/schemas.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

// Класс Environment оставляем как у вас
class Environment {
  static const String appwriteProjectId =
      '6ab36208002bff0986e9'; //'6a4a7a2600224cc2da40';
  static const String appwriteProjectName = 'My Cookbook'; //'my_appnosql';
  static const String appwritePublicEndpoint =
      'https://fra.cloud.appwrite.io/v1';
  static const String appwriteDatabaseId = '6ab36301000f3eaac699';
  static const String appwriteTableId = '6ab3652800196a39c430';
  static const String appwriteTableName = 'recipes';

  static const String appwriteBucketId = '6ab6168400160c2f8ef5';
}

class NetworkApiController {
  static final Client _client = Client()
      .setEndpoint(Environment.appwritePublicEndpoint)
      .setProject(Environment.appwriteProjectId);
  // .setSelfSigned(status:true);

  static Client get client => _client; // Getter для доступа к клиенту Appwrite

  static final TablesDB _tablesDb = TablesDB(_client);
  static const String _databaseId = Environment.appwriteDatabaseId;
  static const String _tableId = Environment.appwriteTableId;
  static final Storage _storage = Storage(_client);
  static const String _bucketId = Environment.appwriteBucketId;

  static final Account _account = Account(_client);

  static final Databases databases = Databases(_client);

  void initApwrite() {
    if (kDebugMode) {
      // Keep debug and release builds pointed at the configured cloud project.
      _client
          .setEndpoint(Environment.appwritePublicEndpoint)
          .setProject(Environment.appwriteProjectId)
          .setSelfSigned(status: false);

      print("Appwrite запущен в режиме разработки (Debug)");
    } else {
      // 🚀 НАСТРОЙКИ ДЛЯ ГОТОВОГО APK (Релиз в продакшн)
      _client
          .setEndpoint(
            Environment.appwritePublicEndpoint,
          ) // Или ваш боевой HTTPS домен
          .setProject(Environment.appwriteProjectId);
      // .setSelfSigned здесь НЕ вызываем (по умолчанию false)

      stdout.writeln("Appwrite запущен в релизном режиме (Release)");
    }
  }

  /// 1. ՈՒՄԱՆՑ ՈՐՈՆՈՒՄ ԸՍՏ ՍԱՌՆԱՐԱՆԻ ԱՊՐԱՆՔՆԵՐԻ (🎯 ՈՒՂՂՎԱԾ Է `List<int>`)
  static Future<List<Map<String, dynamic>>> searchRecipesByFridge(
    List<int> productIds,
  ) async {
    try {
      // Քանի որ Appwrite-ում `ingredients_list`-ը տեքստային Array է,
      // մենք փնտրում ենք ռեցեպտներ, որոնք պարունակում են ընտրված ապրանքները
      final List<String> stringIds = productIds
          .map((id) => id.toString())
          .toList();

      final response = await _tablesDb.listRows(
        databaseId: _databaseId,
        tableId: _tableId,
        // Փնտրում ենք ռեցեպտներ, որտեղ բաղադրիչների մեջ կան մեր ընտրված ID-ները
        queries: [Query.equal("ingredients_list", stringIds)],
      );

      debugPrint(response.toString());

      return _mapRowsToFrontend(response.rows);
    } catch (e) {
      stdout.writeln("❌ Որոնման սխալ սառնարանում: \$e");
      return []; // 🎯 ՊԱՐՏԱԴԻՐ Է: Սխալի դեպքում վերադարձնում ենք դատարկ ցուցակ
    }
  }

  /// 2. ԲԵՐՆՈՒՄ ԵՆՔ ՌԵՑԵՊՏՆԵՐԸ ԸՍՏ ԿԱՏԵԳՈՐԻԱՆԵՐԻ
  static Future<List<Map<String, dynamic>>> fetchRecipesFromCloud(
    String category,
  ) async {
    try {
      final response = await _tablesDb.listRows(
        databaseId: _databaseId,
        tableId: _tableId,
        queries: [
          Query.containsAny("category_type", [category]),
        ],
      );
      debugPrint(response.toString());
      return _mapRowsToFrontend(response.rows);
    } catch (e) {
      return [];
    }
  }

  /// Отправляет измененные параметры рецепта в базу данных Appwrite TablesDB
  static Future<bool> updateRecipeInCloud({
    required String serverRecipeId,
    required String? title,
    required String? instructions,
    String? cuisine,
    required String userAuthId,
    String? authorname,
    String? source,
    String? imageUrl,
    List<dynamic>? additionalimg,
    List<dynamic>? categories,
    required List<String>? ingredientList,
    required List<String>? allergenGroups,
    required int? viewsCount,
  }) async {
    try {
      final Map<String, dynamic> data = {
        "author_id": userAuthId,
        "author": authorname,
        "title": title,
        "instructions": instructions,
        "views_count": viewsCount ?? 0,
        "main_image": imageUrl ?? '',
        "additional_images": List<String>.from(additionalimg ?? []),
        "category_type": List<String>.from(categories ?? []).isNotEmpty
            ? List<String>.from(categories ?? [])
            : [],
        "cuisine": cuisine ?? "Домашняя",
        "ingredients_list": List<String>.from(ingredientList ?? []),
        "allergen_groups": List<String>.from(allergenGroups ?? []),
        "video_link": source ?? '',
      };

      debugPrint('Updating recipe row $serverRecipeId in Appwrite');
      try {
        await _tablesDb.updateRow(
          databaseId: _databaseId,
          tableId: _tableId,
          rowId: serverRecipeId,
          data: data,
        );
      } on AppwriteException catch (error) {
        if (error.type != 'row_not_found') rethrow;

        debugPrint(
          'Recipe row $serverRecipeId is missing; recreating it with the same ID',
        );
        await _tablesDb.createRow(
          databaseId: _databaseId,
          tableId: _tableId,
          rowId: serverRecipeId,
          data: data,
        );
      }
      debugPrint('Recipe row $serverRecipeId saved successfully');
      stdout.writeln('Recipe is successfully updated in Appwrite TablesDB!');

      return true;
    } catch (e) {
      debugPrint('unsuccessed upload, error: $e');
      stdout.writeln(
        '❌ Ошибка сети при обновлении параметров рецепта в Appwrite: $e',
      );
      return false;
    }
  }

  /// 1. ЗАГРУЗКА ЛОКАЛЬНОГО ФАЙЛА В APPWRITE STORAGE И ПОЛУЧЕНИЕ ССЫЛКИ
  static Future<String?> uploadFileToStorage(File file) async {
    try {
      debugPrint('entered');
      if (!await file.exists()) return null;
      debugPrint('Uploading image file: ${file.path}');
      // Генерируем уникальный ID для файла на сервере
      final String fileId = ID.unique();
      debugPrint('fileId is $fileId');
      // Физически отправляем файл в созданный бакет
      final uploadedFile = await _storage.createFile(
        bucketId: _bucketId,
        fileId: fileId,
        file: InputFile.fromPath(
          path: file.path,
          filename: p.basename(file.path),
        ),
        permissions: [Permission.read(Role.any())],
      );
      debugPrint('this info is for upload: $uploadedFile');
      // Конструируем прямую постоянную ссылку (URL) для отображения картинки в приложении
      final String fileUrl =
          '${Environment.appwritePublicEndpoint}/storage/buckets/$_bucketId/files/${uploadedFile.$id}/view?project=${Environment.appwriteProjectId}';

      return fileUrl;
    } catch (e) {
      stdout.writeln("❌ Ошибка загрузки файла в Appwrite Storage: $e");
      return null;
    }
  }

  static Future<({String avatarUrl, bool previousAvatarDeleted})>
  updateUserAvatar(File file, {required String userId}) async {
    final currentUser = await _account.get();
    if (currentUser.$id != userId) {
      throw StateError(
        'The active Appwrite account does not match the profile.',
      );
    }

    final avatarUrl = await uploadFileToStorage(file);
    if (avatarUrl == null) {
      throw StateError('Failed to upload the avatar to Appwrite Storage.');
    }

    try {
      final activeUser = await _account.get();
      if (activeUser.$id != userId) {
        throw StateError(
          'The active Appwrite account changed while uploading the avatar.',
        );
      }

      final currentPrefs = await _account.getPrefs();
      final previousAvatarUrl =
          currentPrefs.data['avatar_url']?.toString() ?? '';

      await _account.updatePrefs(
        prefs: {...currentPrefs.data, 'avatar_url': avatarUrl},
      );

      final previousAvatarDeleted =
          previousAvatarUrl.isEmpty ||
          previousAvatarUrl == avatarUrl ||
          (_isManagedStorageFile(previousAvatarUrl) &&
              await deleteFileFromStorage(previousAvatarUrl));

      return (
        avatarUrl: avatarUrl,
        previousAvatarDeleted: previousAvatarDeleted,
      );
    } catch (error) {
      await deleteFileFromStorage(avatarUrl);
      rethrow;
    }
  }

  static Future<String> fetchCurrentUserAvatarUrl({
    required String userId,
  }) async {
    final currentUser = await _account.get();
    if (currentUser.$id != userId) {
      throw StateError(
        'The active Appwrite account does not match the profile.',
      );
    }

    final prefs = await _account.getPrefs();
    return prefs.data['avatar_url']?.toString() ?? '';
  }

  static Future<void> endCurrentSession({
    required String expectedUserId,
  }) async {
    final currentUser = await _account.get();
    if (currentUser.$id != expectedUserId) {
      throw StateError(
        'The active Appwrite account does not match the profile being deleted.',
      );
    }

    await _account.deleteSession(sessionId: 'current');
  }

  static bool _isManagedStorageFile(String fileUrl) {
    final uri = Uri.tryParse(fileUrl);
    final endpoint = Uri.parse(Environment.appwritePublicEndpoint);
    if (uri == null || !uri.hasAuthority || uri.origin != endpoint.origin) {
      return false;
    }

    final segments = uri.pathSegments;
    final bucketIndex = segments.indexOf('buckets');
    return bucketIndex >= 0 &&
        bucketIndex + 4 < segments.length &&
        segments[bucketIndex + 1] == _bucketId &&
        segments[bucketIndex + 2] == 'files' &&
        segments[bucketIndex + 3].isNotEmpty &&
        segments[bucketIndex + 4] == 'view';
  }

  /// 2. УДАЛЕНИЕ ФАЙЛА ИЗ APPWRITE STORAGE ПО ЕГО URL/ID
  static Future<bool> deleteFileFromStorage(String fileUrl) async {
    try {
      // Извлекаем уникальный fileId из строки URL-адреса файла
      // Ссылка имеет формат: .../files/FILE_ID/view?...
      final Uri uri = Uri.parse(fileUrl);
      final List<String> segments = uri.pathSegments;

      // Находим индекс сегмента 'files', следующий за ним сегмент — это наш File ID
      final int filesIndex = segments.indexOf('files');
      if (filesIndex == -1 || filesIndex + 1 >= segments.length) return false;

      final String fileId = segments[filesIndex + 1];

      // Удаляем файл из облачного бакета
      await _storage.deleteFile(bucketId: _bucketId, fileId: fileId);
      stdout.writeln("🗑️ Файл $fileId успешно удален из Appwrite Storage!");
      return true;
    } catch (e) {
      stdout.writeln("❌ Ошибка удаления файла из Appwrite Storage: $e");
      return false;
    }
  }

  /// Deletes a specific recipe row from the cloud database
  static Future<bool> deleteRecipeFromCloud(String serverRecipeId) async {
    try {
      await _tablesDb.deleteRow(
        databaseId: _databaseId,
        tableId: _tableId,
        rowId: serverRecipeId,
      );
      stdout.writeln('recipe is deleted from cloud db');
      return true;
    } catch (e) {
      stdout.writeln('❌ Network exception during recipe row deletion: $e');
      return false;
    }
  }

  /// 3. ԹՈՓ 20 ԱՄԵՆԱՇԱՏ ԴԻՏՎԱԾ ՌԵՑԵՊՏՆԵՐԻ ԲԵՌՆՈՒՄ
  static Future<List<Map<String, dynamic>>> fetchTop20Recipes() async {
    try {
      final response = await _tablesDb.listRows(
        databaseId: _databaseId,
        tableId: _tableId,
        queries: [Query.orderDesc("views_count"), Query.limit(20)],
      );
      debugPrint('Appwrite returned ${response.rows.length} top recipes');
      return _mapRowsToFrontend(response.rows);
    } catch (e) {
      debugPrint('Appwrite fetchTop20Recipes failed: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> searchRecipesByTitle(
    String title,
  ) async {
    final query = title.trim();
    if (query.isEmpty) return [];

    try {
      final response = await _tablesDb.listRows(
        databaseId: _databaseId,
        tableId: _tableId,
        queries: [Query.contains("title", query)],
      );
      debugPrint(
        'Appwrite returned ${response.rows.length} recipes for title $query',
      );
      return _mapRowsToFrontend(response.rows);
    } catch (e) {
      debugPrint('Appwrite fetchRecipesByTitle failed: $e');
      rethrow;
    }
  }

  // 🎯 4. ՕՖԼԱՅՆ ՌԵՑԵՊՏԻ ԲԵՌՆՈՒՄ ԱՄՊ (Ուղարկում ենք Appwrite-ի սյունակների հետ)
  static Future<String?> uploadUserRecipeToCloud({
    required Recipe recipe,
    required String userAuthId,
    required String userLogin,
    List<String>? textIngredients,
    required List<String> allergenNames,
    String? mainImageUrl,
    List<String>? additionalImageUrls,
    required String? title,
    required String? instructions,
    required String? cuisine,
    required int? viewsCount,
    required String? source,
    required List<String>? categories,
  }) async {
    try {
      // 🎯 ՈՒՂՂՎԱԾ Է. Գրում ենք մեկ կետով (`.createRow`), որպեսզի վերադարձվի Document-ի օբյեկտը
      final dbRow = await _tablesDb.createRow(
        databaseId: _databaseId,
        tableId: _tableId,
        rowId: ID.unique(),
        data: {
          "author_id": userAuthId,
          "author": userLogin,
          "title": recipe.title,
          "instructions": recipe.description,
          "views_count": recipe.viewsCount ?? 0,
          "category_type": recipe.categoryTypes.isNotEmpty
              ? recipe.categoryTypes
              : ["салаты"],
          "cuisine": recipe.cuisine,
          "ingredients_list": textIngredients ?? [],
          "allergen_groups": allergenNames,
          "main_image": mainImageUrl ?? '',
          "additional_images": additionalImageUrls ?? [],
        },
      );

      // 🎯 ՈՒՂՂՎԱԾ Է. Այժմ dbRow.\$id-ն կաշխատի անսխալ, քանի որ Cascade օպերատորը հեռացվել է
      debugPrint('Успешно создана строка с ID: ({dbRow.id}');
      return dbRow.$id;
    } catch (e) {
      debugPrint('❌ Ошибка отправки в Appwrite TablesDB: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>>
  searchGlobalRecipesByMultipleIngredients(List<String> ingredientNames) async {
    try {
      // 🎯 САНТИЗАЦИЯ И СТՈՈГТИЗАЦИЯ НИЖНЕГО РЕГИСТРА
      final cleanNames = ingredientNames
          .map((name) => name.trim().toLowerCase())
          .where((name) => name.isNotEmpty)
          .toList();

      if (cleanNames.isEmpty) return [];

      final matchingRows = <dynamic>[];
      String? cursor;
      while (matchingRows.length < 20) {
        final response = await _tablesDb.listRows(
          databaseId: Environment.appwriteDatabaseId,
          tableId: Environment.appwriteTableId,
          queries: [
            Query.limit(100),
            if (cursor != null) Query.cursorAfter(cursor),
          ],
        );
        final rows = response.rows;
        if (rows.isEmpty) break;

        for (final row in rows) {
          final ingredients = _stringListFrom(row.data['ingredients_list']);
          final matchesIngredient = ingredients.any((ingredient) {
            final normalizedIngredient = ingredient.toLowerCase();
            return cleanNames.any(normalizedIngredient.contains);
          });
          if (matchesIngredient) {
            matchingRows.add(row);
            if (matchingRows.length == 20) break;
          }
        }

        if (rows.length < 100 || matchingRows.length == 20) break;
        cursor = rows.last.$id;
      }

      return _mapRowsToFrontend(matchingRows);
    } catch (e) {
      stdout.writeln("❌ Ошибка при глобальном Tables OR поиске: $e");
      rethrow;
    }
  }

  /// 5. ԴԻՏՈՒՄՆԵՐԻ ՀԱՇՎԻՉԻ ԱՎԵԼԱՑՈՒՄ
  static Future<void> incrementRecipeView(
    String recipeId,
    int currentViews,
  ) async {
    try {
      await _tablesDb.updateRow(
        databaseId: _databaseId,
        tableId: _tableId,
        rowId: recipeId,
        data: {"views_count": currentViews + 1},
      );
    } catch (e) {
      // Իգնոր ֆոնային սխալները
    }
  }

  // Օգնող մեթոդ Appwrite-ի տվյալները ֆրոնտենդին հարմար ձևաչափի բերելու համար
  static List<Map<String, dynamic>> _mapRowsToFrontend(List<dynamic> rows) {
    return rows.map((doc) {
      final rawIngredients = doc.data['ingredients_list'];
      final List<dynamic> safeIngredients = (rawIngredients is List)
          ? rawIngredients
          : [];
      final categories = _stringListFrom(doc.data['category_type']);
      final authorName =
          [
                doc.data['author_name'],
                doc.data['authorName'],
                doc.data['author'],
                doc.data['p_author'],
              ]
              .map((value) => value?.toString().trim() ?? '')
              .firstWhere((value) => value.isNotEmpty, orElse: () => 'Система');

      return {
        'id': doc.$id,
        'title': doc.data['title']?.toString() ?? 'Без названия',
        'categories': categories,
        'category_type': categories,
        'allergen_groups': (doc.data['allergen_groups'] is List)
            ? List<String>.from(doc.data['allergen_groups'])
            : [],
        'cuisine': doc.data['cuisine']?.toString() ?? 'Домашняя',
        'instructions':
            doc.data['instructions']?.toString() ?? 'Инструкция отсутствует.',
        'author': authorName,
        'author_name': authorName,
        'views_count': (doc.data['views_count'] is num)
            ? (doc.data['views_count'] as num).toInt()
            : 0,
        'ingredients_json': jsonEncode(safeIngredients),
        'main_image': doc.data['main_image']?.toString() ?? '',
        'additional_images': (doc.data['additional_images'] is List)
            ? List<String>.from(doc.data['additional_images'])
            : [],
        'ingredient_list': List<String>.from(safeIngredients),
        'video_link': doc.data['video_link']?.toString() ?? '',
        'author_id': doc.data['author_id']?.toString() ?? '',
      };
    }).toList();
  }

  static List<String> _stringListFrom(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is! String || value.trim().isEmpty || value.trim() == 'null') {
      return [];
    }

    final text = value.trim();
    if (text.startsWith('[') && text.endsWith(']')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          return decoded
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList();
        }
      } on FormatException {
        // Fall through to the comma-separated representation.
      }
      return text
          .substring(1, text.length - 1)
          .split(',')
          .map((item) => item.trim().replaceAll('"', '').replaceAll("'", ''))
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static Future<List<Map<String, dynamic>>> fetchMyAuthoredRecipes(
    String authorId,
  ) async {
    try {
      final response = await _tablesDb.listRows(
        databaseId: _databaseId,
        tableId: _tableId,
        queries: [Query.equal("author_id", authorId)],
      );
      return _mapRowsToFrontend(response.rows);
    } catch (e) {
      stdout.writeln('Ошибка получение моих рецептов: $e');
      return [];
    }
  }

  // ... ձեր մնացած ID-ները և մեթոդները

  /// 🎯 ԱՎԵԼԱՑՎԱԾ Է: Իրական օգտատիրոջ մուտք Appwrite Cloud (Ընդհանուր դեպք)
  static Future<Map<String, dynamic>?> loginUser(
    String email,
    String password,
  ) async {
    try {
      // Քանի որ Appwrite-ը մուտքի համար պահանջում է Email, մենք լոգինին ավտոմատ
      // կցում ենք վիրտուալ դոմեն, եթե օգտատերը ուղղակի տեքստ է գրել
      /*  final String validEmail = emailOrLogin.contains('@') 
          ? emailOrLogin 
          : '$emailOrLogin@mycookbook.local';*/

      // 1. Ստեղծում ենք սեսիա Appwrite-ում
      await _account.createEmailPasswordSession(
        email: email.trim(),
        password: password,
      );

      // 2. Վերցնում ենք հաջողված մուտք գործած օգտատիրոջ իրական տվյալները սերվերից
      final userDetails = await _account.get();

      // Վերադարձնում ենք պրոֆիլի քարտեզը (Map)
      return {
        "id": userDetails.$id, // Սերվերի ստեղծած եզակի անվտանգ ID-ն
        "login": userDetails.name.isNotEmpty ? userDetails.name : email,
        "avatar_url": userDetails.prefs.data['avatar_url']?.toString() ?? '',
      };
    } catch (e) {
      stdout.writeln("❌ Իրական մուտքի սխալ Appwrite-ում: $e");
      return null; // Եթե պարոլը սխալ է կամ օգտատերը գոյություն չունի
    }
  }

  static Future<bool> registerUser({
    required String email,
    required String password,
    required String name,
    String? phoneNumber,
  }) async {
    try {
      /* final String validEmail = emailOrLogin.contains('@')
      ? emailOrLogin.trim()
      :'${emailOrLogin.trim()}@mycookbook.local';*/

      // Գրանցում ենք նոր օգտատեր Appwrite-ի Auth համակարգում
      await _account.create(
        userId: ID.unique(), // Սերվերը ավտոմատ կգեներացնի ID
        email: email,
        password: password,
        name: name.trim(),
      );

      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        stdout.writeln(
          "the phone number is successfully added to your account: $phoneNumber",
        );
      }

      stdout.writeln(
        "🚀 Пользователь $email успешно зарегистрирован в Appwrite Cloud!",
      );
      return true;
    } catch (e) {
      stdout.writeln("❌ Ошибка регистрации в Appwrite Cloud: $e");
      return false;
    }
  }

  static Future<Map<String, dynamic>?> authenticateOrRegister(
    String loginOrEmail,
    String password,
  ) async {
    // 1. Ապահով մաքրում ենք մուտքագրված տեքստը
    final String input = loginOrEmail.trim();
    final String pass = password.trim();

    // 2. Ճկուն ստուգում. եթե էլ. փոստ չէ, ավտոմատ կցում ենք վիրտուալ դոմենը
    final String validEmail = input.contains('@')
        ? input
        : '$input@mycookbook.net';
    final String cleanLogin = input.contains('@')
        ? input.split('@').first
        : input;

    // 3. Պատրաստվում ենք սեսիայի ստեղծմանը (անվտանգության համար փակում ենք հինը, եթե կա)
    try {
      await _account.deleteSession(sessionId: 'current');
    } catch (_) {}

    try {
      stdout.writeln("🌐 Փորձում ենք մուտք գործել սերվեր... ($validEmail)");

      // Ա) ՓՈՐՁՈՒՄ ԵՆՔ ՄՈՒՏՔ ԳՈՐԾԵԼ
      await _account.createEmailPasswordSession(
        email: validEmail,
        password: pass,
      );
      final userDetails = await _account.get();

      stdout.writeln("✅ Մուտքը հաջողվեց:");
      return {
        "id": userDetails.$id,
        "login": cleanLogin,
        "email": userDetails.email,
        "avatar_url": userDetails.prefs.data['avatar_url']?.toString() ?? '',
      };
    } catch (e) {
      if (e is AppwriteException) {
        // 401 նշանակում է սխալ գաղտնաբառ (Invalid credentials)
        if (e.code == 401) {
          return {"error": "Неверный пароль для данного аккаунта."};
        }
        // Եթե սխալը 404 չէ (այսինքն խնդիրը ցանցն է կամ սերվերը, այլ ոչ թե ակաունտի բացակայությունը)
        if (e.code != 404) {
          return {
            "error":
                "Ошибка сети или сервера Appwrite: (${e.code}) ${e.message}",
          };
        }
      } else {
        // Ցանցային կապի ուղիղ խափանում (SocketException / Timeout)
        return {
          "error":
              "Нет связи с сервером Appwrite. Проверьте интернет-соединение на смартфоне. ($e)",
        };
      }

      // 🎯 ՄԻԱՅՆ 404 (Ակաունտը գոյություն չունի) ՍԽԱԼԻ ԴԵՊՔՈՒՄ Է ՍԿՍՎՈՒՄ ԱՎՏՈՄԱՏ ԳՐԱՆՑՈՒՄԸ
      stdout.writeln(
        "ℹ️ Аккаунт не найден (404). Автоматически регистрируем нового шефа...",
      );

      try {
        // Գրանցում ենք նոր ակաունտ ամպում
        await _account.create(
          userId: ID.unique(),
          email: validEmail,
          password: pass,
          name: cleanLogin,
        );

        // Գրանցումից անմիջապես հետո կատարում ենք ՄՈՒՏՔ սեսիա ստեղծելու համար
        await _account.createEmailPasswordSession(
          email: validEmail,
          password: pass,
        );
        final userDetails = await _account.get();

        stdout.writeln("🎉 Ավտոմատ գրանցումն ու մուտքը հաջողվեցին:");
        return {
          "id": userDetails.$id,
          "login": cleanLogin,
          "email": userDetails.email,
          "avatar_url": userDetails.prefs.data['avatar_url']?.toString() ?? '',
        };
      } catch (regError) {
        stdout.writeln("❌ Գրանցման կամ սխալ տվյալների սխալ ամպում: $regError");
        return null; // Եթե պարոլը 8 նիշից կարճ է կամ կա ցանցի խնդիր
      }
    }
  }
}

/*
// =======================================================
// СЕТЕВОЙ КОНТРОЛЛЕР API: APPWRITE TABLES API
// =======================================================
class NetworkApiController {
  static final Client _client = Client()
    ..setEndpoint(Environment.appwritePublicEndpoint)
    ..setProject(Environment.appwriteProjectId);

  static final TablesDB _tablesDb = TablesDB(_client);
  static const String _databaseId = Environment.appwriteDatabaseId; 
  static const String _tableId = Environment.appwriteTableId;

  static Future<List<Map<String, dynamic>>> fetchRecipesFromCloud(String category) async {
    try {
      final response = await _tablesDb.listRows(
        databaseId: _databaseId,
        tableId: _tableId,
        queries: [Query.equal("category_type", category)],
      );
      return _mapRowsToFrontend(response.rows);
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchTop20Recipes() async {
    try {
      final response = await _tablesDb.listRows(
        databaseId: _databaseId,
        tableId: _tableId,
        queries: [Query.orderDesc("views_count"), Query.limit(20)],
      );
      return _mapRowsToFrontend(response.rows);
    } catch (e) {
      return [];
    }
  }

  static Future<void> incrementRecipeView(String recipeId, int currentViews) async {
    try {
      await _tablesDb.updateRow(
        databaseId: _databaseId,
        tableId: _tableId,
        rowId: recipeId,
        data: {"views_count": currentViews + 1},
      );
    } catch (e) {
      // Игнорируем фоновые ошибки
    }
  }

  static List<Map<String, dynamic>> _mapRowsToFrontend(List<dynamic> rows) {
    return rows.map((doc) {
      final rawIngredients = doc.data['ingredients_list'];
      final List<dynamic> safeIngredients = (rawIngredients is List) ? rawIngredients : [];

      return {
        'id': doc.$id,
        'title': doc.data['title']?.toString() ?? 'Без названия',
        'category_type': doc.data['category_type']?.toString() ?? 'салаты',
        'instructions': doc.data['instructions']?.toString() ?? 'Инструкция отсутствует.',
        'author': doc.data['author']?.toString() ?? 'Система',
        'views_count': (doc.data['views_count'] is num) ? (doc.data['views_count'] as num).toInt() : 0,
        'ingredinets_list': (doc.data['ingrList']) ?? (doc.data['ingredints']) ??'',
        'ingredients_json': jsonEncode(safeIngredients),
        'image_url': doc.data['image_url']?.toString(),
      };
    }).toList();
  }
}
*/
