import 'package:app_upload/home_admin_page.dart';
import 'package:app_upload/home_user_page.dart';
import 'package:app_upload/register_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _login() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Preencha todos os campos!');
      return;
    }

    setState(() => isLoading = true);
    try {
      final response = await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);

      if (response.user == null) {
        _showMessage('Erro ao fazer login', isError: true);
        return;
      }

      // Acesse o ID do usuário logado
      final userId = Supabase.instance.client.auth.currentUser?.id;

      // Verifique se o userId existe
      if (userId != null) {
        // Busque o perfil do usuário na tabela 'profiles'
        final profileResponse = await Supabase.instance.client
            .from('profiles')
            .select('role')
            .eq('id', userId)
            .single(); // Espera apenas uma linha como resultado

        if (profileResponse['role'] == null) {
          _showMessage('Erro ao buscar o tipo de perfil', isError: true);
          return;
        }

        final role = profileResponse['role'];

        // Verifique o valor do campo role
        if (role == 'admin') {
          // Se for admin, redireciona para a página de admin
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const HomeAdminPage(),
            ),
          );
        } else {
          // Se não for admin, redireciona para a página normal
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const HomeUserPage(),
            ),
          );
        }

        _showMessage('Login realizado com sucesso!', isError: false);
      } else {
        _showMessage('Usuário não encontrado!', isError: true);
      }
    } on AuthException catch (e) {
      if (e.message.contains('Invalid login credentials')) {
        _showMessage('E-mail ou senha incorretos.');
      } else if (e.message.contains('Email not confirmed')) {
        _showMessage('Confirme seu e-mail antes de fazer login.');
      } else {
        _showMessage(e.message);
      }
    } catch (e) {
      _showMessage('Erro inesperado ao fazer login. Tente novamente.');
    }
    setState(() => isLoading = false);
  }

  Future<void> _forgotPassword() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      _showMessage('Digite seu e-mail para redefinir a senha!');
      return;
    }

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      _showMessage('Verifique seu e-mail para redefinir a senha.',
          isError: false);
    } on AuthException catch (e) {
      if (e.message.contains('User not found')) {
        _showMessage('Nenhuma conta encontrada com este e-mail.');
      } else {
        _showMessage(e.message);
      }
    } catch (e) {
      _showMessage('Erro ao solicitar redefinição de senha. Tente novamente.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'E-mail'),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: 'Senha'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : _login,
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Login'),
            ),
            TextButton(
              onPressed: _forgotPassword,
              child: const Text('Esqueci minha senha'),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RegisterPage()),
                );
              },
              child: const Text('Criar conta'),
            ),
          ],
        ),
      ),
    );
  }
}
