import 'package:isar_community/isar.dart';
import '../../allergens/data/models/schemas.dart'; // Импорт ваших схем

class AuthRepository {
  final Isar _isar;

  AuthRepository(this._isar);

  /// Сохранить сессию пользователя в локальную БД после успешного входа
  Future<void> saveSession(
    String authId,
    String login, {
    String? email,
  }) async {
    final profile = await _isar.userProfiles
        .filter()
        .authIdEqualTo(authId)
        .findFirst() ??
        (UserProfile()..authId = authId);
    profile
      ..authId = authId
      ..login = login
      ..email = email;

    // Isar требует выполнять запись внутри транзакции
    await _isar.writeTxn(() async {
      await _isar.userProfiles.put(profile);
    });
  }

  /// Получить текущего сохраненного пользователя (для работы без сети)
  Future<UserProfile?> getCurrentUser() async {
    // Берем первую попавшуюся запись профиля (обычно она одна на устройстве)
    return await _isar.userProfiles.where().findFirst();
  }

  /// Выйти из аккаунта (очистить локальную сессию)
  Future<void> logout() async {
    await _isar.writeTxn(() async {
      await _isar.userProfiles.clear();
    });
  }
}
