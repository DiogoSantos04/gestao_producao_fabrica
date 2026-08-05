import 'package:flutter/material.dart';
import '../core/temas_cores.dart';
import '../models/utilizador_model.dart';
import '../services/auth_service.dart';
import '../widgets/estado_erro.dart';
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
  final _passwordFocus = FocusNode();
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
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Verifica se o utilizador já tem sessão iniciada para saltar o login
  Future<void> _verificarSessaoExistente() async {
    await Future.delayed(Duration.zero);
    
    setState(() => _isLoading = true);
    
    try {
      final utilizador = await _authService.verificarSessaoAtiva();
      if (mounted && utilizador != null) {
        await _redirecionarPorPerfil(utilizador.perfil);
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

      if (!mounted) return;

      debugPrint('Utilizador autenticado. Perfil: ${utilizador.perfil.name}');

      await _redirecionarPorPerfil(utilizador.perfil);

    } catch (erro) {
      debugPrint('Erro detetado no Login: $erro');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(descreverErro(erro)),
            backgroundColor: TemasCores.vermelhoErro,
          ),
        );
      }
    } finally {
      debugPrint('--- FIM DO PROCESSO DE LOGIN ---');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Centraliza as rotas de navegação de acordo com o nível de acesso do utilizador.
  ///
  /// As variantes históricas do texto do perfil ("Admin"/"Administrador",
  /// "Operador"/"Funcionario") são normalizadas em [PerfilUtilizador], em vez de
  /// serem comparadas à mão em cada sítio.
  Future<void> _redirecionarPorPerfil(PerfilUtilizador perfil) async {
    switch (perfil) {
      case PerfilUtilizador.administrador:
        debugPrint('Redirecionando para: DashboardAdminShell (Admin)');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const DashboardAdminShell()),
        );
      case PerfilUtilizador.operador:
        debugPrint('Redirecionando para: OperadorShellScreen (Operador Shell)');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const OperadorShellScreen()),
        );
      case PerfilUtilizador.cliente:
        debugPrint('Redirecionando para: ClienteShellScreen (Portal Cliente)');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const ClienteShellScreen()),
        );
      case PerfilUtilizador.desconhecido:
        debugPrint('ERRO: Perfil de acesso inválido.');
        // A sessão do Auth já está aberta neste ponto: sem o logout, a conta
        // entrava sozinha no arranque seguinte apesar de não ter perfil válido.
        await _authService.logout();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('O seu perfil de acesso é inválido ou desconhecido.'),
            backgroundColor: TemasCores.vermelhoErro,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4527A0), Color(0xFF7E57C2), Color(0xFFEDE7F6)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEDE7F6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.factory_outlined, size: 56, color: Colors.deepPurple),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Gestão de Produção',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Inicie sessão para continuar',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _emailController,
                        enabled: !_isLoading,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _passwordFocus.requestFocus(),
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
                        focusNode: _passwordFocus,
                        enabled: !_isLoading,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!_isLoading) _fazerLogin();
                        },
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Entrar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
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
          ),
        ),
      ),
    );
  }
}