import 'dart:io'; // Обязательно для работы с файлами картинок смартфона
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'features/edit_recipe_bottom_sheet.dart';
import 'features/auth/presentation/register_screen.dart';
import 'package:appwrite/appwrite.dart' as appwrite;
import 'package:flutter_localizations/flutter_localizations.dart'; // 2. Для системных виджетов

// Импортируем Isar и скрываем Query, чтобы не конфликтовать с Appwrite
import 'package:isar_community/isar.dart' hide Query;

// Импорты ваших модулей
import 'features/allergens/data/models/schemas.dart';
import 'core/services/sync_service.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/products/data/recipe_repository.dart';
import 'core/services/network_service/network_api_conroller.dart';
import 'localcache/local_controller.dart';
import 'utils/app_localizations.dart';
import 'utils/image_picker_service.dart';
import 'package:my_cookbook/features/add_new_recipe.dart';
import 'package:isar_community/isar.dart';

class Environment {
  static const String appwriteProjectId =
      '6ab36208002bff0986e9'; //'6a4a7a2600224cc2da40';
  static const String appwriteProjectName = 'My Cookbook'; //'my_appnosql';
  static const String appwritePublicEndpoint =
      'https://fra.cloud.appwrite.io/v1';
  static const String appwriteDatabaseId = '6ab36301000f3eaac699';
  static const String appwriteTableId = '6ab3652800196a39c430';
  static const String appwriteTableName = 'recipes';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация локальной папки и Isar DB
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open([
    UserProfileSchema,
    AllergenSchema,
    RecipeSchema,
    IngredientSchema,
  ], directory: dir.path);

  // Инициализация фоновой синхронизации
  final syncService = SyncService(isar);
  syncService.syncDataWithServer();

