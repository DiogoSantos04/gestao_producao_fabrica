import 'package:flutter/material.dart';

import '../../../core/breakpoints.dart';
import '../../../core/mensagens.dart';
import '../../../core/temas_cores.dart';
import '../../../repositories/utilizadores_repository.dart';

/// Cria a conta de um novo funcionário.
///
/// Grava aqui, ao contrário do diálogo de edição: o botão tem estado próprio de
/// gravação e o diálogo só fecha quando a conta existe mesmo. Devolve a mensagem
/// de sucesso, ou `null` se foi cancelado.
///
/// O isolamento do cliente Supabase — criar a conta sem derrubar a sessão do
/// administrador — é responsabilidade do repositório.
class DialogoAdicionarFuncionario extends StatefulWidget {
  const DialogoAdicionarFuncionario({super.key, required this.repositorio});

  final UtilizadoresRepository repositorio;

  static Future<String?> mostrar(
    BuildContext context, {
    required UtilizadoresRepository repositorio,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DialogoAdicionarFuncionario(repositorio: repositorio),
    );
  }

  @override
  State<DialogoAdicionarFuncionario> createState() => _DialogoAdicionarFuncionarioState();
}

class _DialogoAdicionarFuncionarioState extends State<DialogoAdicionarFuncionario> {
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _aGravar = false;
  bool _ocultarPassword = true;

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _criar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _aGravar = true);

    final nome = _nomeController.text.trim();
    try {
      await widget.repositorio.criarFuncionario(
        nome: nome,
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (mounted) Navigator.pop(context, 'Funcionário "$nome" criado com sucesso!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _aGravar = false);
      context.mostrarMensagem('Erro ao criar funcionário: ${mensagemDeErro(e)}', eErro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Três campos de texto e um parágrafo: com o teclado aberto não cabem na
      // altura útil de um telemóvel.
      scrollable: true,
      title: const Text('Adicionar Novo Funcionário'),
      content: SizedBox(
        width: larguraDialogo(context, 400),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'A conta é criada de imediato como Operador (Ativo). '
                'Entregue estas credenciais ao funcionário para ele iniciar sessão.',
                style: TextStyle(fontSize: 12, color: TemasCores.textoApoio),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nomeController,
                enabled: !_aGravar,
                decoration: const InputDecoration(
                  labelText: 'Nome do Funcionário',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Indique o nome' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                enabled: !_aGravar,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Indique o email';
                  if (!v.contains('@') || !v.contains('.')) return 'Email inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                enabled: !_aGravar,
                obscureText: _ocultarPassword,
                decoration: InputDecoration(
                  labelText: 'Palavra-passe inicial',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_ocultarPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _ocultarPassword = !_ocultarPassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 6) return 'Mínimo 6 caracteres';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _aGravar ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _aGravar ? null : _criar,
          child: _aGravar
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: TemasCores.textoInverso),
                )
              : const Text('Criar Funcionário'),
        ),
      ],
    );
  }
}
