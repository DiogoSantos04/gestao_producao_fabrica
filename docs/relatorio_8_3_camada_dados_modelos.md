# 8.3 Camada de dados e modelos

## 8.3.1 Papel da camada

O diretório `lib/models/` contém dez ficheiros que definem as entidades de domínio da
aplicação. Cada modelo tem três responsabilidades e apenas essas três:

1. **Espelhar uma tabela** da base de dados Supabase, campo a campo, com os tipos de Dart
   correspondentes;
2. **Traduzir o JSON** devolvido pelo PostgREST em objetos tipados, através de uma fábrica
   `fromJson`, absorvendo aí as irregularidades do formato de resposta;
3. **Centralizar as regras de negócio** que dependem exclusivamente dos dados da entidade —
   derivação de estado, cálculos de indicadores, normalização de texto.

O que os modelos **não** fazem: não conhecem o Supabase (não importam o cliente nem executam
queries), não conhecem o Flutter (não importam `material.dart` nem devolvem *widgets*) e não
guardam estado mutável — todos os campos são `final` e as classes são construídas com
construtores `const`. Isto torna-os testáveis sem rede e sem interface, o que se reflete nos
nove ficheiros de teste unitário em `test/models/`.

| Modelo (`lib/models/`) | Tabela / origem | Entidade representada |
| --- | --- | --- |
| `encomenda_model.dart` | `encomendas` | Ordem de produção |
| `estado_ordem.dart` | *derivado* de `encomendas` | Estado da ordem e filtro de estado |
| `historico_model.dart` | `historico_producao` | Registo de conclusão de fase |
| `incidencia_model.dart` | `incidencias` | Paragem de linha e sua manutenção |
| `utilizador_model.dart` | `utilizadores` | Conta de utilizador, perfil e estado |
| `cliente_model.dart` | `clientes` | Cliente da fábrica e sua carteira |
| `pedido_model.dart` | `pedidos_encomenda` | Pedido submetido no portal B2B |
| `fase_model.dart` | `fases_padrao` | Fase do roteiro de fabrico |
| `reason_code_model.dart` | `reason_codes` | Motivo oficial de paragem |
| `checklist_model.dart` | `checklist_execucoes` | Registo de conformidade Poka-Yoke |

---

## 8.3.2 Correspondência com o esquema da base de dados

### Anulabilidade fiel ao esquema

O princípio seguido é que **um campo anulável na base de dados é anulável no modelo**. Não é
uma decisão estética: a versão anterior de `EncomendaModel` declarava todos os campos
obrigatórios e desembrulhava o JSON com conversões diretas (`json['id'] as int`), o que
lançava exceção em qualquer ordem concluída — nessas, `fase_atual_id` é `NULL` por
definição, porque não há fase a decorrer. O modelo tornou-se, por isso, inutilizável e os
ecrãs continuaram a ler `Map<String, dynamic>` cru. Ao alinhar a anulabilidade com o
esquema, os modelos passaram a poder representar qualquer linha que a base de dados aceite.

O mesmo se aplica a `HistoricoModel` (`encomenda_id`, `fase_concluida_id`, `utilizador_id` e
`data_conclusao` são todos anuláveis em `historico_producao`) e a `FaseModel`, onde a versão
anterior exigia `nome_fase_padrao`, `ordem` e `tipos_produto_id`.

Onde a coluna tem valor por omissão no servidor, o modelo replica-o no construtor e na
fábrica, para que os dois lados nunca discordem:

```dart
quantidade: _inteiro(json['quantidade']) ?? 1,
prioridade: (json['prioridade'] as String?) ?? 'Normal',
cancelada: json['cancelada'] == true,
segundosParadosFase: _inteiro(json['segundos_parados_fase']) ?? 0,
```

Repare-se em `json['cancelada'] == true`: a comparação com `true` trata `null` e valores
inesperados como `false` sem lançar exceção, ao contrário de um `as bool`.

### Colunas próprias *versus* campos de junção

Cada modelo separa explicitamente dois grupos de campos, com comentário a marcar a
fronteira. Os primeiros são as colunas da própria tabela; os segundos são valores trazidos
por `select` com junção, documentados como *«campos vindos das junções, quando pedidos»* e
sempre anuláveis, porque **dependem da query e não da linha**. Em `EncomendaModel`:

```dart
/// Campos vindos das junções. Ficam nulos quando a query não os pediu.
final String? nomeCliente;
final String? nomeProduto;
final String? nomeFaseAtual;
final int? ordemFaseAtual;
final String? postoFaseAtual;
final int? postoFaseAtualId;
```

