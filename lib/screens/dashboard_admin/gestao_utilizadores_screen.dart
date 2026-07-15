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

  // Procura todos os utilizadores que contêm "Pendente" no perfil
  Future<void> _carregarPedidosPendentes() async {
    try {
      // Corrigido: Removida a coluna 'id' e selecionada apenas a chave primária real 'utilizador_id'
      final data = await _supabase
          .from('utilizadores')
          .select('utilizador_id, nome_utilizador, email, perfil')
          .ilike('perfil', 'Pendente%'); // Procura por 'Pendente', 'Pendente_Operador', etc.

      setState(() {
        _pedidosPendentes = data;
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar pedidos: $e'), backgroundColor: TemasCores.vermelhoErro),
      );
      setState(() => _isLoading = false);
    }
  }

  // Aprova o utilizador mudando o perfil para o estado definitivo
  Future<void> _aprovarUtilizador(Map<String, dynamic> ut) async {
    setState(() => _isLoading = true);

    try {
      String perfilDefinitivo = 'Operador';
      if (ut['perfil'].toString().contains('Cliente')) {
        perfilDefinitivo = 'Cliente';
      }

      // Corrigido: Atualização filtrada usando 'utilizador_id'
      await _supabase
          .from('utilizadores')
          .update({'perfil': perfilDefinitivo})
          .eq('utilizador_id', ut['utilizador_id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Conta de ${ut['nome_utilizador']} aprovada como $perfilDefinitivo!'),
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
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _pedidosPendentes.length,
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
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text('Email: ${ut['email']}'),
                                Text('Perfil Solicitado: ${ut['perfil']}'),
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