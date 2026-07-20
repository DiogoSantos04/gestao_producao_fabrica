import 'package:flutter/material.dart';
import '../core/temas_cores.dart';
import '../services/auth_service.dart';
import 'dashboard_admin/dashboard_admin_shell.dart';
import 'portal_cliente/cliente_shell_screen.dart'; // 👈 IMPORTADO: Shell centralizada do cliente
import 'portal_cliente/rastreio_cliente_screen.dart';
import 'registo_screen.dart';
import 'terminal_operador/operador_shell_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _verificarSessaoExistente();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Verifica se o utilizador já tem sessão iniciada para saltar o login
  Future<void> _verificarSessaoExistente() async {
    await Future.delayed(Duration.zero);
    
    setState(() => _isLoading = true);
    
    try {
      final utilizador = await _authService.verificarSessaoAtiva();
      if (mounted && utilizador != null) {
        final String perfilNormalizado = utilizador.perfil.trim().toLowerCase();
        _redirecionarPorPerfil(perfilNormalizado);
      }
    } catch (e) {
      debugPrint('Erro ao verificar sessão existente: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Efetua o login seguro usando o AuthService
  Future<void> _fazerLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, preencha todos os campos.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    debugPrint('--- INÍCIO DO PROCESSO DE LOGIN ---');
    debugPrint('Tentativa de login para o e-mail: $email');
    
    try {
      final utilizador = await _authService.login(
        email: email,
        password: password,
      );

      if (utilizador == null) {
        throw Exception('Não foi possível obter os dados do utilizador.');
      }

      if (!mounted) return;

      final String perfilNormalizado = utilizador.perfil.trim().toLowerCase();
      debugPrint('Utilizador autenticado. Perfil: $perfilNormalizado');

      _redirecionarPorPerfil(perfilNormalizado);

    } catch (erro) {
      debugPrint('Erro detetado no Login: $erro');
      if (mounted) {
        final mensagemLimpa = erro.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mensagemLimpa), 
            backgroundColor: TemasCores.vermelhoErro,
          ),
        );
      }
    } finally {
      debugPrint('--- FIM DO PROCESSO DE LOGIN ---');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Centraliza as rotas de navegação de acordo com o nível de acesso do utilizador
  void _redirecionarPorPerfil(String perfilNormalizado) {
    if (perfilNormalizado == 'admin' || perfilNormalizado == 'administrador') {
      debugPrint('Redirecionando para: DashboardAdminShell (Admin)');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const DashboardAdminShell()),
      );
    } else if (perfilNormalizado == 'operador' || perfilNormalizado == 'funcionario' || perfilNormalizado == 'funcionário') {
      debugPrint('Redirecionando para: OperadorShellScreen (Operador Shell)');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const OperadorShellScreen()),
      );
    } else if (perfilNormalizado == 'cliente') {
      debugPrint('Redirecionando para: ClienteShellScreen (Portal Cliente)');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const ClienteShellScreen()), // 👈 REDIRECIONA PARA A SHELL COMPLETA
      );
    } else {
      debugPrint('ERRO: Perfil normalizado "$perfilNormalizado" inválido.');
      _authService.logout();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('O seu perfil de acesso é inválido ou desconhecido.'), 
          backgroundColor: TemasCores.vermelhoErro,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.factory_outlined, size: 80, color: Colors.deepPurple),
                const SizedBox(height: 16),
                const Text(
                  'Gestão de Produção',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  enabled: !_isLoading,
                  decoration: const InputDecoration(
                    labelText: 'E-mail', 
                    border: OutlineInputBorder(), 
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  enabled: !_isLoading,
                  decoration: const InputDecoration(
                    labelText: 'Palavra-passe', 
                    border: OutlineInputBorder(), 
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _fazerLogin,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20, 
                          height: 20, 
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Entrar', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Não tem conta?'),
                    TextButton(
                      onPressed: _isLoading ? null : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => const RegistoScreen()),
                        );
                      },
                      child: const Text('Solicitar acesso', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const Divider(),
                TextButton.icon(
                  onPressed: _isLoading ? null : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const RastreioClienteScreen()),
                    );
                  },
                  icon: const Icon(Icons.search, color: Colors.deepPurple),
                  label: const Text(
                    'Consultar código de rastreio público',
                    style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold),
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