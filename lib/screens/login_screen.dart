import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/temas_cores.dart';
import 'dashboard_admin/painel_controlo_screen.dart';
import 'terminal_operador/fila_trabalho_screen.dart';
import 'portal_cliente/historico_cliente_screen.dart';
import 'portal_cliente/rastreio_cliente_screen.dart';
import 'registo_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

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
      // 1. Autenticação no Supabase Auth nativo
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = res.user;
      if (user == null) {
        throw const AuthException('Não foi possível obter os dados da sessão do utilizador.');
      }

      debugPrint('Autenticação Supabase Auth realizada com sucesso. UID: ${user.id}');

      // 2. Consulta a tabela pública 'utilizadores'
      final perfilData = await Supabase.instance.client
          .from('utilizadores')
          .select('perfil')
          .eq('utilizador_id', user.id)
          .maybeSingle();

      if (perfilData == null) {
        debugPrint('ERRO: UID ${user.id} existe no Auth mas não tem correspondência na tabela pública "utilizadores".');
        await Supabase.instance.client.auth.signOut();
        throw const AuthException('Registo de perfil do utilizador não encontrado no sistema.');
      }

      final String perfilOriginal = perfilData['perfil'].toString();
      // Normalização da string para evitar falhas de grafia ou maiúsculas/minúsculas
      final String perfilNormalizado = perfilOriginal.trim().toLowerCase();

      debugPrint('Perfil encontrado na base de dados: "$perfilOriginal" (Normalizado: "$perfilNormalizado")');

      // 3. Validação de Contas Pendentes de Aprovação
      if (perfilNormalizado.startsWith('pendente')) {
        debugPrint('LOGIN RECUSADO: Conta com perfil pendente de aprovação.');
        await Supabase.instance.client.auth.signOut();
        throw const AuthException('A sua conta ainda não foi aprovada por um administrador.');
      }

      if (!mounted) return;

      // 4. Redirecionamento Dinâmico Inteligente
      if (perfilNormalizado == 'admin' || perfilNormalizado == 'administrador') {
        debugPrint('Redirecionando para: PainelControloScreen (Admin)');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const PainelControloScreen()),
        );
      } else if (perfilNormalizado == 'operador' || perfilNormalizado == 'funcionario' || perfilNormalizado == 'funcionário') {
        debugPrint('Redirecionando para: TerminalOperadorScreen (Operador)');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const TerminalOperadorScreen()),
        );
      } else if (perfilNormalizado == 'cliente') {
        debugPrint('Redirecionando para: HistoricoClienteScreen (Cliente)');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HistoricoClienteScreen()),
        );
      } else {
        debugPrint('ERRO: Perfil normalizado "$perfilNormalizado" não foi mapeado no Router.');
        await Supabase.instance.client.auth.signOut();
        throw const AuthException('O seu perfil de acesso é inválido ou desconhecido.');
      }

    } on AuthException catch (erro) {
      debugPrint('Erro detetado (AuthException): ${erro.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(erro.message), backgroundColor: TemasCores.vermelhoErro),
        );
      }
    } catch (erro) {
      debugPrint('Erro sistémico inesperado: $erro');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro inesperado: $erro'), backgroundColor: TemasCores.vermelhoErro),
        );
      }
    } finally {
      debugPrint('--- FIM DO PROCESSO DE LOGIN ---');
      if (mounted) setState(() => _isLoading = false);
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
                  decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Palavra-passe', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)),
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
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Entrar', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Não tem conta?'),
                    TextButton(
                      onPressed: () {
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
                  onPressed: () {
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