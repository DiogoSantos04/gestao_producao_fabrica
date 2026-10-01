import 'package:flutter/material.dart';

import '../../../core/breakpoints.dart';
import '../../../core/mensagens.dart';
import '../../../core/temas_cores.dart';
import '../../../models/utilizador_model.dart';
import '../../../repositories/utilizadores_repository.dart';

/// Cria a conta de um membro do pessoal interno, com o perfil que o
/// administrador escolher.
///
/// O perfil não vem preenchido: escolher o papel é a decisão central deste
/// formulário e um valor por omissão fá-la-ia passar por distração. Antes este
/// diálogo criava sempre um Operador, sem o dizer no título.
///
/// `Cliente` não está na lista. Uma conta de cliente sem ficha em `clientes` não
/// aparece na carteira e não tem com que se ligar; esse caminho é o botão "Criar
/// Conta de Cliente" no ecrã de Clientes, que cria conta e ficha juntas.
///
/// Grava aqui, ao contrário do diálogo de edição: o botão tem estado próprio de
/// gravação e o diálogo só fecha quando a conta existe mesmo. Devolve a mensagem
/// de sucesso, ou `null` se foi cancelado.
class DialogoAdicionarUtilizador extends StatefulWidget {
  const DialogoAdicionarUtilizador({super.key, required this.repositorio});

  final UtilizadoresRepository repositorio;

  /// Perfis atribuíveis aqui, na ordem em que aparecem.
  static const List<PerfilUtilizador> perfisDisponiveis = [
    PerfilUtilizador.operador,
    PerfilUtilizador.tecnico,
    PerfilUtilizador.administrador,
  ];

  static Future<String?> mostrar(
    BuildContext context, {
    required UtilizadoresRepository repositorio,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DialogoAdicionarUtilizador(repositorio: repositorio),
    );
  }

  @override
  State<DialogoAdicionarUtilizador> createState() => _DialogoAdicionarUtilizadorState();
}

class _DialogoAdicionarUtilizadorState extends State<DialogoAdicionarUtilizador> {
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// `null` até o administrador escolher — ver a nota na classe.
  PerfilUtilizador? _perfil;

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
    final perfil = _perfil;
    if (perfil == null) return;

    setState(() => _aGravar = true);

    final nome = _nomeController.text.trim();
    try {
      await widget.repositorio.criarUtilizador(
        nome: nome,
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        perfil: perfil,
      );
      if (mounted) {
        Navigator.pop(context, 'Conta criada: $nome (${perfil.etiqueta}).');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _aGravar = false);
      context.mostrarMensagem('Erro ao criar utilizador: ${mensagemDeErro(e)}', eErro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Três campos de texto, um dropdown e um parágrafo: com o teclado aberto
      // não cabem na altura útil de um telemóvel.
      scrollable: true,
      title: const Text('Adicionar Utilizador'),
      content: SizedBox(
        width: larguraDialogo(context, 400),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'A conta é criada de imediato como Ativa, com o perfil escolhido. '
                'Entregue estas credenciais ao utilizador para ele iniciar sessão.',
                style: TextStyle(fontSize: 12, color: TemasCores.textoApoio),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<PerfilUtilizador>(
                initialValue: _perfil,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Perfil de acesso',
                  prefixIcon: Icon(Icons.badge_outlined),
                  helperText: 'Clientes criam-se no ecrã de Clientes, com ficha.',
                  helperMaxLines: 2,
                ),
                hint: const Text('Escolha o perfil'),
                items: [
                  for (final p in DialogoAdicionarUtilizador.perfisDisponiveis)
                    DropdownMenuItem(value: p, child: Text(p.etiqueta)),
                ],
                validator: (v) => v == null ? 'Escolha o perfil de acesso' : null,
                onChanged: _aGravar ? null : (val) => setState(() => _perfil = val),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nomeController,
                enabled: !_aGravar,
                decoration: const InputDecoration(
                  labelText: 'Nome do Utilizador',
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
              : const Text('Criar Conta'),
        ),
      ],
    );
  }
}
