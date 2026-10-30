// lib/features/my_recipes/widgets/edit_recipe_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:my_cookbook/utils/image_picker_service.dart';
import '../core/services/network_service/network_api_conroller.dart';
import '../utils/app_localizations.dart';
import 'dart:convert';
import 'dart:io';
//import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';                 // 🎯 ДОБАВЛЕНО для доступа к Isar
import 'package:isar_community/isar.dart';                        // 🎯 ДОБАВЛЕНО для NoSQL транзакций
import '../features/allergens/data/models/schemas.dart';        // 🎯 ДОБАВЛЕНО: Импортируйте вашу схему Recipe

class EditRecipeBottomSheet extends StatefulWidget {
  final Map<String, dynamic> recipe;
  final VoidCallback onRecipeUpdated; 

  const EditRecipeBottomSheet({
    super.key,
    required this.recipe,
    required this.onRecipeUpdated,
  });

  @override
  State<EditRecipeBottomSheet> createState() => _EditRecipeBottomSheetState();
}

class _EditRecipeBottomSheetState extends State<EditRecipeBottomSheet> {
  late TextEditingController _titleCtrl;
  late TextEditingController _stepsCtrl;
  late TextEditingController _sourceCtrl;
  late TextEditingController _cuisineCtrl;
  late TextEditingController _authorCtrl;
  late TextEditingController _mainPhotoCtrl;

  final List<TextEditingController> _additionalPhotosCtrls = [];
  final List<TextEditingController> _ingredientListCtrls = [];
  
  get _availableCategories => [
    {'title': AppLocalizations.of(context).translate('cat_hot_dishes'), 'type': 'горячее'},
    {'title': AppLocalizations.of(context).translate('cat_salads'), 'type': 'салаты'},
    {'title': AppLocalizations.of(context).translate('cat_desserts'), 'type': 'десерты' },
    {'title': AppLocalizations.of(context).translate('cat_vegetables'), 'type': 'овощи'}, 
    {'title': AppLocalizations.of(context).translate('cat_drinks'), 'type': 'напитки'},
    {'title': AppLocalizations.of(context).translate('cat_else'), 'type': 'другие'},
  ];
  final List<String> _selectedCategories = [];

  final Map<int, bool> _uploadingAdditionalLoading = {};
  final Map<String, bool> _allergensMap = {
    'nuts': false,
    'lactose': false,
    'gluten': false,
  };

  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(
      text: widget.recipe['title']?.toString() ?? widget.recipe['dish']?.toString() ?? '',
    );
    _cuisineCtrl = TextEditingController(
      text: widget.recipe['cuisine']?.toString() ?? '',
    );
    _authorCtrl = TextEditingController(
      text: widget.recipe['author']?.toString() ?? widget.recipe['author_name'] ?? '',
    );

    final dynamic rawCategoriesList = widget.recipe['categories'] ?? widget.recipe['category_type'] ?? widget.recipe['categoryTypes'];
    List<String> recipeCategories = [];
    if (rawCategoriesList is List) {
      recipeCategories = rawCategoriesList.map((category) => category.toString().trim()).where((category) => category.isNotEmpty).toList();
    } else if (rawCategoriesList is String && rawCategoriesList.isNotEmpty && rawCategoriesList != 'null') {
      final value = rawCategoriesList.trim();
      if (value.startsWith('[') && value.endsWith(']')) {
        try {
          final decoded = jsonDecode(value);
          recipeCategories = decoded is List ? decoded.map((category) => category.toString().trim()).where((category) => category.isNotEmpty).toList() : [];
        } on FormatException {
          recipeCategories = value.substring(1, value.length - 1).split(',').map((category) => category.trim().replaceAll('"', '')).where((category) => category.isNotEmpty).toList();
        }
      } else {
        recipeCategories = value.split(',').map((category) => category.trim()).where((category) => category.isNotEmpty).toList();
      }
    }
    _selectedCategories.addAll(recipeCategories);

    _mainPhotoCtrl = TextEditingController(
      text: widget.recipe['main_image']?.toString() ?? widget.recipe['photo_url']?.toString() ?? '',
    );
    _stepsCtrl = TextEditingController(
      text: widget.recipe['instructions']?.toString() ?? widget.recipe['descriptions']?.toString() ?? '',
    );
    _sourceCtrl = TextEditingController(
      text: widget.recipe['source']?.toString() ?? widget.recipe['video_link'] ?? '',
    );