Esta distinção é o que permite reutilizar o mesmo modelo em ecrãs com necessidades de dados
diferentes: uma listagem leve não pede as junções e recebe `null` nesses campos; o detalhe
pede-as e recebe-as preenchidas. Sem a separação, seriam necessários dois modelos por tabela
ou um único modelo com campos obrigatórios que nem sempre se conseguem preencher.

### Absorção das irregularidades do PostgREST

As fábricas `fromJson` concentram três problemas recorrentes do formato de resposta que, de
outro modo, se espalhariam por todos os ecrãs:

**(a) Junções que chegam como objeto ou como lista de um elemento.** Consoante a
cardinalidade que o PostgREST infere da relação, o mesmo `select` pode devolver
`{"clientes": {...}}` ou `{"clientes": [{...}]}`. Os modelos normalizam num único auxiliar:

```dart
static Map<String, dynamic>? _comoMapa(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  // Alguns joins devolvem lista de um elemento em vez de objeto.
  if (v is List && v.isNotEmpty && v.first is Map) {
    return Map<String, dynamic>.from(v.first as Map);
  }
  return null;
}
```

**(b) Aliases diferentes para a mesma junção.** A fase atual é pedida com o alias
`fase_atual` no painel de controlo e sem alias (`fases_padrao`) no ecrã de postos. O modelo
aceita os dois, em vez de obrigar todas as queries a convergir:

```dart
final fase = _comoMapa(json['fase_atual']) ?? _comoMapa(json['fases_padrao']);
```

**(c) Tipos numéricos instáveis entre plataformas.** Em Flutter Web, um `bigint` do Postgres
pode chegar como `num` ou como `String`, e não como `int`. A conversão é tolerante e
documentada:

```dart
static int? _inteiro(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}
```

**(d) Colunas `jsonb` com formato heterogéneo.** A checklist de uma fase (`fases_padrao.checklist`)
chega em três formas distintas conforme quem a escreveu: lista de *strings*, lista de objetos
`{"item": "..."}`, ou o próprio JSON ainda por descodificar quando o *driver* o entrega como
texto. `FaseModel._checklist` normaliza as três para `List<String>`; sem essa normalização, o
operador via no terminal a representação crua do objeto — `{item: Verificar solda}`.

---

## 8.3.3 Regras de negócio centralizadas

Esta é a contribuição mais relevante da camada: cada regra que depende apenas dos dados da
entidade vive no modelo, num único sítio, e não replicada em cada ecrã que dela precisa.

### `EstadoOrdem` — a definição única de estado

A tabela `encomendas` não tem coluna de estado. O estado resulta do cruzamento de três
colunas soltas: `cancelada`, `em_suspenso` e `fase_atual_id`. Antes da reorganização, cada
ecrã fazia esse cruzamento à sua maneira e as regras divergiram — os relatórios chegaram a
classificar como *concluída* uma ordem que estava apenas **na** última fase, o que
inflacionava os indicadores (bug (b), `docs/BUGS_RESOLVIDOS.md`).

O `enum EstadoOrdem` passa a ser a definição única, com ordem de avaliação explícita:

```dart
static EstadoOrdem derivar({
  required bool cancelada,
  required bool emSuspenso,
  required bool temFaseAtual,
}) {
  if (cancelada) return EstadoOrdem.cancelada;      // prevalece sobre tudo
  if (emSuspenso) return EstadoOrdem.emHold;
  if (!temFaseAtual) return EstadoOrdem.concluida;  // percorreu o roteiro todo
  return EstadoOrdem.emProducao;
}
```

A precedência é significativa: uma ordem cancelada continua cancelada mesmo que tenha ficado
suspensa, e uma ordem suspensa mantém fase atual. `EncomendaModel.estado` limita-se a
delegar nesta função, pelo que nenhum ecrã tem de conhecer as três colunas.

O mesmo *enum* concentra ainda os predicados que os ecrãs e relatórios consomem, evitando
comparações dispersas:

| Membro | Significado |
| --- | --- |
| `etiqueta` | Texto do *badge* na interface (`EM PRODUÇÃO`, `ON HOLD`, …) |
| `eFinal` | A ordem saiu da linha, por conclusão ou cancelamento |
| `contaParaIndicadores` | A ordem entra nos KPIs (tudo exceto canceladas) |
| `estaNaLinha` | A ordem ocupa um posto de trabalho (em produção ou em hold) |

