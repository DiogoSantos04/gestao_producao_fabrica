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

  @override
  void initState() {
    super.initState();
    _carregarPedidosPendentes();
  }

  // Procura todos os utilizadores que contêm o estado "Pendente" na coluna de controlo de acessos
  Future<void> _carregarPedidosPendentes() async {
    try {
      setState(() => _isLoading = true);

      // ✅ CORRIGIDO: Agora seleciona a coluna 'estado_conta' e filtra onde o estado é 'Pendente' limpo (sem aspas)
      final data = await _supabase
          .from('utilizadores')
          .select('utilizador_id, nome_utilizador, email, perfil, estado_conta')
          .eq('estado_conta', 'Pendente');

      setState(() {
        _pedidosPendentes = data;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar pedidos: $e'), 
            backgroundColor: TemasCores.vermelhoErro,
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  // Aprova o utilizador mudando o seu estado_conta para 'Ativo'
  Future<void> _aprovarUtilizador(Map<String, dynamic> ut) async {
    setState(() => _isLoading = true);

    try {
      // ✅ CORRIGIDO: Atualiza apenas a coluna 'estado_conta' para 'Ativo', mantendo o perfil intacto
      await _supabase
          .from('utilizadores')
          .update({'estado_conta': 'Ativo'})
          .eq('utilizador_id', ut['utilizador_id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Conta de ${ut['nome_utilizador']} aprovada com sucesso!'),
            backgroundColor: TemasCores.verdeSucesso,
          ),
        );
      }
      _carregarPedidosPendentes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao aprovar utilizador: $e'), 
            backgroundColor: TemasCores.vermelhoErro,
          ),
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
                      Text(
                        'Não existem pedidos de adesão pendentes.', 
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _pedidosPendentes.length, // ✅ Fica apenas este
                      itemBuilder: (context, index) {
                      final ut = _pedidosPendentes[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 3,
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.shade100,
                              child: const Icon(Icons.person_add, color: Colors.orange),
                            ),
                            title: Text(
                              ut['nome_utilizador'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold, 
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text('Email: ${ut['email']}'),
                                // ✅ CORRIGIDO: Mostra o perfil registado na base de dados (Ex: Cliente ou Operador)
                                Text('Perfil a Ativar: ${ut['perfil']}'),
                              ],
                            ),
                            trailing: ElevatedButton.icon(
                              onPressed: () => _aprovarUtilizador(ut),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: TemasCores.verdeSucesso,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Aprovar'),
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