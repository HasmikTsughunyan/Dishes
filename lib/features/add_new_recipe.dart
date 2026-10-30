import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:isar_community/isar.dart';
//import 'package:path/path.dart' as p;
import 'package:my_cookbook/utils/image_picker_service.dart';
import 'package:my_cookbook/features/products/data/recipe_repository.dart';
import 'package:my_cookbook/features/auth/data/auth_repository.dart';
//import 'package:my_cookbook/features/allergens/data/models/schemas.dart';
import 'package:my_cookbook/core/services/sync_service.dart';
import 'package:my_cookbook/utils/app_localizations.dart';

class AddRecipeScreen extends StatefulWidget {
  const AddRecipeScreen({super.key});

  @override
  State<AddRecipeScreen> createState() => _AddRecipeScreenState();
}

class _AddRecipeScreenState extends State<AddRecipeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _cuisineCtrl = TextEditingController(); // 🎯 ՈՒՂՂՎԱԾ Է
  final _videoLinkCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController(); // 🎯 Սա Ինստրուկցիան է

  List<Map<String, String>> get _availableCategories => [
    {
      'title': AppLocalizations.of(context).translate('cat_hot_dishes'),
      'type': 'горячее',
    },
    {
      'title': AppLocalizations.of(context).translate('cat_salads'),
      'type': 'салаты',
    },
    {
      'title': AppLocalizations.of(context).translate('cat_desserts'),
      'type': 'десерты',
    },
    {
      'title': AppLocalizations.of(context).translate('cat_vegetables'),
      'type': 'овощи',
    },
    {
      'title': AppLocalizations.of(context).translate('cat_drinks'),
      'type': 'напитки',
    },
    {
      'title': AppLocalizations.of(context).translate('cat_else'),
      'type': 'другие',
    },
  ];

  final List<String> _selectedCategories = [];

  File? _mainImage;
  final List<File> _additionalImages = []; // 🎯 Լրացուցիչ նկարների զանգված

  final List<TextEditingController> _ingredientCtrls = [
    TextEditingController(),
  ];
  final Map<String, bool> _allergensMap = {
    'nuts': false,
    'lactose': false,
    'gluten': false,
  };

  @override
  void dispose() {
    _titleCtrl.dispose();
    _cuisineCtrl.dispose();
    _videoLinkCtrl.dispose();
    _descriptionCtrl.dispose();
    for (var c in _ingredientCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).translate('add_rcp_lbl')),
        backgroundColor: Colors.teal.shade700,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. Անվանում և Խոհանոց
            TextFormField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(
                  context,
                ).translate('recipe_title'),
                border: const OutlineInputBorder(),
              ),
              validator: (v) => v!.isEmpty
                  ? AppLocalizations.of(context).translate('add_title')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cuisineCtrl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).translate('kitchen'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // 2. 🎯 ԲԱԶՄԱԿԻ ԿԱՏԵԳՈՐԻԱՆԵՐԻ ՉԻՊԵՐ (Chips)
            Text(
              AppLocalizations.of(context).translate('choose_categories'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: _availableCategories.map((category) {
                final title = category['title']!;
                final type = category['type']!;
                final isSelected = _selectedCategories.contains(type);
                return CheckboxListTile(
                  title: Text(title),
                  value: isSelected,
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        _selectedCategories.add(type);
                      } else {
                        _selectedCategories.remove(type);
                      }
                    });
                  },
                );
                /*    FilterChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: colorScheme.primaryContainer,
                  checkmarkColor: colorScheme.primary,
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _selectedCategories.add(cat);
                      } else {
                        _selectedCategories.remove(cat);
                      }
                    });
                  },
                );*/
              }).toList(),
            ),
            const SizedBox(height: 16),

            // 3. 📷 ԳԼԽԱՎՈՐ ԼՈՒՍԱՆԿԱՐ (Optional)
            Text(
              AppLocalizations.of(context).translate('gen_photo_lbl'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final File? file =
                        await ImagePickerService.pickAndCompressImage();
                    if (file != null) setState(() => _mainImage = file);
                  },
                  icon: const Icon(Icons.add_a_photo),
                  label: Text(
                    AppLocalizations.of(context).translate('choose_main_image'),
                  ),

                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                _mainImage != null
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : Text(
                        AppLocalizations.of(context).translate('not_choosen'),
                      ),
              ],
            ),
            const SizedBox(height: 16),

            // 4. 🎞️ ԼՐԱՑՈՒՑԻՉ ԼՈՒՍԱՆԿԱՐՆԵՐ (Optional, մինչև 3 հատ)
            Text(
              AppLocalizations.of(context).translate('additional_photos_lbl'),

              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            ElevatedButton.icon(
              onPressed: _additionalImages.length >= 3
                  ? null
                  : () async {
                      final File? file =
                          await ImagePickerService.pickAndCompressImage();
                      if (file != null) {
                        setState(() => _additionalImages.add(file));
                      }
                    },
              icon: const Icon(Icons.collections),
              label: Text(
                AppLocalizations.of(context).translate('add_photos'),
                /*(({_additionalImages.length}/3)*/
              ),
            ),
            if (_additionalImages.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _additionalImages.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Stack(
                        children: [
                          Image.file(
                            _additionalImages[index],
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: GestureDetector(
                              onTap: () => setState(
                                () => _additionalImages.removeAt(index),
                              ),
                              child: Container(
                                color: Colors.black54,
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
            const Divider(height: 30),

            // 5. 🥕 ԴԻՆԱՄԻԿ ԲԱՂԱԴՐԻՉՆԵՐ (Զանգված որոնման համար)
            Text(
              AppLocalizations.of(context).translate('recipe_ingredients_lbl'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            ...List.generate(_ingredientCtrls.length, (idx) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ingredientCtrls[idx],
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(
                            context,
                          ).translate('product'), //#({idx + 1})
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () =>
                          setState(() => _ingredientCtrls.removeAt(idx)),
                    ),
                  ],
                ),
              );
            }),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _ingredientCtrls.add(TextEditingController())),
              icon: const Icon(Icons.add),
              label: Text(
                AppLocalizations.of(context).translate('add_product'),
              ),
            ),

            const SizedBox(height: 12),
            TextFormField(
              controller: _videoLinkCtrl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).translate('video_link'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionCtrl,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(
                  context,
                ).translate('prep_method_title'),
                border: const OutlineInputBorder(),
              ),
              validator: (v) => v!.isEmpty
                  ? AppLocalizations.of(context).translate('input_instruction')
                  : null,
            ),

            const Divider(height: 30),

            // 6. 💾 ԿՈՃԱԿ ՍԱՀՄԱՆԵԼՈՒ (SAVE)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(45),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              onPressed: () async {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                final otherCategory = AppLocalizations.of(
                  context,
                ).translate('cat_else');
                final savedMessage = AppLocalizations.of(
                  context,
                ).translate('msg_label2');

                if (!_formKey.currentState!.validate()) return;

                final isar = Provider.of<Isar>(context, listen: false);
                final recipeRepo = Provider.of<RecipeRepository>(
                  context,
                  listen: false,
                );

                final authRepo = Provider.of<AuthRepository>(
                  context,
                  listen: false,
                );
                final localUser = await authRepo.getCurrentUser();
                if (!mounted) return;
                //    final isar = Provider.of<Isar>(context, listen: false);

                final ingredients = _ingredientCtrls
                    .map((c) => c.text.trim())
                    .where((text) => text.isNotEmpty)
                    .toList();
                debugPrint('Ingredients are: $ingredients');

                final List<String> selectedAllergensList = _allergensMap.entries
                    .where((entry) => entry.value == true)
                    .map((entry) => entry.key)
                    .toList();

                debugPrint('Selected allergens are: $selectedAllergensList');

                await recipeRepo.saveRecipe(
                  title: _titleCtrl.text.trim(),
                  description: _descriptionCtrl.text.trim(),
                  currentUserId: localUser?.authId ?? "Anonymous",
                  authorName: localUser?.login ?? "Guest",
                  categories: _selectedCategories.isEmpty
                      ? [otherCategory]
                      : _selectedCategories, // 🎯 Բազմակի կատեգորիաներ
                  cuisine: _cuisineCtrl.text.trim(),

                  selectedAllergens: selectedAllergensList,
                  textIngredients: ingredients,
                  pickedMainImageFile: _mainImage,
                  pickedAdditionalImagesFiles:
                      _additionalImages, // 🎯 Լրացուցիչ նկարներ ստեղծելիս
                );
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(savedMessage),

                    backgroundColor: Colors.green,
                  ),
                );
                // 🎯 ПРИНУДИТЕЛЬНЫЙ ТРИГГЕР: Вызываем синхронизацию напрямую, в обход слушателя сети!
                final syncService = SyncService(isar);
                await syncService.syncRecipes(localUser!);

                if (mounted) navigator.pop();
              },

              child: Text(
                AppLocalizations.of(context).translate('create_new_recipe'),

                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
