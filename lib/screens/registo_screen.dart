import 'package:flutter/material.dart';

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
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Nome Completo', prefixIcon: Icon(Icons.person)),
                    validator: (val) =>
                        (val ?? '').trim().isEmpty ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.email)),
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