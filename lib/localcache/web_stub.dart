

// Этот класс имитирует window.localStorage для мобильных платформ во время компиляции
class WebWindow {
  Map<String, String> get localStorage => throw UnsupportedError('localStorage доступен только в Web');
}

final window = WebWindow();