    final rawIngredientList = widget.recipe['ingredient_list'] ?? widget.recipe['ingredients_list'] ?? widget.recipe['ingredients'] ?? widget.recipe['ingredients_json'] ?? '';
    if (rawIngredientList != null) {
      if (rawIngredientList is List) {
        for (var ingredient in rawIngredientList) {
          _ingredientListCtrls.add(TextEditingController(text: ingredient.toString()));
        }
      } else if (rawIngredientList is String && rawIngredientList.isNotEmpty && rawIngredientList != 'null') {
        final String value = rawIngredientList.trim();
        List<String> splitIngredients = [];
        if (value.startsWith('[') && value.endsWith(']')) {
          try {
            final decoded = jsonDecode(value);
            splitIngredients = decoded is List ? decoded.map((ingredient) => ingredient.toString().trim()).where((ingredient) => ingredient.isNotEmpty).toList() : [];
          } on FormatException {
            splitIngredients = value.substring(1, value.length - 1).split(',').map((ingredient) => ingredient.trim().replaceAll('"', '')).where((ingredient) => ingredient.isNotEmpty).toList();
          }
        } else {
          splitIngredients = value.split(',').map((ingredient) => ingredient.trim()).where((ingredient) => ingredient.isNotEmpty).toList();
        }
        for (var ingredient in splitIngredients) {
          _ingredientListCtrls.add(TextEditingController(text: ingredient.toString()));
        }
      }
    }