`FiltroEstadoOrdem` é um *enum* deliberadamente separado, porque inclui dois valores que não
são estados de nenhuma ordem: `todos` e `atrasada`. O atraso não é um estado guardado — é o
cruzamento de «ainda não saiu da linha» com `data_entrega` já vencida, pelo que uma ordem
atrasada está simultaneamente em produção ou em hold. A propriedade `estado` devolve `null`
nesses dois casos, e a tradução para condições SQL vive num único sítio, o
`EncomendasRepository`.

### `EncomendaModel` — cálculos de produção

- **`progressoNoRoteiro(int totalFases)`** — fração do roteiro já percorrida, entre 0.0 e
  1.0. Era um método privado do `painel_controlo_screen` que ia buscar as fases a um campo de
  estado do ecrã, o que a tornava impossível de testar sem construir a interface. Recebe agora
  o total como parâmetro e é uma função pura. Sem fase atual devolve `1.0` (percorreu tudo);
  sem informação suficiente devolve `0.0` — a barra fica vazia em vez de mostrar um valor falso.
- **`cumpriuPrazo(prometida, dataConclusao)`** — base da taxa de entrega no prazo. Compara
  **ao dia**, não ao instante, pelo que entregar no próprio dia do prazo conta como cumprido.
  Sem prazo prometido devolve `false`: o indicador só pode contar ordens que tinham prazo a
  cumprir.
- **`dataEntregaIso`** — formata a data como `aaaa-mm-dd`, o formato que o Postgres espera na
  escrita. Evita que cada ecrã improvise a sua própria formatação.
- **`incidenciaAtiva`** — devolve a primeira incidência sem *line clearance* validado, ou
  `null`. É o que determina se a ordem está bloqueada na linha.

Três campos merecem nota pela semântica que documentam:

- `dataInicioFase` — momento em que a ordem entrou na fase atual, escrito pela RPC
  `avancar_fase_encomenda` na mesma transação da transição. É a origem do cronómetro do
  terminal do operador.
- `segundosParadosFase` — segundos que a fase esteve parada em WIP Hold, acumulado pelo
  servidor a cada *line clearance* e reposto a zero na mudança de fase. Existe para que o
  tempo de avaria não conte como tempo de produção **sem falsificar** `dataInicioFase`, que
  tem de continuar a ser o momento real em que a fase começou.
- `dataConfirmacaoRececao` — deliberadamente fora de `EstadoOrdem`: a receção é logística
  posterior ao fabrico, e uma ordem recebida continua a ser uma ordem concluída para todos os
  indicadores.

### `IncidenciaModel` — ciclo de vida da paragem

O modelo cobre o ciclo completo (registo em WIP Hold → intervenção técnica → *line
clearance*), com os campos agrupados por etapa. A versão anterior tinha cinco campos, todos
obrigatórios, e ignorava todo o fluxo de manutenção.

As regras de negócio expõem-se como propriedades derivadas:

| Propriedade | Regra |
| --- | --- |
| `estaAberta` | `!lineClearanceValidado` — a incidência ainda bloqueia a linha |
| `aguardaLineClearance` | Reparação feita, falta a validação da qualidade |
| `intervencaoEmCurso` | Um técnico pegou nela e ainda não a fechou |
| `temRegistoDoTecnico` | Existe diagnóstico ou nota técnica preenchidos |
| `responsavelIntervencao` | Técnico interno, ou entidade externa em alternativa |
| `inicio` | `dataRegisto ?? createdAt` — momento efetivo da paragem |

Duas distinções são conceptualmente importantes e ficam registadas no próprio modelo:

**Sintoma *versus* causa.** `descricaoOperador` é o sintoma relatado por quem parou a linha;
`diagnostico` é a causa apurada pelo técnico. São campos diferentes porque respondem a
perguntas diferentes.

**Tempo de espera *versus* tempo de reparação.** `duracaoIntervencao` conta a partir do
momento em que o técnico pegou no trabalho (`dataInicioIntervencao`), e não do registo da
avaria — é a base do MTTR. O tempo que a incidência passou à espera de atendimento é
`tempoEspera`, uma métrica distinta. Somar as duas escondia qual dos dois problemas está a
custar tempo à fábrica.

```dart
/// Tempo de reparação — a base do MTTR.
Duration? get duracaoIntervencao {
  final inicio = dataInicioIntervencao;
  final fim = dataFimManutencao;
  if (inicio == null || fim == null) return null;   // intervenção ainda aberta
  return fim.difference(inicio);
}
```

