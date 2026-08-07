import 'package:flutter/material.dart';

import '../../core/ecra_recarregavel.dart';
import '../../core/temas_cores.dart';
import '../../models/incidencia_model.dart';
import '../../repositories/base_repository.dart';
import '../../repositories/tecnico_repository.dart';
import '../../widgets/estado_erro.dart';
import 'fila_manutencao_screen.dart' show formatarDuracao;

/// Intervenções já fechadas por este técnico.
///
/// Serve de prova do trabalho feito e é onde o tempo de reparação fica visível
/// para quem o executou — não só para quem lê relatórios.
class HistoricoTecnicoScreen extends StatefulWidget {
  const HistoricoTecnicoScreen({super.key});

  @override
  State<HistoricoTecnicoScreen> createState() => _HistoricoTecnicoScreenState();
}

class _HistoricoTecnicoScreenState extends State<HistoricoTecnicoScreen>
    implements EcraRecarregavel {
  final TecnicoRepository _repo = TecnicoRepository();

  List<IncidenciaModel> _registos = const [];
  bool _aCarregar = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    recarregar();
  }

  @override
  Future<void> recarregar() async {
    if (mounted) setState(() => _aCarregar = true);
    try {
      final registos = await _repo.obterHistorico();
      if (!mounted) return;
      setState(() {
        _registos = registos;
        _erro = null;
        _aCarregar = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e is RepositoryException ? e.mensagem : '$e';
        _aCarregar = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_aCarregar && _registos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erro != null) {
      return EstadoErro(
        titulo: 'Não foi possível carregar o histórico',
        detalhe: _erro,
        aoRepetir: recarregar,
      );
    }

    if (_registos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text(
            'Ainda não fechou nenhuma intervenção.',
            textAlign: TextAlign.center,
            style: TextStyle(color: TemasCores.textoTerciario),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: recarregar,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _registos.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _cartao(_registos[i]),
      ),
    );
  }

  Widget _cartao(IncidenciaModel inc) {
    final duracao = inc.duracaoIntervencao;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: TemasCores.borda),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    inc.rotulo ?? 'Manutenção',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: TemasCores.textoPrimario,
                    ),
                  ),
                ),
                if (duracao != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: TemasCores.sucessoFundo,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      formatarDuracao(duracao),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: TemasCores.sucessoTextoForte,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                inc.nomePosto,
                inc.codigoRastreio,
              ].where((v) => v != null && v.trim().isNotEmpty).join(' · '),
              style: const TextStyle(
                fontSize: 12,
                color: TemasCores.textoTerciario,
              ),
            ),
            if ((inc.diagnostico ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Diagnóstico: ${inc.diagnostico!.trim()}',
                style: const TextStyle(
                  fontSize: 12,
                  color: TemasCores.textoSecundario,
                ),
              ),
            ],
            if (!inc.lineClearanceValidado) ...[
              const SizedBox(height: 8),
              const Text(
                'A aguardar Line Clearance da qualidade.',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: TemasCores.avisoTexto,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