    final dynamic rawAdditionalImg = widget.recipe['additional_images'] ?? widget.recipe['additional_image'];
    if (rawAdditionalImg != null) {
      if (rawAdditionalImg is List) {
        for (var url in rawAdditionalImg) {
          _additionalPhotosCtrls.add(TextEditingController(text: url.toString()));
        }
      } else if (rawAdditionalImg is String && rawAdditionalImg.isNotEmpty && rawAdditionalImg != 'null') {
        final List<String> splitUrls = rawAdditionalImg.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        for (var url in splitUrls) {
          _additionalPhotosCtrls.add(TextEditingController(text: url));
        }
      }
    }
  }

  void _addAdditionalPhotoField() {
    if (_additionalPhotosCtrls.length < 3) {
      setState(() {
        _additionalPhotosCtrls.add(TextEditingController());
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).translate('attn_msg_lbl3'))),
      );
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _cuisineCtrl.dispose();
    _authorCtrl.dispose();
    _mainPhotoCtrl.dispose();
    _stepsCtrl.dispose();
    _sourceCtrl.dispose();
    for (var ctrl in _additionalPhotosCtrls) { ctrl.dispose(); }
    for (var ctrl in _ingredientListCtrls) { ctrl.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        top: 20,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context).translate('rcp_edit_lbl'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).translate('dish_title_lbl'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _authorCtrl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).translate('recipe_author_label'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cuisineCtrl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).translate('recipe_cuisine_label'),
                border: const OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),
                        // 📊 ԿԱՏԵԳՈՐԻԱՆԵՐԻ ՑՈՒՑԱԴՐՈՒՄԸ ԷԿՐԱՆԻՆ (Դարձնում ենք ակտիվ և կանչված)
            Wrap(
              spacing: 8,
              children: _availableCategories.map<Widget>((cat) {
                final String type = cat['type'] ?? 'другие';
                final String title = cat['title'] ?? '';
                
                // Ստուգում ենք՝ արդյո՞ք այս տիպը արդեն ընտրված է ռեցեպտի մեջ
                final isSelected = _selectedCategories.contains(type);

                return FilterChip(
                  label: Text(title),
                  selected: isSelected,
                  selectedColor: colorScheme.primary.withValues(alpha: 0.2),
                  checkmarkColor: colorScheme.primary,
                  onSelected: (bool value) {
                    setState(() {
                      if (value == true) {
                        _selectedCategories.add(type); // Ավելացնում ենք ընտրվածների մեջ
                      } else {
                        _selectedCategories.remove(type); // Հեռացնում ենք
                      }
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).translate('recipe_ingredients_lbl'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            ..._ingredientListCtrls.asMap().entries.map((entry) {
              final index = entry.key;
              final controller = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(context).translate('product'),
border: const OutlineInputBorder(),
),
),
),
IconButton(
icon: const Icon(Icons.delete, color: Colors.red),
onPressed: () {
setState(() { _ingredientListCtrls.removeAt(index).dispose(); });
},
),
],
),
);
}),
TextButton.icon(
onPressed: () {
setState(() { _ingredientListCtrls.add(TextEditingController()); });
},
icon: const Icon(Icons.add),
label: Text(AppLocalizations.of(context).translate('add_product')),
),
const SizedBox(height: 16),
TextField(
controller: _mainPhotoCtrl,
decoration: InputDecoration(
labelText: AppLocalizations.of(context).translate('main_pht_lbl'),
border: const OutlineInputBorder(),
suffixIcon: _isUploadingPhoto
? Padding(
padding: const EdgeInsets.all(12.0),
child: SizedBox(
width: 20, height: 20,
child: CircularProgressIndicator(color: colorScheme.primary, strokeWidth: 2),
),
)
: IconButton(
icon: Icon(Icons.add_a_photo, color: colorScheme.primary),
onPressed: () async {
final scaffoldMessenger = ScaffoldMessenger.of(context);
final uploadSuccessMessage = AppLocalizations.of(context).translate('pht_upld_scs_lbl');
final uploadFailureMessage = AppLocalizations.of(context).translate('pht_upld_unscs_lbl');
final File? pickedData = await ImagePickerService.pickAndCompressImage();
if (pickedData != null) {
setState(() { _isUploadingPhoto = true; });
//final String ext = p.extension(pickedData.path).toLowerCase();
final String? cloudUrl = await NetworkApiController.uploadFileToStorage(pickedData);
setState(() { _isUploadingPhoto = false; });
if (cloudUrl != null) {
_mainPhotoCtrl.text = cloudUrl;
scaffoldMessenger.showSnackBar(SnackBar(content: Text(uploadSuccessMessage), backgroundColor: Colors.green));
} else {
scaffoldMessenger.showSnackBar(SnackBar(content: Text(uploadFailureMessage), backgroundColor: Colors.red));
}
}
},
),
),
),

const SizedBox(height: 12),
..._additionalPhotosCtrls.asMap().entries.map((entry) {
int idx = entry.key;
var ctrl = entry.value;
bool isIdxLoading = _uploadingAdditionalLoading[idx] ?? false;
return Padding(
padding: const EdgeInsets.only(bottom: 12.0),
child: TextFormField(
controller: ctrl,
decoration: InputDecoration(
labelText: '${AppLocalizations.of(context).translate('adtnl_pht_lbl2')} №${idx + 1} (URL)',
border: const OutlineInputBorder(),
prefixIcon: const Icon(Icons.add_photo_alternate_outlined),
suffixIcon: Row(
mainAxisSize: MainAxisSize.min,
children: [
isIdxLoading
? Padding(
padding: const EdgeInsets.all(12.0),
child: SizedBox(
width: 20, height: 20,
child: CircularProgressIndicator(color: colorScheme.primary, strokeWidth: 2),
),
)
: IconButton(
icon: Icon(Icons.add_a_photo, color: colorScheme.primary),
onPressed: () async {
final scaffoldMessenger = ScaffoldMessenger.of(context);
final File? pickedData = await ImagePickerService.pickAndCompressImage();
if (pickedData != null) {
setState(() => _uploadingAdditionalLoading[idx] = true);
final String? cloudUrl = await NetworkApiController.uploadFileToStorage(pickedData);
setState(() {
_uploadingAdditionalLoading[idx] = false;
if (cloudUrl != null) {
ctrl.text = cloudUrl;
scaffoldMessenger.showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).translate('pht_upld_scs_lbl')), backgroundColor: Colors.green));
} else {
scaffoldMessenger.showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).translate('pht_upld_unscs_lbl')), backgroundColor: Colors.red));
}
});
}
},
),
IconButton(
icon: const Icon(Icons.delete, color: Colors.red),
onPressed: () => setState(() => _additionalPhotosCtrls.removeAt(idx)),
),
],
),
),
),
);
}),
if (_additionalPhotosCtrls.length < 3)
TextButton.icon(
onPressed: _addAdditionalPhotoField,
icon: Icon(Icons.add_a_photo, color: colorScheme.primary),
label: Text(AppLocalizations.of(context).translate('upld_adtnl_pht_lbl2'), style: TextStyle(color: colorScheme.primary)),
),
const SizedBox(height: 12),
TextField(
controller: _stepsCtrl,
maxLines: 5,
decoration: InputDecoration(
labelText: AppLocalizations.of(context).translate('instr_lbl'),
border: const OutlineInputBorder(),
),
),
const SizedBox(height: 12),
TextField(
controller: _sourceCtrl,
decoration: InputDecoration(
labelText: AppLocalizations.of(context).translate('recipe_source_label'),
border: const OutlineInputBorder(),
),
),
const SizedBox(height: 16),
_isSaving
? Center(child: CircularProgressIndicator(color: colorScheme.primary))
: ElevatedButton(
style: ElevatedButton.styleFrom(
backgroundColor: colorScheme.primary,
foregroundColor: colorScheme.onPrimary,
padding: const EdgeInsets.symmetric(vertical: 12),
),
onPressed: () async {
if (_titleCtrl.text.trim().isEmpty || _stepsCtrl.text.trim().isEmpty) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text(AppLocalizations.of(context).translate('attn_msg_lbl5'))),
);
return;
}
setState(() { _isSaving = true; });
final NavigatorState navigator = Navigator.of(context);
final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
// 🎯 ИНЪЕКЦИЯ ISAR: Получаем доступ к бд Isar из контекста
final isar = Provider.of<Isar>(context, listen: false);
final String? authorId = widget.recipe['author_id']?.toString() ?? widget.recipe['author']?.toString();
final String serverRecipeId = (widget.recipe['\$id'] ?? widget.recipe['id'])?.toString() ?? '';
if (authorId == null || authorId.isEmpty) {
messenger.showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).translate('unscs_edit_lbl')), backgroundColor: Colors.red));
setState(() => _isSaving = false);
return;
}
List<String> dynamicPhotos = _additionalPhotosCtrls.map((c) => c.text.trim()).where((text) => text.isNotEmpty).toList();
List<String> ingredientsToList = _ingredientListCtrls.map((c) => c.text.trim()).where((text) => text.isNotEmpty).toList();
List<String> activeAllergenGroups = _allergensMap.entries.where((entry) => entry.value == true).map((entry) => entry.key).toList();
final String successMessage = AppLocalizations.of(context).translate('scs_edit_lbl');
final String errorMessage = AppLocalizations.of(context).translate('unscs_edit_lbl');
// 1. Отправляем изменения в Appwrite Cloud
final bool success = await NetworkApiController.updateRecipeInCloud(
serverRecipeId: serverRecipeId,
userAuthId: authorId,
title: _titleCtrl.text.trim(),
cuisine: _cuisineCtrl.text.trim(),
authorname: _authorCtrl.text.trim(),
imageUrl: _mainPhotoCtrl.text.trim(),
categories: List<String>.from(_selectedCategories),
instructions: _stepsCtrl.text.trim(),
source: _sourceCtrl.text.trim(),
viewsCount: widget.recipe['views_count'] ?? 0,
ingredientList: List<String>.from( ingredientsToList),
additionalimg: dynamicPhotos,
allergenGroups: List<String>.from(activeAllergenGroups),
);
if (success) {
// 🎯 2. ЗАКРЕՊЛЕНИЕ ШԵՊՈՉԿԻ ISAR: Синхронно сохраняем изменения в локальный кэш
try {
await isar.writeTxn(() async {
// Ищем рецепт в Isar по его серверному ID
var localRecipe = await isar.recipes.filter().serverRecipeIdEqualTo(serverRecipeId).findFirst();
if (localRecipe != null) {
// Обновляем существующий локальный оффлайн-документ
localRecipe.title = _titleCtrl.text.trim();
localRecipe.description = _stepsCtrl.text.trim();
localRecipe.cuisine = _cuisineCtrl.text.trim();
localRecipe.authorName = _authorCtrl.text.trim();
localRecipe.cloudMainImageUrl = _mainPhotoCtrl.text.trim().isEmpty ? null : _mainPhotoCtrl.text.trim();
localRecipe.cloudAdditionalImageUrls = dynamicPhotos;
localRecipe.textIngredients = ingredientsToList;
localRecipe.allergenGroups = activeAllergenGroups;
localRecipe.categoryTypes = List<String>.from(_selectedCategories);
localRecipe.isSynced = true; // Ставим маркер успешной синхронизации
await isar.recipes.put(localRecipe);
}
});
stdout.writeln("✨ Изменения рецепта '$serverRecipeId' успешно закешированы в Isar!");
} catch (isarError) {
stdout.writeln("⚠️ Ошибка локального сохранения в Isar: $isarError");
}
messenger.showSnackBar(SnackBar(content: Text(successMessage), backgroundColor: Colors.green));
widget.onRecipeUpdated();
if (mounted) navigator.pop(true);
} else {
messenger.showSnackBar(SnackBar(content: Text(errorMessage), backgroundColor: Colors.red));
setState(() => _isSaving = false);
}
},
child: Text(
AppLocalizations.of(context).translate('save_edit_lbl'),
style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
),
),
],
),
),
);
}
}