Há ainda a propriedade `rotulo`, que resolve uma transição de esquema: a coluna `motivo` é
texto livre e deixou de ser preenchida quando o terminal passou a gravar motivos
estruturados em `reason_codes` (bug (D)). `rotulo` percorre `motivo → descricaoReasonCode →
categoriaReasonCode` e devolve o primeiro com texto útil, para que registos antigos e novos
apareçam preenchidos no mesmo ecrã.

### `UtilizadorModel` — perfis, acesso e segurança

A coluna `perfil` é texto livre e acumulou variantes históricas para o mesmo papel
(`Admin`/`Administrador`, `Operador`/`Funcionario`/`Funcionário`, `Tecnico`/`Técnico`). O
`enum PerfilUtilizador` normaliza-as num único ponto — antes, cada ecrã repetia a sua própria
lista de comparações em minúsculas — e mantém separadas três representações:

- `desdeTexto(...)` — leitura tolerante, com `desconhecido` como caso por omissão;
- `valorBd` — o valor canónico a **gravar** na coluna;
- `etiqueta` — o texto a **mostrar** na interface (que não coincide com o valor gravado:
  `Operador` grava-se assim, mas apresenta-se como `Funcionário`).

O `enum EstadoConta` segue a mesma estrutura, com uma regra de segurança explícita: qualquer
valor não reconhecido, ou nulo, resulta em `pendente` — nunca em `ativo`.

```dart
static EstadoConta desdeTexto(String? valor) {
  switch ((valor ?? '').trim().toLowerCase()) {
    case 'ativo':   return EstadoConta.ativo;
    case 'inativo': return EstadoConta.inativo;
    default:        return EstadoConta.pendente;   // falha fechado
  }
}
```

O estado da conta é usado pelo `AuthService` como travão de acesso, pelo que tem de **falhar
fechado**: um campo corrompido ou por preencher não pode dar entrada na aplicação.

Duas notas finais sobre este modelo:

- **Não tem, nem pode ter, campo de palavra-passe.** As credenciais vivem exclusivamente no
  Supabase Auth; a tabela `utilizadores` guarda apenas o perfil aplicacional (bug (c),
  `docs/BUGS_RESOLVIDOS.md`).
- **`iniciais`** calcula as iniciais do avatar (`"Diogo Santos"` → `"DS"`). O cálculo estava
  duplicado em dois ecrãs e dava resultados diferentes para o mesmo nome.

### `PedidoModel` e `EstadoPedido` — portal B2B

`pedidos_encomenda.estado` é texto livre com omissão `'Pendente'`, e os ecrãs comparavam a
string à mão em vários sítios — chegou a existir um
`.or('estado.ilike.Aprovado%,estado.eq.Aprovado')` para tolerar variações de escrita. O
`enum EstadoPedido` faz a leitura por prefixo normalizado (`startsWith('aprovado')`,
`startsWith('em produ')`) e expõe `valorBd` para a escrita. A regra de fluxo fica também no
*enum*: `aguardaDecisao` só é verdadeiro no estado `pendente`, porque apenas um pedido
pendente pode ser aprovado ou rejeitado.

### `ClienteModel` — carteira e composição

É o único modelo que **compõe outros modelos**: as junções `encomendas` e `pedidos_encomenda`
são convertidas em `List<EncomendaModel>` e `List<PedidoModel>` na própria fábrica. Substitui
o acesso por `Map` no ecrã de clientes, que dependia de quatro auxiliares defensivos
(`_obterTotalEncomendas`, `_temEncomendas`, `_obterListaEncomendas`, `_obterListaPedidos`)
para desembrulhar as mesmas junções.

Centraliza ainda duas regras de apresentação:

- `contactoFormatado` / `formatarTelefone` — agrupa os dígitos de 3 em 3 preservando um `+`
  inicial (`+351 912 345 678`). O método estático é **partilhado com o formatador de input do
  ecrã**, para que o texto escrito e o texto apresentado sigam exatamente a mesma regra.
- `corresponde(termo)` — define o que conta como correspondência de pesquisa: nome, email,
  contacto, NIF, pessoa de contacto ou morada.

`MetricasClientes` acompanha o modelo e transporta os contadores do topo do ecrã. São
apurados no servidor por decisão explícita: contá-los sobre a lista carregada daria o tamanho
da página em vez do total da carteira.

### `FaseModel` — roteiro configurável

