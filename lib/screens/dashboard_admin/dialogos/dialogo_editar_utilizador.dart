import 'package:flutter/material.dart';

import '../../../models/utilizador_model.dart';

/// O que o administrador decidiu no diálogo de edição.
///
/// O email não vem aqui: é a credencial gerida pelo Supabase Auth e o campo é
/// apenas de leitura.
class EdicaoUtilizador {
  const EdicaoUtilizador({
    required this.nome,
    required this.perfil,
    required this.estadoConta,
  });

  final String nome;

  /// Valor tal como vai para a coluna — 'Admin', 'Operador' ou 'Cliente'.
  final String perfil;

  /// 'Ativo', 'Inativo' ou 'Pendente'.
  final String estadoConta;
}

/// Edita nome, cargo e estado de uma conta.
///
/// Não grava: devolve a decisão e é o ecrã que escreve, porque a gravação mexe
/// no `_isLoading` da lista.
class DialogoEditarUtilizador extends StatefulWidget {
  const DialogoEditarUtilizador({super.key, required this.utilizador});

  final UtilizadorModel utilizador;

  static Future<EdicaoUtilizador?> mostrar(
    BuildContext context, {
    required UtilizadorModel utilizador,
  }) {
    return showDialog<EdicaoUtilizador>(
      context: context,
      builder: (context) => DialogoEditarUtilizador(utilizador: utilizador),
    );
  }

  @override
  State<DialogoEditarUtilizador> createState() => _DialogoEditarUtilizadorState();
}

class _DialogoEditarUtilizadorState extends State<DialogoEditarUtilizador> {
  late final TextEditingController _nomeController;
  late final TextEditingController _emailController;

  /// Os `value` do dropdown têm de coincidir exatamente com os seus
  /// `DropdownMenuItem`, que usam 'Operador' e não a etiqueta 'Funcionário'.
  late String _perfilSelecionado;
  late String _estadoSelecionado;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.utilizador.nomeUtilizador);
    _emailController = TextEditingController(text: widget.utilizador.email);
    _perfilSelecionado = switch (widget.utilizador.perfil) {
      PerfilUtilizador.administrador => 'Administrador',
      PerfilUtilizador.cliente => 'Cliente',
      _ => 'Operador',
    };
    _estadoSelecionado = widget.utilizador.estadoConta.valorBd;
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Utilizador'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nomeController,
            decoration: const InputDecoration(labelText: 'Nome do Utilizador'),
          ),
          const SizedBox(height: 12),
          // O email de login vive no Supabase Auth e não pode ser alterado
          // a partir daqui. Editá-lo só nesta tabela dessincronizava os dois
          // e o utilizador deixava de conseguir entrar com o email que via.
          TextField(
            controller: _emailController,
            enabled: false,
            decoration: const InputDecoration(
              labelText: 'Email (credencial de acesso)',
              helperText: 'Alterável apenas pelo próprio, no seu perfil.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _perfilSelecionado,
            decoration: const InputDecoration(labelText: 'Cargo / Perfil'),
            items: const [
              DropdownMenuItem(value: 'Administrador', child: Text('Administrador')),
              DropdownMenuItem(value: 'Operador', child: Text('Funcionário (Operador)')),
              DropdownMenuItem(value: 'Cliente', child: Text('Cliente Comercial')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _perfilSelecionado = val);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _estadoSelecionado,
            decoration: const InputDecoration(labelText: 'Estado da Conta'),
            items: const [
              DropdownMenuItem(value: 'Ativo', child: Text('Ativo')),
              DropdownMenuItem(value: 'Inativo', child: Text('Inativo')),
              DropdownMenuItem(value: 'Pendente', child: Text('Pendente de Aprovação')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _estadoSelecionado = val);
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () => Navigator.pop(
            context,
            EdicaoUtilizador(
              nome: _nomeController.text.trim(),
              // 'Administrador' é a etiqueta; a coluna guarda 'Admin'.
              perfil: _perfilSelecionado == 'Administrador' ? 'Admin' : _perfilSelecionado,
              estadoConta: _estadoSelecionado,
            ),
          ),
          child: const Text('Gravar'),
        ),
      ],
    );
  }
}
