import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/temas_cores.dart';

class RegistoScreen extends StatefulWidget {
  const RegistoScreen({super.key});

  @override
  State<RegistoScreen> createState() => _RegistoScreenState();
}

class _RegistoScreenState extends State<RegistoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  String _perfilDesejado = 'Operador';
  bool _isLoading = false;

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _solicitarRegisto() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 1. Criar o utilizador no sistema de Autenticação nativo do Supabase
      final AuthResponse res = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = res.user;

      if (user != null) {
        // 2. Inserir na vossa tabela 'utilizadores' com o estado de aprovação pendente
        // NOTA: Ajustem os nomes das colunas de acordo com a vossa tabela real se necessário
        await Supabase.instance.client.from('utilizadores').insert({
          'utilizador_id': user.id,
          'nome_utilizador': _nomeController.text.trim(),
          'email': _emailController.text.trim(),
          'perfil': _perfilDesejado,
          // Se tiverem adicionado a coluna 'aprovado' (boolean) na tabela, enviamos false. 
          // Se usarem o próprio texto do perfil, podem enviar ex: 'Pendente_Operador'
          'password': _passwordController.text.trim(), 
        });

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.hourglass_top, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Pedido Enviado'),
                ],
              ),
              content: const Text(
                'A sua conta foi pré-registada com sucesso! Por motivos de segurança, deverá aguardar que um Administrador aprove o seu acesso antes de conseguir iniciar sessão.',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Fecha o diálogo
                    Navigator.of(context).pop(); // Volta ao Login
                  },
                  child: const Text('Compreendido'),
                )
              ],
            ),
          );
        }
      }
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: TemasCores.vermelhoErro),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao solicitar registo: $e'), backgroundColor: TemasCores.vermelhoErro),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Solicitar Conta')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Criar Novo Registo',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: TemasCores.primariaRoxa),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nomeController,
                    decoration: const InputDecoration(labelText: 'Nome Completo', prefixIcon: Icon(Icons.person)),
                    validator: (val) => val!.isEmpty ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.email)),
                    keyboardType: TextInputType.emailAddress,
                    validator: (val) => val!.isEmpty ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'Palavra-passe', prefixIcon: Icon(Icons.lock)),
                    obscureText: true,
                    validator: (val) => val!.length < 6 ? 'Mínimo 6 caracteres' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _perfilDesejado,
                    decoration: const InputDecoration(labelText: 'Função no Sistema', prefixIcon: Icon(Icons.badge)),
                    items: const [
                      DropdownMenuItem(value: 'Operador', child: Text('Operador / Chão de Fábrica')),
                      DropdownMenuItem(value: 'Cliente', child: Text('Cliente Comercial')),
                    ],
                    onChanged: (val) => setState(() => _perfilDesejado = val!),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _solicitarRegisto,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: TemasCores.primariaRoxa,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Enviar para Aprovação'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}