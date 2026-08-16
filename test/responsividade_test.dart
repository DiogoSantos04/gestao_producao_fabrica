import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/core/breakpoints.dart';
import 'package:gestao_producao_fabrica/models/cliente_model.dart';
import 'package:gestao_producao_fabrica/models/encomenda_model.dart';
import 'package:gestao_producao_fabrica/models/utilizador_model.dart';
import 'package:gestao_producao_fabrica/screens/dashboard_admin/dialogos/dialogo_cancelar_ordem.dart';
import 'package:gestao_producao_fabrica/screens/dashboard_admin/widgets/barra_filtros_clientes.dart';
import 'package:gestao_producao_fabrica/screens/dashboard_admin/widgets/cartao_kpi.dart';
import 'package:gestao_producao_fabrica/screens/dashboard_admin/widgets/cartao_ordem_producao.dart';
import 'package:gestao_producao_fabrica/screens/dashboard_admin/widgets/kpis_carteira_clientes.dart';
import 'package:gestao_producao_fabrica/screens/dashboard_admin/widgets/linha_cliente.dart';
import 'package:gestao_producao_fabrica/screens/dashboard_admin/widgets/linha_utilizador.dart';
import 'package:gestao_producao_fabrica/screens/dashboard_admin/widgets/painel_ultimas_encomendas.dart';
import 'package:gestao_producao_fabrica/widgets/estado_erro.dart';
import 'package:gestao_producao_fabrica/widgets/rodape_paginacao.dart';

/// Larguras lógicas a que a interface tem de aguentar-se.
///
/// 320 é o telemóvel pequeno (iPhone SE em retrato); 360 o Android comum; 768
/// o tablet em retrato; 1280 o desktop. Um widget que sobrevive a 320 e a 1280
/// sobrevive ao que está pelo meio.
const Map<String, Size> _ecras = {
  'telemóvel pequeno (320)': Size(320, 640),
  'telemóvel (360)': Size(360, 800),
  'tablet (768)': Size(768, 1024),
  'desktop (1280)': Size(1280, 900),
};

/// Monta [widget] em cada largura e falha se o Flutter reportar overflow.
///
/// Um `RenderFlex overflowed` é entregue como exceção ao teste, e é
/// exatamente o defeito visual que se está a caçar: a barra amarela e preta,
/// ou o conteúdo cortado à direita.
Future<void> _semOverflow(
  WidgetTester tester,
  Widget Function() construir,
) async {
  // As falhas são acumuladas em vez de rebentarem à primeira: saber que um
  // widget estoura a 320 **e** a 360 é informação diferente de saber que
  // estoura só no ecrã mais pequeno.
  final falhas = <String>[];

  for (final entrada in _ecras.entries) {
    tester.view.physicalSize = entrada.value;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // `SingleChildScrollView` cobre a altura: o que se testa aqui é a
          // largura, e um ecrã alto de mais é um problema diferente (e
          // resolvido por scroll em toda a app).
          body: SingleChildScrollView(child: construir()),
        ),
      ),
    );
    await tester.pump();

    final excecao = tester.takeException();
    if (excecao != null) falhas.add('${entrada.key}: $excecao');
  }

  expect(falhas, isEmpty, reason: falhas.join('\n'));
}

/// Larguras a que uma **linha de tabela** é realmente montada na app.
///
/// As tabelas de clientes e de utilizadores não usam a largura do ecrã: abaixo
/// de [Breakpoints.compacto] são embrulhadas em `SingleChildScrollView`
/// horizontal com 700 px fixos, e acima disso ocupam o ecrã menos o padding.
/// Testá-las à largura do telemóvel dava um falso positivo — nunca são
/// montadas assim.
///
/// 552 é o caso apertado que sobra: ecrã de 600 px, que já não é "compacto" e
/// portanto não ganha o scroll horizontal, menos os 24 px de padding de cada
/// lado que [paddingEcra] aplica.
const Map<String, double> _largurasDeLinha = {
  'ecrã de 600 sem scroll horizontal (552 úteis)': 552,
  'envelope de scroll horizontal (700)': 700,
  'tablet (720 úteis)': 720,
  'desktop (1200 úteis)': 1200,
};