`nomePublico` existe porque o roteiro é configurável pelo administrador. Um mapa fixo de
tradução escrito em Dart deixaria de cobrir qualquer fase criada depois da compilação. A
regra de resolução é uma só, em `nomeParaCliente`: usa o nome público quando existe e não
está vazio, e o nome técnico caso contrário.

```dart
String get nomeParaCliente {
  final publico = nomePublico?.trim() ?? '';
  return publico.isEmpty ? nomeFasePadrao : publico;
}
```

O portal do cliente recebe já este nome resolvido pela função `rastrear_encomenda` no
servidor; a propriedade serve os ecrãs do administrador, para lhe mostrar o que o cliente vai
efetivamente ver. O modelo mantém também `postoTrabalho` (nome em texto, coluna legada
sincronizada por *trigger*) e `postoTrabalhoId` (ligação real, introduzida pelo bug (a)),
documentando qual é qual.

### `ReasonCodeModel` — motivos estruturados de paragem

Substitui uma lista de cinco *strings* escrita em Dart que o terminal do operador concatenava
no campo de texto livre da incidência, no formato `'[Motivo] observações'`. Sem código
estruturado, uma análise de Pareto das paragens era impossível (bug (D),
`docs/AlteracoesNoOperador.md`). A fábrica garante que `categoria` nunca fica vazia
(omissão `'Geral'`) e `rotulo` define o texto único dos *dropdowns*: `[Categoria] descrição`.

### `checklist_model.dart` — as duas metades do registo Poka-Yoke

Este ficheiro contém dois modelos porque o registo de conformidade tem dois sentidos
distintos, e tratá-los como uma só classe obrigaria a campos que só fazem sentido de um dos
lados.

A checklist obrigatória da fase era, até então, apenas um *gate* de interface: o operador
marcava os pontos, o diálogo devolvia um `bool` e nada ficava gravado. Um mecanismo à prova
de erro sem registo não é rastreável — ninguém sabe quem validou que ponto, a que horas, em
que unidade produzida.

- **`PontoValidado`** é o que **sai** do terminal para a RPC `avancar_fase_encomenda`. Tem
  apenas `toJson`, nunca `fromJson`. O campo `marcadoEm` é o instante em que a caixa foi
  marcada, e não o da conclusão da fase: a diferença entre os dois é o que distingue uma
  verificação feita ponto a ponto de uma série de cliques no fim. O `conforme` vai sempre a
  `true` porque um ponto não conforme não fecha a fase — abre uma incidência, e a RPC recusa
  o avanço se algum vier a `false`.
- **`RegistoConformidade`** é o que se **lê de volta** de `checklist_execucoes`. Tem apenas
  `fromJson`. O campo `item` guarda o texto do ponto *tal como estava* quando foi validado:
  é uma cópia, não uma referência, porque o administrador pode editar a checklist da fase
  depois da produção e o registo tem de continuar a dizer o que foi efetivamente verificado
  nesse dia. `conforme = false` marca um desvio — hoje, o avanço administrativo sem validação.

---

## 8.3.4 Padrões transversais

Cinco decisões repetem-se em todos os modelos e constituem a convenção da camada:

1. **Imutabilidade.** Todos os campos são `final` e os construtores são `const`. Um modelo
   nunca é alterado depois de construído; quando é preciso uma variante, existe `copyWith`
   (`UtilizadorModel`).
2. **Fábrica `fromJson` única por modelo.** Toda a tradução do formato do servidor está num
   só método por entidade. Se o esquema mudar, há um sítio a alterar.
3. **Conversão tolerante, nunca *cast* direto.** `_inteiro`, `_data`, `_mapa`, `_lista` e a
   comparação `== true` para booleanos. Um campo inesperado degrada para `null` ou para a
   omissão documentada, em vez de rebentar o ecrã inteiro.
4. **Valores por omissão alinhados com o servidor.** O que a base de dados assume por
   omissão, o modelo assume também — em ambos os construtores e fábricas.
5. **Regras de negócio como propriedades derivadas.** Uma regra que depende só dos dados da
   entidade é um `get` no modelo, testável isoladamente. Uma regra que precisa de dados
   externos recebe-os como parâmetro (`progressoNoRoteiro(totalFases)`), mantendo a função
   pura em vez de dar ao modelo acesso ao repositório.

Estes padrões são o que permite que `test/models/` teste toda a camada com objetos literais,
sem base de dados, sem rede e sem construir um único *widget*.
