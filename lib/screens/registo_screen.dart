import 'package:flutter/material.dart';

import '../core/breakpoints.dart';
import '../core/temas_cores.dart';
import '../repositories/utilizadores_repository.dart';
import '../widgets/estado_erro.dart';

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
  final _confirmarController = TextEditingController();
  final _repo = UtilizadoresRepository();
  bool _isLoading = false;
  bool _passwordVisivel = false;
  bool _confirmarVisivel = false;

  /// Validação de formato do email.
  ///
  /// Deliberadamente permissiva — o objetivo é apanhar o engano óbvio (falta do
  /// `@`, espaço no meio) antes de gastar um `signUp`, não validar o endereço.
  /// A validade real só se sabe quando a mensagem chegar.
  static final RegExp _formatoEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _solicitarRegisto() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _repo.registarPedidoDeAcesso(
        nome: _nomeController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.hourglass_top, color: Colors.orange),
              SizedBox(width: 8),
              Flexible(child: Text('Pedido Enviado', overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: const Text(
            'A sua conta foi pré-registada com sucesso! Deverá aguardar que um '
            'Administrador aprove o seu acesso e lhe atribua a função adequada '
            'antes de conseguir iniciar sessão.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Compreendido'),
            )
          ],
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Volta ao Login
    } catch (erro) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(descreverErro(erro)),
          backgroundColor: TemasCores.vermelhoErro,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Em telemóvel o cartão tem de ceder margem e escala: com o padding e as
    // fontes de desktop, o formulário completo não cabia no ecrã e a linha do
    // rodapé estourava na horizontal.
    final bool compacto = context.ehCompacto;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Solicitar Conta'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4527A0), Color(0xFF7E57C2), Color(0xFFEDE7F6)],
          ),
        ),
        child: SafeArea(
          child: Center(
          child: SingleChildScrollView(
            // O corpo passa por baixo da AppBar transparente: sem folga no topo
            // o cartão ficava tapado pelo botão de voltar em ecrãs baixos.
            padding: EdgeInsets.fromLTRB(
              compacto ? 12 : 24,
              kToolbarHeight + 16,
              compacto ? 12 : 24,
              24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compacto ? 20 : 32,
                    vertical: compacto ? 28 : 40,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  Center(
                    child: Container(
                      padding: EdgeInsets.all(compacto ? 14 : 18),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEDE7F6),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.person_add_alt_1_outlined,
                          size: compacto ? 44 : 56, color: Colors.deepPurple),
                    ),
                  ),
                  SizedBox(height: compacto ? 16 : 20),
                  Text(
                    'Criar Novo Registo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compacto ? 22 : 26,
                      fontWeight: FontWeight.bold,
                      color: TemasCores.primariaRoxa,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'O acesso fica pendente de aprovação',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  SizedBox(height: compacto ? 24 : 32),
                  TextFormField(
                    controller: _nomeController,
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nome Completo',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (val) =>
                        (val ?? '').trim().isEmpty ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (val) {
                      final email = (val ?? '').trim();
                      if (email.isEmpty) return 'Campo obrigatório';
                      if (!_formatoEmail.hasMatch(email)) {
                        return 'Introduza um e-mail válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Palavra-passe',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _passwordVisivel
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        tooltip: _passwordVisivel
                            ? 'Ocultar palavra-passe'
                            : 'Mostrar palavra-passe',
                        onPressed: _isLoading
                            ? null
                            : () => setState(
                                () => _passwordVisivel = !_passwordVisivel),
                      ),
                    ),
                    obscureText: !_passwordVisivel,
                    validator: (val) =>
                        (val ?? '').length < 6 ? 'Mínimo 6 caracteres' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmarController,
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) {
                      if (!_isLoading) _solicitarRegisto();
                    },
                    decoration: InputDecoration(
                      labelText: 'Confirmar palavra-passe',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _confirmarVisivel
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        tooltip: _confirmarVisivel
                            ? 'Ocultar palavra-passe'
                            : 'Mostrar palavra-passe',
                        onPressed: _isLoading
                            ? null
                            : () => setState(
                                () => _confirmarVisivel = !_confirmarVisivel),
                      ),
                    ),
                    obscureText: !_confirmarVisivel,
                    // Um engano a escrever a password só se descobria no primeiro
                    // login — que falha sem explicação possível, porque a conta
                    // até existe.
                    validator: (val) => val != _passwordController.text
                        ? 'As palavras-passe não coincidem'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _solicitarRegisto,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: TemasCores.primariaRoxa,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Enviar para Aprovação',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  // `Wrap` e não `Row`: em ecrãs estreitos o texto mais o botão
                  // não cabem na mesma linha e a `Row` estourava na horizontal.
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Já tem conta?'),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Iniciar sessão',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                      ],
                    ),
                  ),
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