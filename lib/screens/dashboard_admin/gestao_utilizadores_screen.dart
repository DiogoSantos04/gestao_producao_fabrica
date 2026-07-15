import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/temas_cores.dart';

class GestaoUtilizadoresScreen extends StatefulWidget {
  const GestaoUtilizadoresScreen({super.key});

  @override
  State<GestaoUtilizadoresScreen> createState() => _GestaoUtilizadoresScreenState();
}

class _GestaoUtilizadoresScreenState extends State<GestaoUtilizadoresScreen> {
  final _supabase = Supabase.instance.client;
  List<dynamic> _pedidosPendentes = [];
  bool _isLoading = true;

  // Guarda localmente o papel selecionado pelo Admin para cada utilizador ID antes de clicar em aprovar
  final Map<String, String> _papeisSelecionados = {};

  @override
  void initState() {
    super.initState();
    _carregarPedidosPendentes();
  }

  Future<void> _carregarPedidosPendentes() async {
    try {
      // Procura especificamente todas as contas cujo perfil seja exatamente 'Pendente'
      final data = await _supabase
          .from('utilizadores')
          .select('utilizador_id, nome_utilizador, email, perfil')
          .eq('estado_conta', 'Pendente');

      setState(() {
        _pedidosPendentes = data;
        
        // Inicializa o mapa com o papel predefinido 'Operador' para cada nova conta encontrada
        for (var ut in data) {
          final uid = ut['utilizador_id'] as String;
          _papeisSelecionados[uid] = 'Operador';
        }
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar pedidos: $e'), backgroundColor: TemasCores.vermelhoErro),
      );
      setState(() => _isLoading = false);
    }
  }

  // Grava o perfil oficial escolhido e remove o estado pendente
  Future<void> _aprovarUtilizador(Map<String, dynamic> ut) async {
    final uid = ut['utilizador_id'] as String;
    final papelEscolhido = _papeisSelecionados[uid] ?? 'Operador';

    setState(() => _isLoading = true);

    try {
      await _supabase
          .from('utilizadores')
          .update({
            'perfil': papelEscolhido,
            'estado_conta': 'Ativo', // Atualiza a coluna certa para 'Ativo'
          })
          .eq('utilizador_id', uid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Conta de ${ut['nome_utilizador']} ativada com sucesso como $papelEscolhido!'),
            backgroundColor: TemasCores.verdeSucesso,
          ),
        );
      }
      _carregarPedidosPendentes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao aprovar utilizador: $e'), backgroundColor: TemasCores.vermelhoErro),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestão de Utilizadores'),
        backgroundColor: Colors.deepPurple.shade50,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pedidosPendentes.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_user_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Não existem pedidos de adesão pendentes.', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 650),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _pedidosPendentes.length,
                      itemBuilder: (context, index) {
                        final ut = _pedidosPendentes[index];
                        final uid = ut['utilizador_id'] as String;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.orange.shade100,
                                    child: const Icon(Icons.person_add, color: Colors.orange),
                                  ),
                                  title: Text(
                                    ut['nome_utilizador'],
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  subtitle: Text('Email: ${ut['email']}'),
                                ),
                                const Divider(),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Seletor dinâmico do papel a atribuir
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: _papeisSelecionados[uid],
                                        decoration: const InputDecoration(
                                          labelText: 'Atribuir Função',
                                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                        items: const [
                                          DropdownMenuItem(value: 'Admin', child: Text('Administrador')),
                                          DropdownMenuItem(value: 'Operador', child: Text('Operador (Fábrica)')),
                                          DropdownMenuItem(value: 'Cliente', child: Text('Cliente Comercial')),
                                        ],
                                        onChanged: (novoPapel) {
                                          if (novoPapel != null) {
                                            setState(() {
                                              _papeisSelecionados[uid] = novoPapel;
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Botão de submissão
                                    ElevatedButton.icon(
                                      onPressed: () => _aprovarUtilizador(ut),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: TemasCores.verdeSucesso,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                      ),
                                      icon: const Icon(Icons.check, size: 18),
                                      label: const Text('Confirmar'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
    );
  }
}