  runApp(
    MultiProvider(
      providers: [
        Provider<Isar>.value(value: isar),
        Provider<SyncService>.value(value: syncService),
        ProxyProvider<Isar, AuthRepository>(
          update: (_, isarInstance, _) => AuthRepository(isarInstance),
        ),

        ProxyProvider2<Isar, SyncService, RecipeRepository>(
          update: (_, isarInstance, syncInstance, _) =>
              RecipeRepository(isarInstance, syncInstance),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static void setLocale(BuildContext context, Locale newLocale) {
    _MyAppState? state = context.findAncestorStateOfType<_MyAppState>();
    state?.changeLanguage(newLocale);
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkMode = false;

  // 🌟 ԱՎԵԼԱՑՎԱԾ Է. Լեզվի ընթացիկ կարգավիճակը (Դեֆոլտ՝ ռուսերեն)
  Locale _currentLocale = const Locale('en');

  // 🌟 ԱՎԵԼԱՑՎԱԾ Է. Լեզվի LIVE փոփոխման մեթոդը
  void changeLanguage(Locale locale) {
    setState(() {
      _currentLocale = locale;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final savedMode = await LocalCacheController.getLocalThemeMode();
    if (mounted) setState(() => _isDarkMode = savedMode);
  }

  Future<void> _setThemeMode(bool isDarkMode) async {
    setState(() => _isDarkMode = isDarkMode);
    await LocalCacheController.saveLocalThemeMode(isDarkMode);
  }

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: brightness,
    );
    final baseTheme = brightness == Brightness.dark
        ? ThemeData.dark()
        : ThemeData.light();

    return baseTheme.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(color: colorScheme.surfaceContainerLow),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
      ),
      dialogTheme: DialogThemeData(backgroundColor: colorScheme.surface),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DISHES',

      onGenerateTitle: (context) =>
          AppLocalizations.of(context).translate('cookbook_lbl'),

      debugShowCheckedModeBanner: false,
      locale: _currentLocale, // 🌟 ԱՎԵԼԱՑՎԱԾ Է. Կարգավորում ենք ընթացիկ լեզուն
      supportedLocales: const [Locale('ru'), Locale('en'), Locale('hy')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: MainScreen(isDarkMode: _isDarkMode, onThemeChanged: _setThemeMode),
    );
  }
}

class MainScreen extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onThemeChanged;
  const MainScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentBottomIndex =
      -1; // -1 - Главная, 0 - Лента, 1 - Свой Скрининг, 2 - ИИ Чат
  List<Map<String, dynamic>> _topRecipes = [];
  bool _isLoadingTop = true;
  Map<String, dynamic>? _currentUserProfile;
  final Map<String, bool> _activeAllergens = {
    'nuts': false,
    'lactose': false,
    'gluten': false,
  };
  late final Future<void> _sessionRestoreFuture;

  appwrite.RealtimeSubscription? _realtimeSubscription;

  @override
  void initState() {
    super.initState();
    _sessionRestoreFuture = _restoreSession();
    _loadTopRecipesFeed();
    _initAppwriteRealtimeListener();
  }

  Future<void> _restoreSession() async {
    final authRepository = Provider.of<AuthRepository>(context, listen: false);

    final user = await authRepository.getCurrentUser();
    if (!mounted || user == null) return;

    await _setAuthenticatedProfile({
      'id': user.authId,
      'login': user.login,
      'email': user.email,
    });
  }

  Future<void> _setAuthenticatedProfile(Map<String, dynamic> profile) async {
    final userId = profile['id']?.toString();
    if (userId == null || userId.isEmpty) {
      throw StateError('Authenticated profile has no user ID.');
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final preferenceKey = 'active_allergens_$userId';
    var selectedAllergens = prefs.getStringList(preferenceKey);
    if (selectedAllergens == null) {
      final isar = Provider.of<Isar>(context, listen: false);
      final savedAllergens = await isar.allergens.where().findAll();
      const supportedAllergens = {'nuts', 'lactose', 'gluten'};
      selectedAllergens = savedAllergens
          .map((allergen) => allergen.name)
          .where(supportedAllergens.contains)
          .toSet()
          .toList();
      await prefs.setStringList(preferenceKey, selectedAllergens);
    }

    for (final key in _activeAllergens.keys) {
      _activeAllergens[key] = selectedAllergens.contains(key);
    }

    if (!mounted) return;
    if (mounted) {
      setState(() => _currentUserProfile = profile);
    }
  }

  Future<void> _loadTopRecipesFeed() async {
    setState(() => _isLoadingTop = true);
    final data = await NetworkApiController.fetchTop20Recipes();
    setState(() {
      _topRecipes = data;
      _isLoadingTop = false;
    });
  }

  void _initAppwriteRealtimeListener() {
    try {
      final client = NetworkApiController.client;
      final realtime = appwrite.Realtime(client);
      _realtimeSubscription = realtime.subscribe([
        'databases.${Environment.appwriteDatabaseId}.collections.${Environment.appwriteTableId}.documents.*',
      ]);
      _realtimeSubscription!.stream.listen((event) async {
        if (!mounted) return;

        final isar = Provider.of<Isar>(context, listen: false);
        final syncService = SyncService(isar);

        // 🔄 А) Если админ или вы с другого устройства ИЗМЕНИЛИ рецепт в веб-консоли
        if (event.events.contains(
          'databases.*.collections.*.documents.*.update',
        )) {
          final Map<String, dynamic> remoteData = event.payload;
          final String serverId = remoteData['\$id'].toString();

          // Вызываем наш метод обновления локального Isar, который мы только что написали
          await syncService.fetchAndSyncFromServer(
            remoteData['userId'] ?? '',
            remoteData['userLogin'] ?? '',
          );
          debugPrint("⚡ Realtime: Рецепт $serverId обновлен из облака!");
        }

        // ❌ Б) Если админ УДАЛИЛ рецепт из базы данных Appwrite Cloud
        if (event.events.contains(
          'databases.*.collections.*.documents.*.delete',
        )) {
          final Map<String, dynamic> remoteData = event.payload;
          final String serverId = remoteData['\$id'].toString();

          // Находим его локально и удаляем из Isar, чтобы на UI он мгновенно исчез
          await isar.writeTxn(() async {
            await isar.recipes
                .filter()
                .serverRecipeIdEqualTo(serverId)
                .deleteAll();
          });
          debugPrint(
            "⚡ Realtime: Рецепт $serverId удален из Isar, так как его удалили в облаке!",
          );
        }
      });
    } catch (e) {
      stdout.writeln("❌ Ошибка при инициализации Realtime: $e");
    }
  }

  @override
  void dispose() {
    _realtimeSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        title: Row(
          children: [
            if (_currentBottomIndex != -1)
              IconButton(
                icon: const Icon(Icons.home, color: Colors.white),
                onPressed: () => setState(() => _currentBottomIndex = -1),
              ),
            Text(
              AppLocalizations.of(context).translate('title'),
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.teal.shade700,
        actions: [
          IconButton(
            icon: Icon(
              _currentUserProfile != null
                  ? Icons.account_circle
                  : Icons.lock_outline,
              size: 26,
              color: Colors.white,
            ),
            onPressed: () async {
              await _sessionRestoreFuture;
              if (!context.mounted) return;

              if (_currentUserProfile != null) {
                // 1. Եթե օգտատերը արդեն ներսում է, նրան տանում ենք իր Պրոֆիլի էջ
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfilePage(
                      userProfile: _currentUserProfile!,
                      activeAllergens: _activeAllergens,
                      onLogout: () =>
                          setState(() => _currentUserProfile = null),
                    ),
                  ),
                );
              } else {
                // 2. 🎯 ՃԻՇՏ Է: Եթե մուտք գործած չէ, նրան տանում ենք ՄՈՒՏՔԻ էջ (AuthScreen)
                final profile = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
                );

                if (profile != null) {
                  await _setAuthenticatedProfile(profile);
                }
              }
            },
          ),
          IconButton(
            icon: Icon(
              widget.isDarkMode ? Icons.wb_sunny : Icons.nightlight_round,
              color: Colors.white,
            ),
            onPressed: () => widget.onThemeChanged(!widget.isDarkMode),
          ),
        ],
      ),
      body: _currentBottomIndex == -1
          ? _buildCategoriesGrid()
          : _currentBottomIndex == 0
          ? _buildTop20RecipesFeed()
          : _currentBottomIndex == 1
          ? const FridgeSearchPage()
          : _currentUserProfile != null
          ? MyAuthoredRecipesListScreen(
              userId: _currentUserProfile!['id'].toString(),
            )
          : _buildAuthRequiredPlaceholder(),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal.shade700,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () async {
          await _sessionRestoreFuture;
          if (!context.mounted) return;

          if (_currentUserProfile == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context).translate('att_lbl_1'),
                ),
                backgroundColor: Colors.orange,
              ),
            );

            final profile = await Navigator.push<Map<String, dynamic>>(
              context,
              MaterialPageRoute(builder: (context) => const AuthScreen()),
            );
            if (profile != null) {
              await _setAuthenticatedProfile(profile);
            }
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddRecipeScreen()),
            );
          }
        },
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentBottomIndex == -1 ? 0 : _currentBottomIndex,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        backgroundColor: colorScheme.surface,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentBottomIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.restaurant),
            label: AppLocalizations.of(context).translate('top20_scr_lbl'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.kitchen),
            label: AppLocalizations.of(context).translate('by_grocceries'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.notes),
            label: AppLocalizations.of(context).translate('my_ckbk'),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthRequiredPlaceholder() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_person_outlined,
              size: 80,
              color: colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).translate('your_cookbook_cloud'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).translate('att_lbl_2'),
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: const Icon(Icons.login, color: Colors.white),
              label: Text(
                AppLocalizations.of(context).translate('login_create_lbl'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () async {
                // Կանչում ենք մուտքի էկրանը
                final profile = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
                );

                if (profile != null) {
                  await _setAuthenticatedProfile(profile);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesGrid() {
    final colorScheme = Theme.of(context).colorScheme;
    final categories = [
      {
        'title': AppLocalizations.of(context).translate('cat_hot_dishes'),
        'type': 'горячее',
        'icon': Icons.soup_kitchen_outlined,
      },
      {
        'title': AppLocalizations.of(context).translate('cat_salads'),
        'type': 'салаты',
        'icon': Icons.breakfast_dining_outlined,
      },
      {
        'title': AppLocalizations.of(context).translate('cat_desserts'),
        'type': 'десерты',
        'icon': Icons.cake_outlined,
      },
      {
        'title': AppLocalizations.of(context).translate('cat_vegetables'),
        'type': 'овощи',
        'icon': Icons.lunch_dining_outlined,
      },
      {
        'title': AppLocalizations.of(context).translate('cat_drinks'),
        'type': 'напитки',
        'icon': Icons.local_drink_outlined,
      },
      {
        'title': AppLocalizations.of(context).translate('cat_else'),
        'type': 'другие',
        'icon': Icons.brunch_dining_outlined,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: colorScheme.surface,
          child: GridView.builder(
            // 🎯 ՊԱՐԱՄԵՏՐ 1: Ստիպում է ListView-ին ունենալ հստակ չափս Column-ի ներսում
            shrinkWrap: true,
            // 🎯 ՊԱՐԱՄԵՏՐ 2: Անջատում է ներքին ավելորդ սքրոլը, որպեսզի էկրանը չկոտրվի
            physics: const ScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            itemCount: categories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (context, index) {
              final cat = categories[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CategoryDetailPage(
                          title: cat['title'] as String,
                          themeColor: Colors.teal.shade700,
                          categoryType: cat['type']?.toString() ?? 'салаты',
                          activeAllergens: _activeAllergens,
                        ),
                      ),
                    ).then((_) => _loadTopRecipesFeed());
                  },
                  child: Container(
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(75),
                      border: Border.all(
                        color: Colors.white10,
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 16,
                    ),
                    child: Column(
                      // 🎯 ՊԱՐԱՄԵՏՐ 3: Հորիզոնական գծով տարրերը հավասարեցնում ենք ձախ եզրին
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,

                      children: [
                        Icon(
                          cat['icon'] as IconData,
                          size: 30,
                          color: Colors.teal.shade200,
                        ),
                        // 🎯 ՈՒՂՂՎԱԾ Է: Row-ի ներսում հեռավորության համար տալիս ենք width, այլ ոչ թե height
                        const SizedBox(width: 15),
                        Text(
                          cat['title'] as String,
                          textAlign: TextAlign.center ,
                          style: const TextStyle(
                            color: Colors.teal,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        //const Spacer(), // Տեղափոխում է սլաքը էկրանի աջ եզր
                        //Icon(Icons.arrow_forward_ios, size: 14, color: Colors.teal.shade300),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTop20RecipesFeed() {
    final colorScheme = Theme.of(context).colorScheme;
    return _isLoadingTop
        ? Center(child: CircularProgressIndicator(color: Colors.teal.shade700))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppLocalizations.of(context).translate('popular_recipes'),

                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.refresh,
                      size: 18,
                      color: Colors.teal.shade700,
                    ),
                    onPressed: _loadTopRecipesFeed,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_topRecipes.isEmpty)
                Center(
                  child: Text(
                    AppLocalizations.of(
                      context,
                    ).translate('no_popular_recipes'),
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                )
              else
                ..._topRecipes.map((recipe) {
                  final String ingredientsStr =
                      recipe['ingredients_json']?.toString() ?? '';
                  final String? imageUrl = recipe['main_image']?.toString();
                  final String lower = ingredientsStr.toLowerCase();
                  bool isDangerous = false;
                  String foundName = "";
                  if (_activeAllergens['nuts'] == true &&
                      (lower.contains('орех') || lower.contains('арахис'))) {
                    isDangerous = true;
                    foundName = "Орехи";
                  }
                  if (_activeAllergens['lactose'] == true &&
                      (lower.contains('молоко') || lower.contains('сливки'))) {
                    isDangerous = true;
                    foundName = "Лактоза";
                  }
                  if (_activeAllergens['gluten'] == true &&
                      (lower.contains('мука') || lower.contains('глютен'))) {
                    isDangerous = true;
                    foundName = "Глютен";
                  }
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    elevation: 0,
                    color: isDangerous
                        ? colorScheme.errorContainer
                        : colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isDangerous
                            ? Colors.red.shade200
                            : colorScheme.outlineVariant,
                      ),
                    ),
                    child: ListTile(
                      leading: imageUrl != null && imageUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                imageUrl,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.auto_awesome,
                                  color: isDangerous
                                      ? Colors.red.shade400
                                      : Colors.teal.shade600,
                                  size: 20,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.auto_awesome,
                              color: isDangerous
                                  ? Colors.red.shade400
                                  : Colors.teal.shade600,
                              size: 20,
                            ),
                      title: Text(
                        recipe['title'] ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDangerous
                              ? colorScheme.onErrorContainer
                              : colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Row(
                        children: [
                          Icon(
                            Icons.visibility,
                            size: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${recipe['views_count'] ?? 0} ${AppLocalizations.of(context).translate('views_lbl')}',
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (isDangerous) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.warning,
                              size: 10,
                              color: Colors.red.shade700,
                            ),
                            Text(
                              '${AppLocalizations.of(context).translate('includes_lbl')}   $foundName',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 12),
                      onTap: () async {
                        final navigator = Navigator.of(context);

                        final int currentViews = (recipe['views_count'] is num)
                            ? (recipe['views_count'] as num).toInt()
                            : 0;

                        if (recipe['id'] != null) {
                          await NetworkApiController.incrementRecipeView(
                            recipe['id'].toString(),
                            currentViews,
                          );
                        }

                        navigator.push(
                          MaterialPageRoute(
                            builder: (_) => RecipeDetailPage(
                              recipe: recipe,
                              onRecipeUpdated: () =>
                                  setState(() => _loadTopRecipesFeed()),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }),
            ],
          );
  }
}

class IngredientSearchDropdown extends StatelessWidget {
  final int? selectedId;
  final List<Map<String, dynamic>> globalIngredients;
  final ValueChanged<int?> onSelected;
  final VoidCallback onDelete;
  const IngredientSearchDropdown({
    super.key,
    required this.selectedId,
    required this.globalIngredients,
    required this.onSelected,
    required this.onDelete,
  });
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double dropdownWidth = constraints.maxWidth - 46;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            DropdownMenu(
              initialSelection: selectedId,
              hintText: AppLocalizations.of(context).translate('search_hint_2'),
              width: dropdownWidth,
              enableFilter: true,
              enableSearch: true,
              requestFocusOnTap: true,
              textStyle: const TextStyle(fontSize: 12),
              inputDecorationTheme: const InputDecorationTheme(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
              dropdownMenuEntries: globalIngredients.map((ing) {
                return DropdownMenuEntry(
                  value: ing['id'] as int,
                  label: ing['ingrname'] ?? '',
                  style: MenuItemButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                );
              }).toList(),
              onSelected: onSelected,
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.red,
                size: 20,
              ),
              onPressed: onDelete,
            ),
          ],
        );
      },
    );
  }
}

class SearchByTitleScreen extends StatefulWidget {
  const SearchByTitleScreen({super.key});

  @override
  State<SearchByTitleScreen> createState() => SearchByTitleScreenState();
}

class SearchByTitleScreenState extends State<SearchByTitleScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results = await NetworkApiController.searchRecipesByTitle(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSearching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate('search_error_lbl'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).translate('search_title_lbl')),
        backgroundColor: Colors.teal.shade700,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(
                  context,
                ).translate('input_title_lbl2'),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _performSearch(_searchController.text),
                ),
              ),
              onSubmitted: (value) => _performSearch(value),
            ),
          ),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                ? Center(
                    child: Text(
                      AppLocalizations.of(context).translate('no_results_lbl'),
                    ),
                  )
                : ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final recipe = _searchResults[index];
                      return ListTile(
                        title: Text(
                          recipe['title'] ??
                              AppLocalizations.of(
                                context,
                              ).translate('no_title_lbl'),
                        ),
                        subtitle: Text(
                          '${AppLocalizations.of(context).translate('rcp_author_lbl2')}: ${recipe['author'] ?? AppLocalizations.of(context).translate('no_author_lbl')}',
                        ),
                        leading: recipe['main_image'].isNotEmpty
                            ? Image.network(
                                recipe['main_image'],
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                              )
                            : const Icon(Icons.fastfood, size: 40),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 12),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RecipeDetailPage(recipe: recipe),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class CategoryDetailPage extends StatelessWidget {
  final String title;
  final Color themeColor;
  final String categoryType;
  final Map<String, bool> activeAllergens;
  const CategoryDetailPage({
    super.key,
    required this.title,
    required this.themeColor,
    required this.categoryType,
    required this.activeAllergens,
  });
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    String? checkActiveAllergens(String jsonStr, Map<String, bool> allergens) {
      final String lower = jsonStr.toLowerCase();
      if (allergens['nuts'] == true &&
          (lower.contains(AppLocalizations.of(context).translate('nut_lbl2')) ||
              lower.contains(
                AppLocalizations.of(context).translate('peanuts_lbl'),
              ))) {
        return (AppLocalizations.of(context).translate('nuts_lbl2'));
      }
      if (allergens['lactose'] == true &&
          (lower.contains(AppLocalizations.of(context).translate('milk_lbl')) ||
              lower.contains(
                AppLocalizations.of(context).translate('cream_lbl'),
              ))) {
        return (AppLocalizations.of(context).translate('lactose_lbl1'));
      }
      if (allergens['gluten'] == true &&
          (lower.contains(
                AppLocalizations.of(context).translate('flour_lbl'),
              ) ||
              lower.contains(
                AppLocalizations.of(context).translate('gluten_lbl1'),
              ))) {
        return (AppLocalizations.of(context).translate('gluten_lbl2'));
      }
      return null;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: themeColor,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal.shade700,
        child: const Icon(Icons.search, color: Colors.white),
        onPressed: () async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (context) => const SearchByTitleScreen(),
            ),
          );
        },
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: NetworkApiController.fetchRecipesFromCloud(categoryType),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: themeColor));
          }
          final cloudRecipes = snapshot.data ?? [];
          if (cloudRecipes.isEmpty) {
            return Center(
              child: Text(
                AppLocalizations.of(
                  context,
                ).translate('no_recipes_in_category'),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: cloudRecipes.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (context, index) {
              final recipe = cloudRecipes[index];
              final String ingredientsStr =
                  recipe['ingredients_json']?.toString() ?? '';
              final String? foundAllergen = checkActiveAllergens(
                ingredientsStr,
                activeAllergens,
              );
              final bool isDangerous = foundAllergen != null;
              return Card(
                color: isDangerous
                    ? colorScheme.errorContainer
                    : colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isDangerous
                        ? Colors.red.shade200
                        : colorScheme.outlineVariant,
                  ),
                ),
                child: InkWell(
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    final recipeId = recipe['id'];
                    final views = recipe['views_count'] is num
                        ? (recipe['views_count'] as num).toInt()
                        : 0;

                    if (recipeId != null) {
                      await NetworkApiController.incrementRecipeView(
                        recipeId.toString(),
                        views,
                      );
                    }

                    navigator.push(
                      MaterialPageRoute(
                        builder: (_) => RecipeDetailPage(recipe: recipe),
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                          child: recipe['main_image'] != null
                              ? Image.network(
                                  recipe['main_image']!,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.fastfood, size: 40),
                                )
                              : const Center(
                                  child: Icon(
                                    Icons.fastfood,
                                    size: 40,
                                    color: Colors.grey,
                                  ),
                                ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              recipe['title'] ??
                                  AppLocalizations.of(
                                    context,
                                  ).translate('no_title_lbl1'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDangerous
                                    ? colorScheme.onErrorContainer
                                    : colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            isDangerous
                                ? Row(
                                    children: [
                                      Icon(
                                        Icons.warning,
                                        color: colorScheme.error,
                                        size: 10,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${AppLocalizations.of(context).translate('found_allergen_lbl')} $foundAllergen!',
                                        style: TextStyle(
                                          color: colorScheme.error,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    '${AppLocalizations.of(context).translate('rcp_author_lbl2')}: ${recipe['author'] ?? AppLocalizations.of(context).translate('no_author_lbl')}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class FridgeSearchPage extends StatefulWidget {
  const FridgeSearchPage({super.key});

  @override
  State<FridgeSearchPage> createState() => _FridgeSearchPageState();
}

class _FridgeSearchPageState extends State<FridgeSearchPage> {
  final TextEditingController _ingredientCtrl = TextEditingController();

  // 🎯 СПИСОК ТЕГОВ: Сюда будут добавляться введенные пользователем ингредиенты
  final List<String> _selectedIngredients = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _searchError;

  // Функция очистки и санитизации текста NoSQL
  String _sanitizeText(String text) {
    return text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  void _addIngredient() {
    final String rawInput = _ingredientCtrl.text;
    final String cleanIngredient = _sanitizeText(rawInput);

    if (cleanIngredient.isNotEmpty &&
        !_selectedIngredients.any(
          (ingredient) =>
              ingredient.toLowerCase() == cleanIngredient.toLowerCase(),
        )) {
      setState(() {
        _selectedIngredients.add(cleanIngredient);
        _ingredientCtrl.clear(); // Очищаем поле ввода
      });
    }
  }

  @override
  void dispose() {
    _ingredientCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator(color: Colors.teal))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                AppLocalizations.of(context).translate('fridge_search_lbl'),

                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(height: 12),

              // 📝 НАСТОЯЩЕЕ ТЕКСТОВОЕ ПОЛЕ ВВОДА ВМЕСТО СТАРЫХ ДРОПДАУНОВ
              TextField(
                controller: _ingredientCtrl,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(
                    context,
                  ).translate('input_ingredient_lbl'),

                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.teal),
                    onPressed: _addIngredient,
                  ),
                ),
                onSubmitted: (_) =>
                    _addIngredient(), // Добавление по кнопке Enter на клавиатуре
              ),
              const SizedBox(height: 12),

              // 🎯 ДИНАМИЧЕСКИЕ ТЕГИ (CHIPS) ПОД ПОЛЕМ ВВОДА
              if (_selectedIngredients.isNotEmpty)
                Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
                  children: _selectedIngredients.map((ingredient) {
                    return Chip(
                      label: Text(
                        ingredient,
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Colors.teal,
                      deleteIcon: const Icon(
                        Icons.cancel,
                        size: 18,
                        color: Colors.white,
                      ),
                      onDeleted: () {
                        setState(() {
                          _selectedIngredients.remove(ingredient);
                        });
                      },
                    );
                  }).toList(),
                ),
              const SizedBox(height: 16),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  backgroundColor: Colors.teal,
                ),
                onPressed: () async {
                  if (_selectedIngredients.isEmpty) return;
                  setState(() {
                    _isLoading = true;
                    _searchError = null;
                  });

                  try {
                    final results =
                        await NetworkApiController.searchGlobalRecipesByMultipleIngredients(
                          _selectedIngredients,
                        );
                    if (!mounted) return;
                    setState(() {
                      _searchResults = results;
                      _hasSearched = true;
                    });
                  } catch (error) {
                    if (!mounted) return;
                    setState(() {
                      _searchResults = [];
                      _searchError =
                          "${AppLocalizations.of(context).translate('search_error_lbl')}: $error";
                    });
                  } finally {
                    if (mounted) {
                      setState(() => _isLoading = false);
                    }
                  }
                },
                child: Text(
                  AppLocalizations.of(context).translate('smart_search_lbl'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              if (_searchError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _searchError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_hasSearched &&
                  _searchError == null &&
                  _searchResults.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    AppLocalizations.of(context).translate('no_results_lbl2'),
                  ),
                ),

              // ГЛОБАЛЬНЫЕ РЕЗУЛЬТАТЫ ОБЛАЧНОГО ПОИСКА
              ..._searchResults.map(
                (recipe) => Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListTile(
                    leading: recipe['main_image']?.toString().isNotEmpty == true
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              recipe['main_image'].toString(),
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.restaurant,
                                color: Colors.teal,
                              ),
                            ),
                          )
                        : const Icon(Icons.restaurant, color: Colors.teal),
                    title: Text(
                      recipe['title'] ??
                          AppLocalizations.of(
                            context,
                          ).translate('no_title_lbl1'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      recipe['author_name']?.toString() ??
                          AppLocalizations.of(
                            context,
                          ).translate('no_author_lbl'),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios,
                      size: 12,
                      color: Colors.teal,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RecipeDetailPage(recipe: recipe),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
  }
}

class UserProfilePage extends StatefulWidget {
  final Map<String, dynamic> userProfile;
  final Map<String, bool> activeAllergens;
  final VoidCallback onLogout;

  const UserProfilePage({
    super.key,
    required this.userProfile,
    required this.activeAllergens,
    required this.onLogout,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late String _avatarUrl;
  bool _isUploadingAvatar = false;
  bool _isDeletingAccount = false;
  bool _isRefreshingAvatar = false;
  int _avatarRefreshKey = 0;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.userProfile['avatar_url']?.toString() ?? '';
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) {
        if (results.any((result) => result != ConnectivityResult.none)) {
          _refreshAvatarFromServer();
        }
      },
      onError: (Object error) {
        debugPrint('Failed to observe connectivity for profile avatar: $error');
      },
    );
    _restoreCachedAvatar();
    _refreshAvatarIfOnline();
  }

  Future<void> _restoreCachedAvatar() async {
    final userId = widget.userProfile['id']?.toString();
    if (userId == null || userId.isEmpty) return;

    final cachedUrl = await LocalCacheController.getProfileAvatarUrl(userId);
    if (!mounted || cachedUrl == null || cachedUrl.isEmpty) return;
    if (_avatarUrl.isNotEmpty) return;

    setState(() {
      _avatarUrl = cachedUrl;
      widget.userProfile['avatar_url'] = cachedUrl;
      _avatarRefreshKey++;
    });
  }

  Future<void> _refreshAvatarIfOnline() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.any((result) => result != ConnectivityResult.none)) {
        await _refreshAvatarFromServer();
      }
    } catch (error) {
      debugPrint('Failed to check connectivity for profile avatar: $error');
    }
  }

  Future<void> _refreshAvatarFromServer() async {
    final userId = widget.userProfile['id']?.toString();
    if (userId == null || userId.isEmpty || _isRefreshingAvatar) return;

    _isRefreshingAvatar = true;
    try {
      final avatarUrl = await NetworkApiController.fetchCurrentUserAvatarUrl(
        userId: userId,
      );
      await LocalCacheController.saveProfileAvatarUrl(userId, avatarUrl);
      if (!mounted) return;

      setState(() {
        widget.userProfile['avatar_url'] = avatarUrl;
        _avatarUrl = avatarUrl;
        _avatarRefreshKey++;
      });
    } catch (error) {
      debugPrint('Failed to refresh profile avatar: $error');
    } finally {
      _isRefreshingAvatar = false;
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _changeAvatar() async {
    if (_isUploadingAvatar) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final image = await ImagePickerService.pickAndCompressImageOrThrow();
      if (!mounted) return;
      if (image == null) {
        setState(() => _isUploadingAvatar = false);
        return;
      }

      final result = await NetworkApiController.updateUserAvatar(
        image,
        userId: widget.userProfile['id'].toString(),
      );
      widget.userProfile['avatar_url'] = result.avatarUrl;
      await LocalCacheController.saveProfileAvatarUrl(
        widget.userProfile['id'].toString(),
        result.avatarUrl,
      );
      if (!mounted) return;

      setState(() {
        _avatarUrl = result.avatarUrl;
        _avatarRefreshKey++;
        _isUploadingAvatar = false;
      });

      final localizations = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.previousAvatarDeleted
                ? localizations.translate('photo_upload_success_lbl')
                : localizations.translate('avatar_cleanup_warning'),
          ),
          backgroundColor: result.previousAvatarDeleted
              ? Colors.green
              : Colors.orange,
        ),
      );
    } catch (error) {
      debugPrint('Failed to update profile avatar: $error');
      if (!mounted) return;

      setState(() => _isUploadingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate('photo_upload_unsuccess'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteLocalAccount() async {
    if (_isDeletingAccount) return;

    final localizations = AppLocalizations.of(context);
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.translate('delete_account_title_lbl')),
        content: Text(localizations.translate('delete_account_warning_lbl')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(localizations.translate('discard_chng_lbl')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(localizations.translate('delete_local_account_lbl')),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;

    setState(() => _isDeletingAccount = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final userId = widget.userProfile['id']?.toString();
      if (userId == null || userId.isEmpty) {
        throw StateError('The profile has no account ID.');
      }

      final isar = Provider.of<Isar>(context, listen: false);
      final recipes = await isar.recipes
          .filter()
          .authorIdEqualTo(userId)
          .findAll();
      final localImagePaths = <String>{
        for (final recipe in recipes)
          if (recipe.localMainImage != null &&
              !recipe.localMainImage!.startsWith('http'))
            recipe.localMainImage!,
        for (final recipe in recipes)
          ...?recipe.localAdditionalImages?.where(
            (path) => !path.startsWith('http'),
          ),
      };

      for (final imagePath in localImagePaths) {
        final imageFile = File(imagePath);
        if (await imageFile.exists()) {
          await imageFile.delete();
        }
      }

      await isar.writeTxn(() async {
        await isar.recipes.deleteAll(
          recipes.map((recipe) => recipe.id).toList(),
        );
        await isar.allergens.clear();
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_allergens_$userId');
      await prefs.remove('profile_avatar_$userId');

      await NetworkApiController.endCurrentSession(expectedUserId: userId);

      if (mounted) {
        final authRepository = Provider.of<AuthRepository>(
          context,
          listen: false,
        );

        await authRepository.logout();
      }
      widget.onLogout();
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(localizations.translate('local_account_deleted_lbl')),
        ),
      );
    } catch (error) {
      debugPrint('Failed to clear local account data and end session: $error');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${localizations.translate('local_account_delete_failed_lbl')} $error',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeletingAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).translate('profile_page')),
        backgroundColor: Colors.teal,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: Colors.teal.shade100,
                      child: _avatarUrl.isEmpty
                          ? const Icon(
                              Icons.person,
                              size: 52,
                              color: Colors.teal,
                            )
                          : ClipOval(
                              child: CachedNetworkImage(
                                key: ValueKey('$_avatarUrl-$_avatarRefreshKey'),
                                imageUrl: _avatarUrl,
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => const Icon(
                                  Icons.person,
                                  size: 52,
                                  color: Colors.teal,
                                ),
                              ),
                            ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Material(
                        color: Colors.teal,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: AppLocalizations.of(context).translate(
                            _avatarUrl.isEmpty
                                ? 'avatar_add_lbl'
                                : 'avatar_change_lbl',
                          ),
                          onPressed: _isUploadingAvatar ? null : _changeAvatar,
                          icon: _isUploadingAvatar
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 18,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _isUploadingAvatar ? null : _changeAvatar,
                  icon: const Icon(Icons.add_a_photo),
                  label: Text(
                    AppLocalizations.of(context).translate(
                      _avatarUrl.isEmpty
                          ? 'avatar_add_lbl'
                          : 'avatar_change_lbl',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.userProfile['login'] ?? 'Шеф-Повар',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Տեղադրեք սա ձեր user_profile_page.dart-ի ListView-ի մեջ՝ Ալերգենների Divider-ից առաջ
          const Divider(height: 30),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Text(
              AppLocalizations.of(context).translate('lng_slct_lbl'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
          ),
          // 🌟 ԻՍՊՐԱՎЛЕНՈ: Հին 3 կոճակները փոխարինվել են մաքուր բացվող Dropdown ցուցակով
          DropdownButtonFormField<String>(
            initialValue: Localizations.localeOf(
              context,
            ).languageCode, // Ավտոմատ վերցնում է ընթացիկ ակտիվ լեզուն [4.2]
            decoration: InputDecoration(
              //border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              filled: true,
              fillColor: Colors.orange.shade50, // Նարնջագույն թեթև ֆոն
            ),
            dropdownColor: Colors.orange.shade50,
            icon: const Icon(Icons.language, color: Colors.orange),
            items: const [
              DropdownMenuItem(
                value: 'ru',
                child: Text(
                  '🇷🇺 Русский',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DropdownMenuItem(
                value: 'hy',
                child: Text(
                  '🇦🇲 Հայերեն',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DropdownMenuItem(
                value: 'en',
                child: Text(
                  '🇺🇸 English',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
            onChanged: (String? newLangCode) {
              if (newLangCode != null) {
                // Ակնթարթորեն միացնում է ընտրված լեզուն main.dart-ում [4.2]
                MyApp.setLocale(context, Locale(newLangCode));
              }
            },
          ),

          const Divider(height: 30),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            child: Text(
              AppLocalizations.of(context).translate('your_allergens_lbl'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
          ),

          Card(
            elevation: 2,
            child: Column(
              children: [
                _buildAllergenSwitch(
                  'nuts',
                  AppLocalizations.of(context).translate('nuts_lbl3'),
                ),
                _buildAllergenSwitch(
                  'lactose',
                  AppLocalizations.of(context).translate('lactose_lbl3'),
                ),
                _buildAllergenSwitch(
                  'gluten',
                  AppLocalizations.of(context).translate('gluten_lbl3'),
                ),
              ],
            ),
          ),
          const Divider(height: 30),

          _buildTile(
            Icons.password,
            AppLocalizations.of(context).translate('psw_chnge_lbl'),
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChangePasswordScreen(
                  userLogin:
                      widget.userProfile['login'] ??
                      AppLocalizations.of(context).translate('chef_lbl'),
                ),
              ),
            ),
          ),
          //  _buildTile(Icons.menu_book, 'Мои рецепты в базе', () => Navigator.push(context, MaterialPageRoute(builder: (context) => UserRecipesScreen(userLogin: widget.userProfile['login'] ?? 'Повар')))),
          _buildTile(
            Icons.support_agent,
            AppLocalizations.of(context).translate('contact_admin_lbl'),
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AdminTicketScreen(
                  userLogin:
                      widget.userProfile['login'] ??
                      AppLocalizations.of(context).translate('chef_lbl'),
                ),
              ),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: Text(AppLocalizations.of(context).translate('logout_lbl')),
            onTap: () async {
              // ИСПОЛЬЗУЕМ ISAR ДЛЯ ВЫХОДА ИЗ СЕССИИ
              final authRepo = Provider.of<AuthRepository>(
                context,
                listen: false,
              );
              await authRepo.logout();

              widget.onLogout();
              if (context.mounted) Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: Text(
              AppLocalizations.of(
                context,
              ).translate('delete_local_account_lbl'),
              style: const TextStyle(color: Colors.red),
            ),
            subtitle: Text(
              AppLocalizations.of(
                context,
              ).translate('delete_account_local_only_lbl'),
            ),
            trailing: _isDeletingAccount
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            enabled: !_isDeletingAccount,
            onTap: _deleteLocalAccount,
          ),
        ],
      ),
    );
  }

  Widget _buildAllergenSwitch(String key, String title) {
    return SwitchListTile(
      title: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      activeThumbColor: Colors.teal,
      value: widget.activeAllergens[key] ?? false,
      onChanged: (bool value) async {
        setState(() => widget.activeAllergens[key] = value);

        final userId = widget.userProfile['id']?.toString();
        if (userId == null || userId.isEmpty) {
          setState(() => widget.activeAllergens[key] = !value);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).translate('settings_missing_lbl'),
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        try {
          final prefs = await SharedPreferences.getInstance();
          final selectedAllergens = widget.activeAllergens.entries
              .where((entry) => entry.value)
              .map((entry) => entry.key)
              .toList();
          final saved = await prefs.setStringList(
            'active_allergens_$userId',
            selectedAllergens,
          );
          if (!saved) {
            throw StateError('Failed to persist allergen preferences.');
          }
          if (!mounted) return;
        } catch (error) {
          debugPrint('Failed to save allergen preferences: $error');
          if (mounted) {
            setState(() => widget.activeAllergens[key] = !value);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(
                    context,
                  ).translate('settings_missing_lbl'),
                ),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
        }

        // СОХРАНЯЕМ В ЛՈԿԱЛЬНУЮ БАЗУ ДАННЫХ ИЗМЕНЕНИЯ И ЗАПУСКАЕМ СИНХРОНИЗАЦИЮ
        final isar = Provider.of<Isar>(context, listen: false);
        final syncService = Provider.of<SyncService>(context, listen: false);

        await isar.writeTxn(() async {
          final existing = await isar.allergens
              .filter()
              .nameEqualTo(key)
              .findFirst();
          if (value && existing == null) {
            await isar.allergens.put(Allergen()..name = key);
          } else if (!value && existing != null) {
            await isar.allergens.delete(existing.id);
          }

          // Помечаем профиль пользователя как несинхронизированный
          final user = await isar.userProfiles.where().findFirst();
          if (user != null) {
            user.isSynced = false;
            await isar.userProfiles.put(user);
          }
        });

        // Пингуем фоновую синхронизацию с Appwrite
        syncService.syncDataWithServer();
      },
    );
  }

  Widget _buildTile(
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color? color,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color ?? Colors.blueGrey),
        title: Text(title, style: const TextStyle(fontSize: 13)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 12),
        onTap: onTap,
      ),
    );
  }
}

// ==========================================================
// ЭКРАН АВТОРИЗАЦИИ (ВХОД)
// ==========================================================
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _loginCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isHidden = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).translate('signin_lbl')),
        backgroundColor: Colors.teal,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextField(
                  controller: _loginCtrl,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(
                        r"""[a-zA-Z0-9!@#$%^&*()_+=\[{\]};:<>|./?,\-~`"'\\]""",
                      ),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(
                      context,
                    ).translate('login_ctrl_lbl'),

                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _isHidden,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(
                        r"""[a-zA-Z0-9!@#$%^&*()_+=\[{\]};:<>|./?,\-~`"'\\]""",
                      ),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(
                      context,
                    ).translate('pswd_lbl'),

                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isHidden ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _isHidden = !_isHidden),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(45),
                    backgroundColor: Colors.teal,
                  ),
                  onPressed: () async {
                    final String inputLogin = _loginCtrl.text.trim();
                    final String inputPassword = _passwordCtrl.text.trim();

                    if (inputLogin.isEmpty || inputPassword.isEmpty) return;

                    final navigator = Navigator.of(context);
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    final authRepo = Provider.of<AuthRepository>(
                      context,
                      listen: false,
                    );

                    final isar = Provider.of<Isar>(context, listen: false);

                    // Ցուցադրում ենք սպասման լոադերը
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const Center(
                        child: CircularProgressIndicator(color: Colors.teal),
                      ),
                    );

                    try {
                      // 1. ԿԱՆՉՈՒՄ ԵՆՔ ՈՒՆԻՎԵՐՍԱԼ ԱՎՏՈՐԻԶԱՑԻԱՆ/ԳՐԱՆՑՈՒՄԸ
                      final Map<String, dynamic>? profile =
                          await NetworkApiController.authenticateOrRegister(
                            inputLogin,
                            inputPassword,
                          );

                      // Փակում ենք լոադերը
                      if (context.mounted) navigator.pop();

                      if (profile != null) {
                        // 🎯 ՍՏՈՒԳՈՒՄ ԵՆՔ՝ ԱՐԴՅՈՔ ՍԵՐՎԵՐԸ ՆԵՐՔԻՆ ՍԽԱԼ Է ՎԵՐԱԴԱՐՁՐԵԼ
                        if (profile.containsKey('error')) {
                          if (context.mounted) {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  '🚨 system error: ${profile['error']}',
                                ),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 6),
                              ),
                            );
                          }
                          return;
                        }

                        final String newUserId = profile['id'].toString();
                        final String newUserLogin = profile['login'].toString();

                        // 2. 🔐 ՏԵՂԱԿԱՆ ՕՖԼԱՅՆ ՍԵՍԻԱՅԻ ՊԱՀՊԱՆՈՒՄ ԻՍԱՐՈՒՄ
                        await authRepo.saveSession(
                          newUserId,
                          newUserLogin,
                          email: profile['email']?.toString(),
                        );

                        // 3. 🔄 ՕՖԼԱՅՆ ՌԵՑԵՊՏՆԵՐԻ ԱՎՏՈՄԱՏ ՄԻԳՐԱՑԻԱ (ՈՐԴԵԳՐՈՒՄ)
                        // 🎯 ՈՒՂՂՎԱԾ Է. Փնտրում ենք և՛ փոքրատառ "anonymous", և՛ մեծատառ "Anonymous" տարբերակները, որպեսզի ոչ մի տվյալ չկորչի!
                        final localAnonymousRecipes = await isar.recipes
                            .filter()
                            .authorIdEqualTo("anonymous")
                            .or()
                            .authorIdEqualTo("Anonymous")
                            .findAll();

                        if (localAnonymousRecipes.isNotEmpty) {
                          await isar.writeTxn(() async {
                            for (var recipe in localAnonymousRecipes) {
                              recipe.authorId = newUserId;
                              recipe.authorName = newUserLogin;
                              recipe.isSynced = false;
                              await isar.recipes.put(recipe);
                            }
                          });
                          stdout.writeln(
                            "✨ ${localAnonymousRecipes.length} անոնիմ ռեցեպտ կցվեց նոր պրոֆիլին:",
                          );
                        }

                        // 4. 🚀 ԱՎՏՈՄԱՏ ՏՐԻԳԵՐ ՑԱՆՑԱՅԻՆ ՍԻՆԽՐՈՆԱՑՄԱՆ ՀԱՄԱՐ
                        final syncService = SyncService(isar);
                        await syncService.fetchAndSyncFromServer(
                          newUserId,
                          newUserLogin,
                        );
                        syncService.syncDataWithServer();

                        if (context.mounted) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                "${AppLocalizations.of(context).translate('login_success_lbl')} + '$newUserLogin'",
                              ),

                              backgroundColor: Colors.green,
                            ),
                          );
                          navigator.pop(profile);
                        }
                      } else {
                        if (context.mounted) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'consol errores are: returned null from networkapicontroller ',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    } catch (mainError) {
                      // Փակում ենք լոադերը կրեշի դեպքում
                      if (context.mounted) navigator.pop();
                      if (context.mounted) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              "${AppLocalizations.of(context).translate('err_lbl1')} + '$mainError'",
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: Text(
                    AppLocalizations.of(context).translate('enter_lbl'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),

                const SizedBox(height: 16), // Небольшой отступ
                // 🎯 ВОТ СЮДА ВСТАВЛЯЙТЕ ЭТОТ TextButton:
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RegisterScreen(),
                      ),
                    );
                  },
                  child: Text(
                    AppLocalizations.of(context).translate('create_acc_lbl'),
                    style: const TextStyle(
                      color: Colors.teal,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16), // Небольшой отступ
                // 🎯 ВОТ СЮДА ВСТАВЛЯЙТЕ ЭТОТ TextButton:
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const ChangePasswordScreen(userLogin: ''),
                      ),
                    );
                  },
                  child: Text(
                    AppLocalizations.of(
                      context,
                    ).translate('forgotten_pswrd_lbl'),
                    style: const TextStyle(
                      color: Colors.teal,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================================
// ЭКРАН СМЕНЫ ПАРОЛЯ
// ==========================================================
class ChangePasswordScreen extends StatefulWidget {
  final String userLogin;
  const ChangePasswordScreen({super.key, required this.userLogin});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _passwordCtrl = TextEditingController();
  bool _isHidden = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).translate('psw_chng_lbl')),

        backgroundColor: Colors.teal,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _passwordCtrl,
              obscureText: _isHidden,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(
                  context,
                ).translate('new_psw_lbl'),

                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isHidden ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _isHidden = !_isHidden),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: () async {
                // В оффлайн-режиме обновляем профиль локально
                final isar = Provider.of<Isar>(context, listen: false);
                final user = await isar.userProfiles.where().findFirst();
                if (user != null) {
                  await isar.writeTxn(() async {
                    user.isSynced =
                        false; // Требует синхронизации изменений с сервером
                    await isar.userProfiles.put(user);
                  });
                }

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(
                          context,
                        ).translate('local_save_lbl'),
                      ),
                      backgroundColor: Colors.blue,
                    ),
                  );
                  Navigator.pop(context);
                }
              },
              child: Text(
                AppLocalizations.of(context).translate('change_pswd_lbl'),

                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================================
// СТРАНИЦА ОБРАЩЕНИЙ К АДМИНИСТРАЦИИ (TICKETS SERVICE)
// ==========================================================
class AdminTicketScreen extends StatefulWidget {
  final String userLogin;
  const AdminTicketScreen({super.key, required this.userLogin});

  @override
  State<AdminTicketScreen> createState() => _AdminTicketScreenState();
}

class _AdminTicketScreenState extends State<AdminTicketScreen> {
  final _ticketController = TextEditingController();
  List<Map<String, dynamic>> _ticketHistory = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _ticketController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    // Временное хранение простых тикетов в SharedPreferences, чтобы не усложнять Isar
    final prefs = await SharedPreferences.getInstance();
    final String? rawTickets = prefs.getString(
      'user_tickets_${widget.userLogin}',
    );

    if (rawTickets != null) {
      final List<dynamic> decoded = jsonDecode(rawTickets);
      setState(() {
        _ticketHistory = decoded.cast<Map<String, dynamic>>();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).translate('tkt_to_admin_lbl')),

        backgroundColor: Colors.teal,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _ticketController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(
                  context,
                ).translate('msg_text_lbl'),

                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(42),
                backgroundColor: Colors.teal,
              ),
              onPressed: () async {
                if (_ticketController.text.isEmpty) return;

                final newTicket = {
                  'user_login': widget.userLogin,
                  'message_text': _ticketController.text,
                  'created_at': AppLocalizations.of(context).translate('today'),
                  'admin_reply': null,
                };

                final updatedHistory = List<Map<String, dynamic>>.from(
                  _ticketHistory,
                )..add(newTicket);

                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(
                  'user_tickets_${widget.userLogin}',
                  jsonEncode(updatedHistory),
                );

                _ticketController.clear();
                _loadHistory();
              },
              child: Text(
                AppLocalizations.of(context).translate('send'),

                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: _ticketHistory.length,
                itemBuilder: (_, index) {
                  final t = _ticketHistory[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(t['message_text'] ?? ''),
                      subtitle: Text(
                        AppLocalizations.of(context).translate('sts_wait_lbl'),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.teal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/*
// ==========================================================
// СТРАНИЦА ЛИЧНЫХ РЕЦЕПТОВ ПОЛЬЗОВАТЕЛЯ (ВЫВОД ИЗ ISAR DB)
// ==========================================================
class UserRecipesScreen extends StatelessWidget {
  final String userLogin;
  const UserRecipesScreen({super.key, required this.userLogin});

  

  @override
  Widget build(BuildContext context) {
    // Получаем репозиторий рецептов для чтения локальной NoSQL базы данных
    final recipeRepo = Provider.of<RecipeRepository>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Мои личные рецепты'), backgroundColor: Colors.teal),
      body: FutureBuilder<List<Recipe>>(
        future: recipeRepo.getAllLocalRecipes(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.teal));
          }

          final userRecipes = snapshot.data ?? [];
          if (userRecipes.isEmpty) {
            return const Center(child: Text('Вы еще не добавили ни одного рецепта.', style: TextStyle(color: Colors.grey)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: userRecipes.length,
            itemBuilder: (context, index) {
              final recipe = userRecipes[index];
              
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: recipe.localMainImage != null ||
                          recipe.cloudMainImageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image(
                            image: recipe.cloudMainImageUrl != null
                                ? NetworkImage(recipe.cloudMainImageUrl!)
                                : recipe.localMainImage!.startsWith('http')
                                    ? NetworkImage(recipe.localMainImage!)
                                    : FileImage(File(recipe.localMainImage!)),
                            width: 45,
                            height: 45,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(Icons.restaurant, color: Colors.teal),
                  title: Text(recipe.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(
                    recipe.isSynced ? 'Synced ✨' : 'Waiting for network ⏳',
                    style: TextStyle(fontSize: 10, color: recipe.isSynced ? Colors.green : Colors.grey),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 12),
                  onTap: () {
                    // Конвертируем Isar-объект обратно в Map структуру для детального экрана
                    final Map<String, dynamic> convertedRecipe = {
                      'title': recipe.title,
                      'instructions': recipe.description,
                      'ingredients': recipe.textIngredients,
                      'cuisine': recipe.cuisine,
                      'categories': recipe.categoryTypes,
                      'local_image': recipe.localMainImage,
                      'local_additionalImages': recipe.localAdditionalImages,                      
                      'videoLink': recipe.videoLink,
                      'viewsCount': recipe.viewsCount,
                      'author_id': recipe.authorId,
                      'author_name': recipe.authorName,
                    };
                    Navigator.push(
                      context, 
                      MaterialPageRoute(
                        builder: (context) => RecipeDetailPage(
                          recipe: convertedRecipe, 
                         onRecipeUpdated: () => _refreshRecipesList(context)
                        )
                      )
                    );
                  },
                ),
              );
            },
          );
        },
      ),
     
    );
  }
}
*/
// ==========================================================
// ДЕТАЛЬНАЯ СТРАНИЦА РЕЦЕПТА (УМНЫЙ ВЫВОД: ОБЛАКО ИЛИ СМАРТФОН)
// ==========================================================
class RecipeDetailPage extends StatefulWidget {
  final Map<String, dynamic> recipe;
  final VoidCallback? onRecipeUpdated;
  final bool showManagementActions;

  const RecipeDetailPage({
    super.key,
    required this.recipe,
    this.onRecipeUpdated,
    this.showManagementActions = false,
  });

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  late Map<String, dynamic> currentRecipe;

  void _showAdditionalImage(String imagePath) {
    final ImageProvider imageProvider = imagePath.startsWith('http')
        ? NetworkImage(imagePath)
        : FileImage(File(imagePath));

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Image(
                  image: imageProvider,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 32,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    currentRecipe = widget.recipe;
  }

  void _showEditSheet(Map<String, dynamic> recipe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return EditRecipeBottomSheet(
          recipe: recipe,
          onRecipeUpdated: () {
            if (widget.onRecipeUpdated != null) widget.onRecipeUpdated!();
            Navigator.pop(context);
          },
        );
      },
    );
  }

  void _confirmDeleteRecipe(String recipeId, List<String> imageUrls) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context).translate('delete_rcp_lbl')),
            ],
          ),
          content: Text(AppLocalizations.of(context).translate('attn_msg_lbl')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                AppLocalizations.of(context).translate('discard_chng_lbl'),
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(dialogContext);
                final bool ok =
                    await NetworkApiController.deleteRecipeFromCloud(recipeId);
                if (ok) {
                  for (final imageUrl in imageUrls) {
                    await NetworkApiController.deleteFileFromStorage(imageUrl);
                  }
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? AppLocalizations.of(
                                context,
                              ).translate('dlt_scs_lbl')
                            : AppLocalizations.of(
                                context,
                              ).translate('dlt_unscs_lbl'),
                      ),
                      backgroundColor: ok ? Colors.green : Colors.red,
                    ),
                  );
                  if (ok) {
                    if (widget.onRecipeUpdated != null) {
                      widget.onRecipeUpdated!();
                    }
                    Navigator.pop(context);
                  }
                }
              },
              child: Text(
                AppLocalizations.of(context).translate('slct_lbl'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 🎯 ԿԱՐԴՈՒՄ ԵՆՔ ԲՈԼՈՐ ԴԱՇՏԵՐԸ ՌԵՑԵՊՏԻ ՄԻՋԻՑ
    final String title = currentRecipe['title']?.toString() ?? 'Без названия';
    final String description =
        currentRecipe['description']?.toString() ??
        currentRecipe['instructions']?.toString() ??
        '';
    final String authorName =
        currentRecipe['author_name']?.toString() ?? 'Шеф-повар';
    String formatListField(dynamic value) {
      if (value is List) {
        return value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty && item.toLowerCase() != 'null')
            .join(', ');
      }
      if (value == null) return '';

      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') return '';
      if (text.startsWith('[') && text.endsWith(']')) {
        try {
          final decoded = jsonDecode(text);
          if (decoded is List) return formatListField(decoded);
        } on FormatException {
          // Treat non-JSON values as comma-separated text below.
        }
      }
      return text;
    }

    final String cuisine =
        currentRecipe['cuisine']?.toString() ??
        currentRecipe['p_cuisine']?.toString() ??
        '';
    final String ingredients = formatListField(
      currentRecipe['ingredient_list'] ??
          currentRecipe['ingredients_list'] ??
          currentRecipe['ingredientsList'] ??
          currentRecipe['ingredients'] ??
          currentRecipe['ingredients_json'],
    );
    final String categories = formatListField(
      currentRecipe['categories'] ??
          currentRecipe['category_type'] ??
          currentRecipe['categoryTypes'],
    );
    final String allergens = formatListField(
      currentRecipe['allergen_groups'] ??
          currentRecipe['allergenGroups'] ??
          currentRecipe['allergens'],
    );
    final String videoLink =
        currentRecipe['video_link']?.toString() ??
        currentRecipe['videoLink']?.toString() ??
        '';

    final String? mainImageUrl =
        currentRecipe['main_image']?.toString() ??
        currentRecipe['imageUrl']?.toString() ??
        currentRecipe['photo_url']?.toString();

    // Լրացուցիչ նկարների մշակում (List)
    final dynamic rawAdditionalImg =
        currentRecipe['additional_images'] ??
        currentRecipe['additionalimg'] ??
        currentRecipe['localAdditionalImages'] ??
        currentRecipe['local_additionalImages'];
    List<String> additionalImages = [];
    if (rawAdditionalImg is List) {
      additionalImages = rawAdditionalImg.map((e) => e.toString()).toList();
    } else if (rawAdditionalImg is String && rawAdditionalImg.isNotEmpty) {
      additionalImages = rawAdditionalImg
          .split(',')
          .map((e) => e.trim())
          .toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.teal,
        actions: widget.showManagementActions
            ? [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white),
                  onPressed: () => _showEditSheet(currentRecipe),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_forever, color: Colors.white),
                  onPressed: () {
                    final imageUrls = <String>[
                      if (mainImageUrl?.startsWith('http') ?? false)
                        mainImageUrl!,
                      ...additionalImages.where(
                        (url) => url.startsWith('http'),
                      ),
                    ];
                    _confirmDeleteRecipe(
                      currentRecipe['id'].toString(),
                      imageUrls,
                    );
                  },
                ),
              ]
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 🎯 ՊԱՅՄԱՆ 1. ԳԼԽԱՎՈՐ ԼՈՒՍԱՆԿԱՐ (Ցուցադրվում է միայն եթե առկա է)
          if (mainImageUrl != null &&
              mainImageUrl.isNotEmpty &&
              mainImageUrl != 'null')
            Container(
              height: 220,
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                image: DecorationImage(
                  image: mainImageUrl.startsWith('http')
                      ? NetworkImage(mainImageUrl) as ImageProvider
                      : FileImage(File(mainImageUrl)),
                  fit: BoxFit.cover,
                ),
              ),
            ),

          // 📝 ՎԵՐՆԱԳԻՐ ԵՎ ՀԵՂԻՆԱԿ
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "${AppLocalizations.of(context).translate('recipe_author_label')}  $authorName",
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (cuisine.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              " ${AppLocalizations.of(context).translate('recipe_cuisine_label')}  ${cuisine.trim()}",
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (ingredients.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              "${AppLocalizations.of(context).translate('recipe_ingredients_label')}  $ingredients",
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              "${AppLocalizations.of(context).translate('categories')} $categories",
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (allergens.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              "${AppLocalizations.of(context).translate('allergens')} $allergens",
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (videoLink.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              "${AppLocalizations.of(context).translate('video')} ${videoLink.trim()}",
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const Divider(height: 24, thickness: 1),

          // 📖 ՆԿԱՐԱԳՐՈՒԹՅՈՒՆ / ԻՆՍՏՐՈՒԿՑԻԱՆԵՐ
          if (description.isNotEmpty) ...[
            Text(
              AppLocalizations.of(context).translate('prep_method_title'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 16),
          ],

          // 🎯 ՊԱՅՄԱՆ 2. ԼՐԱՑՈՒՑԻՉ ԼՈՒՍԱՆԿԱՐՆԵՐ (Ցուցադրվում են միայն եթե կան)
          if (additionalImages.isNotEmpty) ...[
            Text(
              AppLocalizations.of(context).translate('adtnl_photos_lbl'),
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: additionalImages.length,
                itemBuilder: (context, index) {
                  final imgPath = additionalImages[index];
                  if (imgPath.isEmpty || imgPath == 'null') {
                    return const SizedBox.shrink();
                  }
                  return GestureDetector(
                    onTap: () => _showAdditionalImage(imgPath),
                    child: Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: imgPath.startsWith('http')
                              ? NetworkImage(imgPath) as ImageProvider
                              : FileImage(File(imgPath)),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class MyAuthoredRecipesListScreen extends StatefulWidget {
  final String userId;
  const MyAuthoredRecipesListScreen({super.key, required this.userId});

  @override
  State<MyAuthoredRecipesListScreen> createState() =>
      _MyAuthoredRecipesListScreenState();
}

class _MyAuthoredRecipesListScreenState
    extends State<MyAuthoredRecipesListScreen> {
  List<Map<String, dynamic>> _myRecipes = [];
  bool _isLoading = true;

  Future<void> _refreshRecipesList() async {
    await _loadMyRecipes();
  }

  Future<void> _loadCachedRecipes(Isar isar) async {
    final cachedRecipes = await isar.recipes.where().findAll();
    final authoredRecipes = cachedRecipes
        .where((recipe) => recipe.authorId == widget.userId)
        .map((recipe) {
          final localImages = recipe.localAdditionalImages ?? <String>[];
          final additionalImages = localImages.isNotEmpty
              ? localImages
              : recipe.cloudAdditionalImageUrls ?? <String>[];
          final serverRecipeId = recipe.serverRecipeId;
          return <String, dynamic>{
            'id': serverRecipeId != null && !serverRecipeId.startsWith('local_')
                ? serverRecipeId
                : null,
            'title': recipe.title,
            'instructions': recipe.description,
            'views_count': recipe.viewsCount ?? 0,
            'author_name': recipe.authorName,
            'author_id': recipe.authorId,
            'cuisine': recipe.cuisine,
            'main_image':
                recipe.localMainImage ?? recipe.cloudMainImageUrl ?? '',
            'additional_images': additionalImages,
            'ingredients_json': jsonEncode(recipe.textIngredients),
            'ingredient_list': recipe.textIngredients,
            'ingredients': recipe.textIngredients,
            'categories': recipe.categoryTypes,
            'category_type': recipe.categoryTypes,
            'allergen_groups': recipe.allergenGroups,
            'video_link': recipe.videoLink ?? '',
          };
        })
        .toList();

    if (mounted) {
      setState(() {
        _myRecipes = authoredRecipes;
        _isLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMyRecipes();
  }

  Future<void> _loadMyRecipes() async {
    final isar = Provider.of<Isar>(context, listen: false);
    final syncService = Provider.of<SyncService>(context, listen: false);
    try {
      await _loadCachedRecipes(isar);

      final user = await isar.userProfiles
          .filter()
          .authIdEqualTo(widget.userId)
          .findFirst();

      if (!mounted) return;
      await syncService.fetchAndSyncFromServer(
        widget.userId,
        user?.login ?? widget.userId,
      );

      await _loadCachedRecipes(isar);
    } catch (e) {
      debugPrint('Ошибка при загрузке списка рецептов: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).translate('my_ckbk_lbl2')),
        backgroundColor: Colors.teal,
      ),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : _myRecipes.isEmpty
          ? Center(
              child: Text(
                AppLocalizations.of(context).translate('attn_msg_lbl2'),
              ),
            )
          : ListView.builder(
              itemCount: _myRecipes.length,
              itemBuilder: (context, index) {
                final recipe = _myRecipes[index];
                final title =
                    recipe['title']?.toString() ??
                    recipe['dish']?.toString() ??
                    'Без названия';
                final author =
                    recipe['author_name']?.toString() ??
                    recipe['p_author']?.toString() ??
                    'Не указан';
                final views = recipe['viewscount'] ?? recipe['viewsCount'] ?? 0;
                final instructions =
                    recipe['instructions']?.toString() ??
                    recipe['recipe_instructions']?.toString() ??
                    'Инструкция отсутствует';
                final cuisine =
                    recipe['cuisine']?.toString() ??
                    recipe['p_cuisine']?.toString();

                final rawSource =
                    recipe['source'] ??
                    recipe['source_url'] ??
                    recipe['p_source'];
                final String? source =
                    (rawSource != null &&
                        rawSource.toString().trim() != '0' &&
                        rawSource.toString().trim().toLowerCase() != 'null' &&
                        rawSource.toString().trim().isNotEmpty)
                    ? rawSource.toString().trim()
                    : null;
                final imageUrl =
                    recipe['main_image']?.toString() ??
                    recipe['image_url']?.toString() ??
                    recipe['photo_url']?.toString() ??
                    recipe['p_mainimg']?.toString();
                final imageSize = MediaQuery.of(context).size.shortestSide / 3;

                // 🌟 ԼՐԱՑՈՒՑԻՉ ԼՈՒՍԱՆԿԱՐՆԵՐԻ ՆԵՐԲԵՌՆՈՒՄԸ ԲԱԶԱՅԻՑ

                final dynamic rawAdditionalImg =
                    recipe['additional_images'] ??
                    recipe['p_additionalimg'] ??
                    recipe['additionalimg'] ??
                    recipe['additionalImg'];
                List<String> additionalImages = [];

                if (rawAdditionalImg != null) {
                  if (rawAdditionalImg is List) {
                    additionalImages = rawAdditionalImg
                        .map((e) => e.toString().trim())
                        .where((e) => e.isNotEmpty && e != 'null')
                        .toList();
                  } else if (rawAdditionalImg is String &&
                      rawAdditionalImg.isNotEmpty &&
                      rawAdditionalImg != 'null') {
                    final String cleanStr = rawAdditionalImg.trim();
                    // Проверяем, если строка пришла в формате JSON-массива ["url", "url"]
                    if (cleanStr.startsWith('[') && cleanStr.endsWith(']')) {
                      try {
                        final List<dynamic> decoded = jsonDecode(cleanStr);
                        additionalImages = decoded
                            .map((e) => e.toString().trim())
                            .where((e) => e.isNotEmpty)
                            .toList();
                      } catch (e) {
                        // Если jsonDecode не сработал, чистим скобки вручную
                        additionalImages = cleanStr
                            .replaceAll('[', '')
                            .replaceAll(']', '')
                            .replaceAll('"', '')
                            .replaceAll("'", "")
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList();
                      }
                    } else {
                      // Обычная строка со ссылками через запятую
                      additionalImages = cleanStr
                          .split(',')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList();
                    }
                  }
                }
                return Card(
                  margin: const EdgeInsets.only(bottom: 16.0),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  color: colorScheme.surface,
                  child: Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      onExpansionChanged: (bool isExpanded) {
                        if (isExpanded && recipe['id'] != null) {
                          final int currentViews =
                              (recipe['views_count'] is num)
                              ? (recipe['views_count'] as num).toInt()
                              : 0;
                          NetworkApiController.incrementRecipeView(
                            recipe['id'].toString(),
                            currentViews,
                          );
                        }
                      },
                      //trailing:
                      title: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),

                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    if (imageUrl != null &&
                                        imageUrl.isNotEmpty) {
                                      showDialog(
                                        context: context,
                                        builder: (context) => Dialog.fullscreen(
                                          backgroundColor: Colors.black
                                              .withValues(alpha: 0.9),
                                          child: Stack(
                                            children: [
                                              Positioned.fill(
                                                child: Image(
                                                  image:
                                                      imageUrl.startsWith(
                                                        'http',
                                                      )
                                                      ? NetworkImage(imageUrl)
                                                      : FileImage(
                                                          File(imageUrl),
                                                        ),
                                                  fit: BoxFit.scaleDown,
                                                  errorBuilder: (_, _, _) =>
                                                      const Center(
                                                        child: Icon(
                                                          Icons.auto_awesome,
                                                          color: Colors.white70,
                                                          size: 48,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                              Positioned(
                                                top: 40,
                                                right: 20,
                                                child: IconButton(
                                                  icon: const Icon(
                                                    Icons.close,
                                                    color: Colors.white,
                                                    size: 30,
                                                  ),
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: Container(
                                    height: imageSize,
                                    width: imageSize,
                                    decoration: BoxDecoration(
                                      color:
                                          colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child:
                                        imageUrl != null && imageUrl.isNotEmpty
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Image(
                                              image: imageUrl.startsWith('http')
                                                  ? NetworkImage(imageUrl)
                                                  : FileImage(File(imageUrl)),
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => const Center(
                                                    child: Icon(
                                                      Icons.auto_awesome,
                                                      size: 30,
                                                      color: Colors.teal,
                                                    ),
                                                  ),
                                            ),
                                          )
                                        : const Center(
                                            child: Icon(
                                              Icons.auto_awesome,
                                              size: 30,
                                              color: Colors.teal,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurface,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.visibility,
                                            size: 14,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${AppLocalizations.of(context).translate('recipe_veiws_label')} $views',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (cuisine != null &&
                                          cuisine.isNotEmpty) ...[
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.flag_outlined,
                                              size: 14,
                                              color: Colors.blueGrey,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${AppLocalizations.of(context).translate('recipe_cuisine_label')} $cuisine',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Colors.blueGrey,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      if (source != null) ...[
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.link,
                                              size: 16,
                                              color: Colors.blueGrey,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                '${AppLocalizations.of(context).translate('recipe_source_label')} $source',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.blueGrey,
                                                  decoration:
                                                      TextDecoration.none,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.person,
                                            size: 14,
                                            color: Colors.blueGrey,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '${AppLocalizations.of(context).translate('recipe_author_label')} $author',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Colors.blueGrey,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => RecipeDetailPage(
                                        recipe: recipe,
                                        onRecipeUpdated: _refreshRecipesList,
                                        showManagementActions: true,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).translate('open_rcp_page'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 16.0,
                            right: 16.0,
                            bottom: 16.0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Divider(height: 1, color: Colors.grey),
                              const SizedBox(height: 12),

                              Text(
                                AppLocalizations.of(
                                  context,
                                ).translate('prep_method_title'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                instructions,
                                style: const TextStyle(
                                  height: 1.4,
                                  fontSize: 14,
                                ),
                              ),
                              // 🌟 ԻՍՊՐԱՎԼԵՆՈ: ԼՐԱՑՈՒՑԻՉ ԼՈՒՍԱՆԿԱՐՆԵՐԻ ՀՈՐԻԶՈՆԱԿԱՆ ՑՈՒՑԱԴՐՈՒՄԸ ՔԱՐՏԻ ՄԵՋ
                              if (additionalImages.isNotEmpty) ...[
                                const SizedBox(height: 16),

                                Text(
                                  AppLocalizations.of(
                                    context,
                                  ).translate('recipe_adtnl_img_label'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                    fontSize: 13,
                                  ),
                                ),

                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 80,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: additionalImages.length,
                                    itemBuilder: (context, imgIdx) {
                                      final url = additionalImages[imgIdx];
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8.0,
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: url.startsWith('http')
                                              ? Image.network(
                                                  url,
                                                  width: 80,
                                                  height: 80,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (c, e, s) =>
                                                      Container(
                                                        width: 80,
                                                        color: Colors.grey,
                                                        child: const Icon(
                                                          Icons.broken_image,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                )
                                              : Image.file(
                                                  File(url),
                                                  width: 80,
                                                  height: 80,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (c, e, s) =>
                                                      Container(
                                                        width: 80,
                                                        color: Colors.grey,
                                                        child: const Icon(
                                                          Icons.broken_image,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