/// Como [_semOverflow], mas para widgets que vivem numa largura imposta pelo
/// contentor e não pela do ecrã.
Future<void> _semOverflowEmLarguras(
  WidgetTester tester,
  Widget Function() construir,
) async {
  final falhas = <String>[];

  for (final entrada in _largurasDeLinha.entries) {
    tester.view.physicalSize = Size(entrada.value + 100, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: entrada.value, child: construir()),
          ),
        ),
      ),
    );
    await tester.pump();

    final excecao = tester.takeException();
    if (excecao != null) falhas.add('${entrada.key}: $excecao');
  }

  expect(falhas, isEmpty, reason: falhas.join('\n'));
}

EncomendaModel _encomenda({String? nomeLongo}) => EncomendaModel.fromJson({
      'id': 1,
      'codigo_rastreio': 'TRC-4D3155',
      'data_entrega': '2026-09-30',
      'quantidade': 120,
      'prioridade': 'Urgente',
      'clientes': {
        'nome_cliente': nomeLongo ?? 'Fábrica de Bebidas do Centro',
      },
      'tipos_produto': {
        'nome_tipo_produto': nomeLongo ?? 'Garrafa de Vidro Personalizada',
      },
      'fase_atual': {
        'nome_fase_padrao': nomeLongo ?? 'Montagem e Acabamento Final',
        'ordem': 3,
        'posto_trabalho': 'Linha de Montagem 2',
      },
    });

ClienteModel _cliente({String? nomeLongo}) => ClienteModel.fromJson({
      'id': 1,
      'nome_cliente': nomeLongo ?? 'Fábrica de Bebidas do Centro',
      'email': 'geral@fabricadebebidasdocentro.pt',
      'contacto': '+351 912 345 678',
      'nif': '501234567',
      'ativo': true,
    });

UtilizadorModel _utilizador({String? nomeLongo}) => UtilizadorModel.fromJson({
      'utilizador_id': 'abc-123',
      'nome_utilizador': nomeLongo ?? 'Maria Fernanda Albuquerque',
      'email': 'maria.fernanda.albuquerque@fabrica.pt',
      'perfil': 'Operador',
      'estado_conta': 'ativo',
    });

/// Nome propositadamente longo, sem espaços onde partir.
///
/// Texto que não parte é o caso que rebenta layouts: um `Text` sem `ellipsis`
/// dentro de uma `Row` sem `Expanded` empurra tudo o resto para fora do ecrã.
const String _textoLongo =
    'ProdutoComNomeExtremamenteLongoSemEspacosParaPartir';

