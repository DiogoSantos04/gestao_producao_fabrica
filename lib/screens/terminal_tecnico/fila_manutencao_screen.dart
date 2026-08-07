import 'package:flutter/material.dart';

import '../../core/ecra_recarregavel.dart';
import '../../core/mensagens.dart';
import '../../core/temas_cores.dart';
import '../../models/incidencia_model.dart';
import '../../repositories/base_repository.dart';
import '../../repositories/tecnico_repository.dart';
import '../../widgets/estado_erro.dart';
import 'dialogo_concluir_intervencao.dart';

/// Duração em texto curto ("2h 15m", "8m").
String formatarDuracao(Duration d) {
  final horas = d.inHours;
  final minutos = d.inMinutes.remainder(60);
  if (horas > 0) return '${horas}h ${minutos}m';
  return '${d.inMinutes}m';
}

/// Fila de avarias por resolver.
///
/// Mostra tanto as pendentes como as já aceites por outro técnico: saber quem
/// está a tratar do quê evita dois técnicos no mesmo posto. Quem não pode agir é
/// travado no botão, não escondendo-lhe a linha.
class FilaManutencaoScreen extends StatefulWidget {
  const FilaManutencaoScreen({super.key});

  @override
  State<FilaManutencaoScreen> createState() => _FilaManutencaoScreenState();
}

class _FilaManutencaoScreenState extends State<FilaManutencaoScreen>
    implements EcraRecarregavel {
  final TecnicoRepository _repo = TecnicoRepository();

  List<IncidenciaModel> _fila = const [];
  bool _aCarregar = true;
  String? _erro;

  /// Incidência com uma ação em curso — trava só esse cartão, não a lista toda.
  int? _idEmProcessamento;

  @override
  void initState() {
    super.initState();
    recarregar();
  }

  @override
  Future<void> recarregar() async {
    if (mounted) setState(() => _aCarregar = true);
    try {
      final fila = await _repo.obterFila();
      if (!mounted) return;
      setState(() {
        _fila = fila;
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

  Future<void> _aceitar(IncidenciaModel incidencia) async {
    setState(() => _idEmProcessamento = incidencia.id);
    try {
      await _repo.aceitar(incidencia.id);
      if (!mounted) return;
      context.mostrarMensagem('Intervenção iniciada. O tempo começa a contar.');
    } catch (e) {
      if (!mounted) return;
      context.mostrarMensagem('$e', eErro: true);
    } finally {
      if (mounted) setState(() => _idEmProcessamento = null);
      // Recarrega em qualquer dos casos: se a incidência foi entretanto aceite
      // por outro técnico, a lista tem de mostrar isso em vez de manter o botão.
      await recarregar();
    }
  }

  Future<void> _concluir(IncidenciaModel incidencia) async {
    final fechou = await DialogoConcluirIntervencao.mostrar(
      context,
      incidencia: incidencia,
      repositorio: _repo,
    );
    if (fechou != true || !mounted) return;
    context.mostrarMensagem(
      'Intervenção fechada. A ordem aguarda Line Clearance.',
    );
    await recarregar();
  }

  @override
  Widget build(BuildContext context) {
    if (_aCarregar && _fila.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erro != null) {
      return EstadoErro(
        titulo: 'Não foi possível carregar a fila de manutenção',
        detalhe: _erro,
        aoRepetir: recarregar,
      );
    }

    if (_fila.isEmpty) {
      return _semTrabalho();
    }

    return RefreshIndicator(
      onRefresh: recarregar,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _fila.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _cartao(_fila[i]),
      ),
    );
  }

  Widget _semTrabalho() {
    return ListView(
      padding: const EdgeInsets.all(48),
      children: [
        const Icon(
          Icons.check_circle_outline,
          size: 56,
          color: TemasCores.sucessoClaro,
        ),
        const SizedBox(height: 16),
        const Text(
          'Nenhuma avaria em aberto.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: TemasCores.textoPrimario,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'As paragens registadas pelos operadores aparecem aqui.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: TemasCores.textoTerciario),
        ),
        const SizedBox(height: 20),
        Center(
          child: OutlinedButton.icon(
            onPressed: recarregar,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Atualizar'),
          ),
        ),
      ],
    );
  }

  Widget _cartao(IncidenciaModel inc) {
    final aProcessar = _idEmProcessamento == inc.id;
    final meu = inc.tecnicoId != null && inc.tecnicoId == _repo.utilizadorAtualId;
    final espera = inc.inicio == null
        ? null
        : DateTime.now().difference(inc.inicio!);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: inc.intervencaoEmCurso
              ? TemasCores.avisoBorda
              : TemasCores.borda,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    inc.rotulo ?? 'Manutenção requerida',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: TemasCores.textoPrimario,
                    ),
                  ),
                ),
                _etiquetaEstado(inc),
              ],
            ),
            const SizedBox(height: 10),
            _linha(Icons.factory_outlined, inc.nomePosto ?? 'Posto não indicado'),
            if (inc.codigoRastreio != null)
              _linha(
                Icons.qr_code_2_outlined,
                '${inc.codigoRastreio}'
                '${inc.nomeCliente != null ? ' · ${inc.nomeCliente}' : ''}',
              ),
            if (espera != null)
              _linha(
                Icons.timer_outlined,
                inc.intervencaoEmCurso
                    ? 'Em intervenção há ${formatarDuracao(DateTime.now().difference(inc.dataInicioIntervencao!))}'
                    : 'Linha parada há ${formatarDuracao(espera)}',
              ),
            if ((inc.descricaoOperador ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: TemasCores.superficieTenue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  inc.descricaoOperador!.trim(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: TemasCores.textoSecundario,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _acao(inc, aProcessar: aProcessar, meu: meu),
          ],
        ),
      ),
    );
  }

  Widget _acao(IncidenciaModel inc, {required bool aProcessar, required bool meu}) {
    if (aProcessar) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (!inc.intervencaoEmCurso) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _aceitar(inc),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            backgroundColor: TemasCores.avisoTexto,
            foregroundColor: TemasCores.textoInverso,
          ),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('Aceitar Intervenção'),
        ),
      );
    }

    if (!meu) {
      // O trabalho é de outro técnico: mostrar de quem é vale mais do que um
      // botão que o servidor recusaria.
      return Row(
        children: [
          const Icon(Icons.engineering_rounded,
              size: 16, color: TemasCores.textoTerciario),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Em intervenção por ${inc.nomeTecnico ?? 'outro técnico'}',
              style: const TextStyle(
                fontSize: 12,
                color: TemasCores.textoTerciario,
              ),
            ),
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _concluir(inc),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: TemasCores.sucessoForte,
          foregroundColor: TemasCores.textoInverso,
        ),
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('Registar e Concluir'),
      ),
    );
  }

  Widget _etiquetaEstado(IncidenciaModel inc) {
    final (String texto, Color fundo, Color cor) = inc.intervencaoEmCurso
        ? ('EM INTERVENÇÃO', TemasCores.avisoFundo, TemasCores.avisoTextoForte)
        : ('PENDENTE', TemasCores.erroFundo, TemasCores.erroForte);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: cor,
        ),
      ),
    );
  }

  Widget _linha(IconData icone, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icone, size: 15, color: TemasCores.textoTerciario),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 12,
                color: TemasCores.textoSecundario,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
