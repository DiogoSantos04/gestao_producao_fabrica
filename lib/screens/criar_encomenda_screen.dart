import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CriarEncomendaScreen extends StatefulWidget {
  const CriarEncomendaScreen({super.key});

  @override
  State<CriarEncomendaScreen> createState() => _CriarEncomendaScreenState();
}

class _CriarEncomendaScreenState extends State<CriarEncomendaScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  List<dynamic> _clientes = [];
  List<dynamic> _tiposProduto = [];
  
  String? _clienteSelecionado;
  String? _tipoProdutoSelecionado;
  final _dataEntregaController = TextEditingController();
  
  bool _isLoadingData = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _dataEntregaController.dispose();
    super.dispose();
  }

  // Carrega Clientes e Tipos de Produto do Supabase para os Dropdowns
  Future<void> _carregarDados() async {
    try {
      final clientesData = await _supabase.from('clientes').select('id, nome_cliente');
      final produtosData = await _supabase.from('tipos_produto').select('id, nome_tipo_produto');

      setState(() {
        _clientes = clientesData;
        _tiposProduto = produtosData;
        _isLoadingData = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar dados: $e'), backgroundColor: Colors.red),
      );
      setState(() => _isLoadingData = false);
    }
  }

  // Gera um Código de Rastreio Aleatório (TRC-XXXXXX)
  String _gerarCodigoRastreio() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    final sufixo = List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();
    return 'TRC-$sufixo';
  }

  // Submete a encomenda seguindo as regras de negócio
  Future<void> _lancarEncomenda() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // 1. Procurar a primeira fase padrão (ordem = 1) para o tipo de produto selecionado
      final faseInicialData = await _supabase
          .from('fases_padrao')
          .select('id')
          .eq('tipos_produto_id', int.parse(_tipoProdutoSelecionado!))
          .eq('ordem', 1)
          .maybeSingle();

      if (faseInicialData == null) {
        throw Exception('Não foi encontrada nenhuma fase inicial (Ordem 1) para este tipo de produto.');
      }

      final faseInicialId = faseInicialData['id'];
      final codigoRastreio = _gerarCodigoRastreio();

      // 2. Inserir a encomenda na tabela 'encomendas'
      await _supabase.from('encomendas').insert({
        'codigo_rastreio': codigoRastreio,
        'data_entrega': _dataEntregaController.text,
        'cliente_id': int.parse(_clienteSelecionado!),
        'tipos_produtos_id': int.parse(_tipoProdutoSelecionado!),
        'fase_atual_id': faseInicialId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Encomenda $codigoRastreio lançada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // Fecha o ecrã e avisa que houve mudanças
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao lançar encomenda: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lançar Ordem de Produção'),
        backgroundColor: Colors.deepPurple.shade50,
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Nova Ordem',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            
                            // Dropdown Clientes
                            DropdownButtonFormField<String>(
                              value: _clienteSelecionado,
                              decoration: const InputDecoration(
                                labelText: 'Selecione o Cliente',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person),
                              ),
                              items: _clientes.map((c) {
                                return DropdownMenuItem<String>(
                                  value: c['id'].toString(),
                                  child: Text(c['nome_cliente']),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _clienteSelecionado = val),
                              validator: (val) => val == null ? 'Campo obrigatório' : null,
                            ),
                            const SizedBox(height: 16),

                            // Dropdown Tipos de Produto
                            DropdownButtonFormField<String>(
                              value: _tipoProdutoSelecionado,
                              decoration: const InputDecoration(
                                labelText: 'Tipo de Produto',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.category),
                              ),
                              items: _tiposProduto.map((p) {
                                return DropdownMenuItem<String>(
                                  value: p['id'].toString(),
                                  child: Text(p['nome_tipo_produto']),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _tipoProdutoSelecionado = val),
                              validator: (val) => val == null ? 'Campo obrigatório' : null,
                            ),
                            const SizedBox(height: 16),

                            // Campo Data de Entrega (Texto simples formatado como YYYY-MM-DD para testes simples)
                            TextFormField(
                              controller: _dataEntregaController,
                              decoration: const InputDecoration(
                                labelText: 'Data Prevista de Entrega (AAAA-MM-DD)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.calendar_today),
                                hintText: 'Ex: 2026-08-30',
                              ),
                              keyboardType: TextInputType.datetime,
                              validator: (val) {
                                if (val == null || val.isEmpty) return 'Campo obrigatório';
                                if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(val)) {
                                  return 'Formato inválido. Use AAAA-MM-DD';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),

                            ElevatedButton(
                              onPressed: _isSaving ? null : _lancarEncomenda,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Text('Lançar Encomenda', style: TextStyle(fontSize: 16)),
                            ),
                          ],
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