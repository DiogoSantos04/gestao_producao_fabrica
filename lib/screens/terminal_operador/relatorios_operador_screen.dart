import 'package:flutter/material.dart';

import '../../core/breakpoints.dart';
import '../../core/ecra_recarregavel.dart';
import '../../core/temas_cores.dart';
import '../../models/incidencia_model.dart';
import '../../repositories/operador_repository.dart';
import '../../services/pdf_service.dart';
import '../../services/relatorio_turno.dart';
import '../../widgets/estado_erro.dart';

class RelatoriosOperadorScreen extends StatefulWidget {
  const RelatoriosOperadorScreen({super.key});

  @override
  State<RelatoriosOperadorScreen> createState() =>
      _RelatoriosOperadorScreenState();
}

class _RelatoriosOperadorScreenState extends State<RelatoriosOperadorScreen>
    implements EcraRecarregavel {
  final OperadorRepository _repo = OperadorRepository();

  List<ResumoDeTurno> _turnos = [];
  bool _aCarregar = true;
  String? _erro;

  /// Nome do operador para o cabeçalho do PDF, lido de `utilizadores`.
  String? _nomeOperador;

  /// Dia cujo PDF está a ser preparado, para travar cliques repetidos.
  DateTime? _aGerar;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  /// Recarregamento pedido pelo shell ao voltar a este separador.
  @override
  Future<void> recarregar() => _carregar(mostrarSpinner: false);

  Future<void> _carregar({bool mostrarSpinner = true}) async {
    if (mostrarSpinner && mounted) {
      setState(() {
        _aCarregar = true;
        _erro = null;
      });
    }

    try {
      // O nome vem na mesma ida à rede: é precisa para o PDF e falhar só na
      // altura do download deixava o operador sem relatório sem saber porquê.
      final resultados = await Future.wait([
        _repo.obterTurnos(),
        _repo.obterNomeUtilizadorAtual(),
      ]);
      if (!mounted) return;
      setState(() {
        _turnos = resultados[0] as List<ResumoDeTurno>;
        _nomeOperador = resultados[1] as String?;
        _erro = null;
        _aCarregar = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = descreverErro(e);
        _aCarregar = false;
      });
    }
  }

  /// Turnos do mês corrente, em hora local.
  ///
  /// A comparação é feita ao dia e inclui o dia 1: comparar com `isAfter` sobre
  /// o dia 1 às 00:00 excluía o trabalho registado exatamente nesse instante.
  Iterable<ResumoDeTurno> get _turnosDoMes {
    final agora = DateTime.now();
    final inicio = DateTime(agora.year, agora.month, 1);
    return _turnos.where((t) => !t.dia.isBefore(inicio));
  }

  int get _fasesDoMes =>
      _turnosDoMes.fold(0, (soma, t) => soma + t.fasesConcluidas);

  int get _paragensDoMes =>
      _turnosDoMes.fold(0, (soma, t) => soma + t.incidencias);

  static String _nomeFicheiro(DateTime d) {
    String d2(int n) => n.toString().padLeft(2, '0');
    return 'Relatorio_Turno_${d2(d.day)}${d2(d.month)}${d.year}.pdf';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemasCores.fundoEcraFrio,
      body: Padding(
        padding: paddingEcra(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              TemasCores.operadorAcentoClaro,
                              TemasCores.operadorAcentoForte,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.analytics_outlined,
                          color: TemasCores.textoInverso,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Área de Relatórios',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: TemasCores.textoPrimarioFrio,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Consulte o histórico de turnos e descarregue os '
                              'relatórios automáticos da sua atividade',
                              style: TextStyle(
                                fontSize: 14,
                                color: TemasCores.textoSecundarioFrio,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _aCarregar ? null : () => _carregar(),
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Recarregar os relatórios',
                  color: TemasCores.operadorAcento,
                ),
              ],
            ),
            const SizedBox(height: 32),
            Expanded(child: _construirCorpo()),
          ],
        ),
      ),
    );
  }

  Widget _construirCorpo() {
    if (_aCarregar) {
      return const Center(
        child: CircularProgressIndicator(color: TemasCores.operadorAcento),
      );
    }

    if (_erro != null) {
      return EstadoErro(
        titulo: 'Não foi possível carregar os relatórios de turno',
        detalhe: _erro,
        aoRepetir: () => _carregar(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _construirMetricas(),
        const SizedBox(height: 32),
        const Text(
          'Relatórios de Turno Disponíveis',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: TemasCores.textoPrimario,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _construirLista()),
      ],
    );
  }

  Widget _construirMetricas() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: TemasCores.borda),
      ),
      color: TemasCores.superficie,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Métricas de Produção Acumuladas (Mês Corrente)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: TemasCores.textoPrimario,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _Metrica(
                    icone: Icons.check_circle_outline,
                    rotulo: 'Fases Superadas',
                    valor: '$_fasesDoMes etapas',
                    fundo: TemasCores.sucessoFundo,
                    borda: TemasCores.sucessoBorda,
                    corRotulo: TemasCores.sucessoTexto,
                    corValor: TemasCores.sucessoForte,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _Metrica(
                    icone: Icons.warning_amber_rounded,
                    rotulo: 'Bloqueios Sinalizados',
                    valor: '$_paragensDoMes alertas',
                    fundo: TemasCores.erroFundo,
                    borda: TemasCores.erroBorda,
                    corRotulo: TemasCores.erroTexto,
                    corValor: TemasCores.erroForte,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirLista() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: TemasCores.borda),
      ),
      color: TemasCores.superficie,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _turnos.isEmpty
            ? const Center(
                child: Text(
                  'Ainda não existem turnos registados com atividade nesta conta.',
                  style: TextStyle(color: TemasCores.textoTerciario),
                ),
              )
            : ListView.separated(
                itemCount: _turnos.length,
                separatorBuilder: (context, index) => const Divider(
                  height: 1,
                  color: TemasCores.superficieSuave,
                ),
                itemBuilder: (context, index) {
                  final turno = _turnos[index];
                  final data = dataCurta(turno.dia);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: TemasCores.operadorAcentoFundo,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.picture_as_pdf_outlined,
                        color: TemasCores.operadorAcento,
                        size: 24,
                      ),
                    ),
                    title: Text(
                      _nomeFicheiro(turno.dia),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: TemasCores.textoPrimario,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        'Dia: $data • Avanços: ${turno.fasesConcluidas} '
                        '• Incidências: ${turno.incidencias}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: TemasCores.textoSecundarioFrio,
                        ),
                      ),
                    ),
                    // O PDF passou a ir à rede buscar o detalhe do dia, pelo
                    // que já não é instantâneo: sem indicação, um toque sem
                    // resposta convida ao segundo toque.
                    trailing: _aGerar == turno.dia
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: TemasCores.operadorAcento,
                            ),
                          )
                        : IconButton(
                            icon: const Icon(
                              Icons.download_outlined,
                              color: TemasCores.operadorAcentoClaro,
                            ),
                            tooltip: 'Descarregar PDF do Turno',
                            onPressed:
                                _aGerar != null ? null : () => _descarregar(turno),
                          ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _descarregar(ResumoDeTurno turno) async {
    if (_aGerar != null) return;
    setState(() => _aGerar = turno.dia);

    try {
      final inicioDia = DateTime(turno.dia.year, turno.dia.month, turno.dia.day);
      final resultados = await Future.wait<dynamic>([
        _repo.obterRegistosDoDia(turno.dia),
        _repo.obterIncidenciasRegistadas(
          desde: inicioDia,
          ate: inicioDia.add(const Duration(days: 1)),
        ),
      ]);

      await PdfService.descarregarRelatorioTurno(
        construirRelatorioTurno(
          nomeOperador: _nomeOperador ?? 'Operador',
          dia: turno.dia,
          registos: resultados[0] as List<RegistoDeTurno>,
          incidencias: resultados[1] as List<IncidenciaModel>,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível gerar o relatório: ${descreverErro(e)}'),
          backgroundColor: TemasCores.erroForte,
        ),
      );
    } finally {
      if (mounted) setState(() => _aGerar = null);
    }
  }
}

/// Caixa de um indicador acumulado do mês.
class _Metrica extends StatelessWidget {
  const _Metrica({
    required this.icone,
    required this.rotulo,
    required this.valor,
    required this.fundo,
    required this.borda,
    required this.corRotulo,
    required this.corValor,
  });

  final IconData icone;
  final String rotulo;
  final String valor;
  final Color fundo;
  final Color borda;
  final Color corRotulo;
  final Color corValor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borda),
      ),
      child: Row(
        children: [
          Icon(icone, color: corValor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rotulo,
                  style: TextStyle(fontSize: 11, color: corRotulo),
                ),
                Text(
                  valor,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: corValor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
