import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/temas_cores.dart';
import '../../../models/cliente_model.dart';

/// Formata o número à medida que é escrito, usando a mesma regra que o
/// `ClienteModel` aplica ao apresentá-lo. Antes existiam duas implementações
/// independentes da mesma formatação.
class TelefoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final limpo = newValue.text.replaceAll(RegExp(r'[^\d+]'), '');
    final resultado = ClienteModel.formatarTelefone(limpo);
    return TextEditingValue(
      text: resultado,
      selection: TextSelection.collapsed(offset: resultado.length),
    );
  }
}

/// Os dados que o formulário recolheu, prontos para gravar.
class DadosCliente {
  const DadosCliente({
    required this.nome,
    required this.email,
    required this.contacto,
    required this.nif,
    required this.pessoaContacto,
    required this.morada,
    required this.ativo,
    this.passwordAcesso,
  });

  final String nome;
  final String email;
  final String contacto;
  final String nif;
  final String pessoaContacto;
  final String morada;
  final bool ativo;

  /// Palavra-passe inicial da conta de acesso a criar, ou `null` quando o
  /// cliente fica sem credencial (edição, ou criação com o acesso desligado).
  final String? passwordAcesso;
}

/// Formulário de criação e de edição de um cliente — é o mesmo, mudando apenas
/// o título e os valores iniciais.
///
/// Não grava: devolve os dados e é o ecrã que decide entre criar e atualizar,
/// porque é ele que tem o `_isLoading` e a lista a recarregar.
class DialogoCliente extends StatefulWidget {
  const DialogoCliente({super.key, this.clienteExistente});

  final ClienteModel? clienteExistente;

  static Future<DadosCliente?> mostrar(
    BuildContext context, {
    ClienteModel? clienteExistente,
  }) {
    return showDialog<DadosCliente>(
      context: context,
      builder: (context) => DialogoCliente(clienteExistente: clienteExistente),
    );
  }

  @override
  State<DialogoCliente> createState() => _DialogoClienteState();
}

class _DialogoClienteState extends State<DialogoCliente> {
  late final TextEditingController _nome;
  late final TextEditingController _email;
  late final TextEditingController _nif;
  late final TextEditingController _pessoaContacto;
  late final TextEditingController _morada;
  late final TextEditingController _contacto;
  final TextEditingController _password = TextEditingController();
  late bool _acessoAtivo;

  /// Só existe na criação: um cliente novo nasce, por omissão, já com conta de
  /// acesso — é isso que o faz aparecer na lista de Utilizadores.
  bool _criarAcesso = true;
  bool _ocultarPassword = true;
  String? _erro;

  bool get _eEdicao => widget.clienteExistente != null;

  /// Na edição a credencial já existe (ou não) e não se mexe aqui.
  bool get _podeCriarAcesso => !_eEdicao && _criarAcesso;

  @override
  void initState() {
    super.initState();
    final c = widget.clienteExistente;
    _nome = TextEditingController(text: c?.nomeCliente ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _nif = TextEditingController(text: c?.nif ?? '');
    _pessoaContacto = TextEditingController(text: c?.pessoaContacto ?? '');
    _morada = TextEditingController(text: c?.morada ?? '');
    _contacto = TextEditingController(
      text: c != null ? ClienteModel.formatarTelefone(c.contacto ?? '') : '',
    );
    _acessoAtivo = c?.ativo ?? true;
  }

  @override
  void dispose() {
    _nome.dispose();
    _email.dispose();
    _nif.dispose();
    _pessoaContacto.dispose();
    _morada.dispose();
    _contacto.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Devolve a primeira falha do formulário, ou `null` se estiver pronto.
  ///
  /// O email só é obrigatório quando se cria acesso, porque aí é a credencial
  /// de login; sem acesso continua a ser apenas um contacto.
  String? _validar() {
    if (_nome.text.trim().isEmpty) return 'Indique o nome do cliente.';
    if (_contacto.text.trim().isEmpty) return 'Indique o contacto telefónico.';
    if (!_podeCriarAcesso) return null;

    final email = _email.text.trim();
    if (email.isEmpty) return 'O email é obrigatório para criar a conta de acesso.';
    if (!email.contains('@') || !email.contains('.')) return 'Email inválido.';
    if (_password.text.trim().length < 6) {
      return 'A palavra-passe de acesso tem de ter pelo menos 6 caracteres.';
    }
    return null;
  }

  void _gravar() {
    // Nome e contacto são obrigatórios; sem eles o botão não faz nada, tal como
    // antes. O erro passou a ser dito em vez de o botão ficar mudo.
    final erro = _validar();
    if (erro != null) {
      setState(() => _erro = erro);
      return;
    }

    Navigator.pop(
      context,
      DadosCliente(
        passwordAcesso: _podeCriarAcesso ? _password.text.trim() : null,
        nome: _nome.text.trim(),
        email: _email.text.trim(),
        contacto: _contacto.text.trim(),
        nif: _nif.text.trim(),
        pessoaContacto: _pessoaContacto.text.trim(),
        morada: _morada.text.trim(),
        ativo: _acessoAtivo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_eEdicao ? 'Editar Dados do Cliente' : 'Criar Conta de Cliente'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nome,
                decoration: const InputDecoration(labelText: 'Nome do Cliente / Empresa *'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nif,
                      decoration:
                          const InputDecoration(labelText: 'NIF / NIPC', hintText: '9 dígitos'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(9),
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email de Contacto'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _contacto,
                      decoration: const InputDecoration(labelText: 'Contacto Telefónico *'),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(16),
                        TelefoneInputFormatter(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _pessoaContacto,
                      decoration: const InputDecoration(
                          labelText: 'Pessoa de Contacto / Cargo', hintText: 'Ex: Engª Ana Silva'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _morada,
                decoration: const InputDecoration(
                    labelText: 'Morada de Carga / Entrega', hintText: 'Rua, Código Postal, Cidade'),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Acesso ao Portal de Rastreio',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text(_acessoAtivo
                    ? 'Cliente consegue rastrear encomendas'
                    : 'Acesso temporariamente bloqueado'),
                value: _acessoAtivo,
                activeThumbColor: TemasCores.textoPrimario,
                onChanged: (val) => setState(() => _acessoAtivo = val),
              ),
              if (!_eEdicao) ...[
                const Divider(height: 24),
                SwitchListTile(
                  title: const Text('Criar conta de acesso ao portal',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: Text(_criarAcesso
                      ? 'O cliente passa a constar em Utilizadores, com perfil Cliente'
                      : 'Fica só como ficha de cliente, sem login'),
                  value: _criarAcesso,
                  activeThumbColor: TemasCores.textoPrimario,
                  onChanged: (val) => setState(() => _criarAcesso = val),
                ),
                if (_criarAcesso)
                  TextField(
                    controller: _password,
                    obscureText: _ocultarPassword,
                    decoration: InputDecoration(
                      labelText: 'Palavra-passe inicial *',
                      helperText: 'Entregue-a ao cliente; ele pode alterá-la no perfil.',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_ocultarPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _ocultarPassword = !_ocultarPassword),
                      ),
                    ),
                  ),
              ],
              if (_erro != null) ...[
                const SizedBox(height: 12),
                Text(_erro!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _gravar, child: const Text('Gravar')),
      ],
    );
  }
}