void main() {
  group('Responsividade — componentes partilhados', () {
    testWidgets('EstadoErro', (tester) async {
      await _semOverflow(
        tester,
        () => EstadoErro(
          titulo: 'Não foi possível carregar os dados da produção',
          detalhe: 'SocketException: Failed host lookup: '
              'hnilivakkwvnvgyblmss.supabase.co',
          aoRepetir: () {},
        ),
      );
    });

    testWidgets('EstadoErro.compacto', (tester) async {
      await _semOverflow(
        tester,
        () => EstadoErro.compacto(
          titulo: 'O estado dos postos pode estar desatualizado.',
          detalhe: 'Erro de rede',
          aoRepetir: () {},
        ),
      );
    });

    testWidgets('RodapePaginacao', (tester) async {
      await _semOverflow(
        tester,
        () => RodapePaginacao(
          aCarregar: false,
          erro: 'Não foi possível carregar mais resultados da lista.',
          aoCarregarMais: () {},
        ),
      );
    });
  });

  group('comScrollHorizontalAbaixoDe', () {
    Future<void> montar(WidgetTester tester, double largura) async {
      tester.view.physicalSize = Size(largura, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: comScrollHorizontalAbaixoDe(
              700,
              const SizedBox(height: 40, child: Text('tabela')),
            ),
          ),
        ),
      );
    }

    testWidgets('com espaço a mais, a tabela ocupa a largura toda',
        (tester) async {
      await montar(tester, 900);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('sem espaço, ganha scroll horizontal à largura mínima',
        (tester) async {
      await montar(tester, 500);

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.getSize(find.byType(SizedBox).first).width, 700);
      expect(tester.takeException(), isNull);
    });

    testWidgets('exatamente na largura mínima não precisa de scroll',
        (tester) async {
      await montar(tester, 700);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });
  });

  group('Responsividade — painel do administrador', () {
    testWidgets('CartaoKpi', (tester) async {
      await _semOverflow(
        tester,
        () => const CartaoKpi(
          estilo: EstiloKpi.principal,
          titulo: 'Entregas Confirmadas',
          valor: '39%',
          subtitulo: '35 de 90 concluídas recebidas',
          icone: Icons.inventory_2_outlined,
          corIcone: Colors.green,
        ),
      );
    });

    testWidgets('ItemKpiCompacto', (tester) async {
      await _semOverflow(
        tester,
        () => const ItemKpiCompacto(
          estilo: EstiloKpi.postos,
          titulo: 'Parados / WIP Hold',
          valor: '12',
          icone: Icons.warning_amber_rounded,
          cor: Colors.red,
        ),
      );
    });

    testWidgets('KpisCarteiraClientes', (tester) async {
      await _semOverflow(
        tester,
        () => const KpisCarteiraClientes(
          metricas: MetricasClientes(
            total: 128,
            ativosPortal: 96,
            comEncomendas: 74,
            totalEncomendas: 1240,
          ),
        ),
      );
    });

    testWidgets('BarraFiltrosClientes', (tester) async {
      final controlador = TextEditingController();
      addTearDown(controlador.dispose);

      await _semOverflow(
        tester,
        () => BarraFiltrosClientes(
          controladorPesquisa: controlador,
          filtro: FiltroCliente.todos,
          aoMudarFiltro: (_) {},
        ),
      );
    });

    testWidgets('LinhaCliente', (tester) async {
      await _semOverflowEmLarguras(
        tester,
        () => LinhaCliente(
          cliente: _cliente(),
          aoAbrirDetalhe: () {},
          aoEditar: () {},
        ),
      );
    });

    testWidgets('LinhaCliente com nome longo sem espaços', (tester) async {
      await _semOverflowEmLarguras(
        tester,
        () => LinhaCliente(
          cliente: _cliente(nomeLongo: _textoLongo),
          aoAbrirDetalhe: () {},
          aoEditar: () {},
        ),
      );
    });

    testWidgets('LinhaUtilizador', (tester) async {
      await _semOverflowEmLarguras(
        tester,
        () => LinhaUtilizador(
          utilizador: _utilizador(),
          posto: const {'nome_posto': 'Linha de Montagem 2'},
          aoAbrirDetalhe: () {},
          aoAprovar: () {},
          aoRejeitar: () {},
          aoEditar: () {},
          aoAlterarEstado: (EstadoConta _) {},
        ),
      );
    });

    testWidgets('LinhaUtilizador com nome longo sem espaços', (tester) async {
      await _semOverflowEmLarguras(
        tester,
        () => LinhaUtilizador(
          utilizador: _utilizador(nomeLongo: _textoLongo),
          posto: const {'nome_posto': _textoLongo},
          aoAbrirDetalhe: () {},
          aoAprovar: () {},
          aoRejeitar: () {},
          aoEditar: () {},
          aoAlterarEstado: (EstadoConta _) {},
        ),
      );
    });

    testWidgets('CartaoOrdemProducao', (tester) async {
      await _semOverflow(
        tester,
        () => CartaoOrdemProducao(
          encomenda: _encomenda(),
          progresso: 0.4,
          aoAvancarFase: () {},
          aoWipHold: () {},
          aoRegistoTecnico: (_) {},
          aoLineClearance: (_) {},
          aoHistorico: () {},
          aoEditar: () {},
          aoCancelar: (_) {},
        ),
      );
    });

    testWidgets('CartaoOrdemProducao com nomes longos sem espaços',
        (tester) async {
      await _semOverflow(
        tester,
        () => CartaoOrdemProducao(
          encomenda: _encomenda(nomeLongo: _textoLongo),
          progresso: 0.4,
          aoAvancarFase: () {},
          aoWipHold: () {},
          aoRegistoTecnico: (_) {},
          aoLineClearance: (_) {},
          aoHistorico: () {},
          aoEditar: () {},
          aoCancelar: (_) {},
        ),
      );
    });

    testWidgets('DialogoCancelarOrdem em telemóvel deitado', (tester) async {
      // Telemóvel na horizontal: 360 px de altura. É também, aproximadamente,
      // o que sobra num telemóvel em pé com o teclado aberto — a situação
      // normal num diálogo com campos de texto.
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => DialogoCancelarOrdem.mostrar(
                  context,
                  referencia: 'ORD-2026-0042',
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('PainelUltimasEncomendas em modo compacto', (tester) async {
      await _semOverflow(
        tester,
        () => PainelUltimasEncomendas(
          encomendas: [_encomenda(), _encomenda(nomeLongo: _textoLongo)],
          eDesktop: false,
        ),
      );
    });
  });
}
