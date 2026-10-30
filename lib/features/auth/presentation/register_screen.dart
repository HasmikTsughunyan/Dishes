import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/network_service/network_api_conroller.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _loginCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _isHidden = true;

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passwordCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Регистрация шеф-повара'),
        backgroundColor: Colors.teal.shade700,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _loginCtrl,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Придумайте Логин (только английский)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: _isHidden,
              decoration: InputDecoration(
                labelText: 'Придумайте Пароль (мин. 8 символов)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isHidden ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _isHidden = !_isHidden),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              obscureText: _isHidden,
              decoration: InputDecoration(
                labelText: 'e-mail',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isHidden ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _isHidden = !_isHidden),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              obscureText: _isHidden,
              decoration: InputDecoration(
                labelText: 'Your phone number: +',
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
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              onPressed: () async {
                final String login = _loginCtrl.text.trim();
                final String password = _passwordCtrl.text.trim();
                final String email = _emailCtrl.text.trim();
                final String phone = _phoneCtrl.text.trim();

                if (login.isEmpty ||
                    password.length < 8 ||
                    email.isEmpty ||
                    phone.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('❌ Заполните все поля для регистрации.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Ցուցադրում ենք լոադերը
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => Center(
                    child: CircularProgressIndicator(
                      color: colorScheme.primary,
                    ),
                  ),
                );

                // 🎯 ԿԱՆՉՈՒՄ ԵՆՔ ԻՐԱԿԱՆ ԳՐԱՆՑՈՒՄԸ ԱՄՊ
                final bool success = await NetworkApiController.registerUser(
                  email: _emailCtrl.text.trim(),
                  password: _passwordCtrl.text.trim(),
                  name: _loginCtrl.text.trim(),
                  phoneNumber: _phoneCtrl.text.trim(),
                );

                if (context.mounted) {
                  Navigator.pop(context); // Փակում ենք լոադերը
                }

                if (success) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '🎉 Вы успешно зарегистрированы! Войдите в систему.',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                    Navigator.pop(
                      context,
                    ); // Վերադառնում ենք Մուտքի էջ (AuthScreen)
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '❌ Ошибка регистрации! Логин может быть занят.',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: Text(
                'Зарегистрироваться',
                style: TextStyle(color: colorScheme.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
