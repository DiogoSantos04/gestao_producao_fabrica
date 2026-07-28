# Notas de Alterações — Centralização das cores (`dashboard_admin`)

## O problema

O módulo `lib/screens/dashboard_admin/` tinha **321 cores escritas à mão** —
24 literais `Color(0xFF…)` e 297 `Colors.x.shadeN` — contra apenas 9 usos de
`TemasCores` em toda a aplicação. O `TemasCores.obterTema()` definia um tema
Material 3 completo que praticamente ninguém consumia, e `const Color(0xFF111625)`
aparecia repetido em 5 ficheiros como cor de marca sem nome.

Consequência: mudar a identidade visual obrigava a tocar em 321 sítios.

## O que foi feito

Todas as cores do módulo passaram a vir de `lib/core/temas_cores.dart`.
**O aspeto da aplicação não muda**: cada token aponta exatamente para o mesmo
valor hexadecimal que estava escrito no sítio que substituiu.

| | Antes | Depois |
|---|---|---|
| Cores em bruto em `dashboard_admin` | 321 | **0** \* |
| Usos de `TemasCores` | 9 (nenhum neste módulo) | **507** |

\* Sobram duas ocorrências de `Colors.transparent`, que é ausência de cor e não
faz parte da identidade visual.

## `lib/core/temas_cores.dart` — a nova estrutura

O ficheiro passou de 31 para ~370 linhas, organizado em duas camadas:

### 1. `Paleta` — os valores em bruto

A **única** lista de hexadecimais da aplicação. Contém as rampas do Material
(`neutro50…900`, `azul50…900`, `verde`, `vermelho`, `ambar`, `laranja`, …) mais
os tons próprios do projeto (ardósia, e os cinzas `0xFF707070` / `0xFFEAEAEA`
que estavam fora da rampa Material).

Estão declaradas em hexadecimal — e não como `Colors.x.shadeN` — porque os
`shadeN` do Flutter são *getters* e não podem ser usados em contexto `const`.
Os valores foram copiados do próprio SDK, pelo que são idênticos aos originais.

### 2. `TemasCores` — os papéis

Os ecrãs usam sempre estes nomes, nunca a `Paleta` nem hexadecimais:

- **Marca** — `marcaEscura` (o antigo `0xFF111625`), `marcaAcento`, `acaoPrincipal`, `primariaRoxa`
- **Superfícies** — `fundoEcra`, `fundoEcraFrio`, `superficie`, `superficieSuave`, `superficieTenue`, `superficieInerte`, `superficieEscura`
- **Contornos e sombras** — `borda`, `bordaForte`, `bordaNeutra`, `bordaEscura`, `sombraTenue`, `sombraSuave`, `sombraMarcada`, `sombraBase`, `veuModal`
- **Texto** — `textoPrimario`, `textoSecundario`, `textoTerciario`, `textoDesativado`, `textoApoio`/`Forte`/`Intenso`, `textoPrimarioFrio`, `textoSecundarioFrio`, e a família `textoInverso*` para fundos escuros
- **Estados** — `sucesso`, `erro`, `aviso`, `alerta`, `info`, `inativo`. Cada um segue sempre a mesma escala de papéis: `Fundo` → `FundoForte` → `Borda` → `Claro`/`Medio` → *base* → `Forte` → `Texto` → `TextoForte` → `TextoIntenso`
- **Acentos de categorização** — `acentoAzul`, `acentoIndigo`, `acentoTurquesa`, `acentoRoxo`, … para distinguir séries e perfis entre si (sem valor semântico de estado)
- **Painel de resumo** — `resumoFundo`/`Borda`/`Texto`/`TextoForte` (o azul-acinzentado do cartão de carga estimada)
- **Avatares** — `paletaAvatares`
- **Gráficos** — `graficoBarraTopo`, `graficoBarraBase`, `graficoGrelha`, `avaliacaoEstrela`

Os nomes antigos (`laranjaAlerta`, `verdeSucesso`, `vermelhoErro`,
`fundoEscuroSidebar`, `primariaRoxa`) foram mantidos como aliases, para não
partir o `login_screen`, o `registo_screen` nem o `mensagens.dart`.

`obterTema()` ficou inalterado.

## Ficheiros alterados

### `lib/core/`

- **`temas_cores.dart`** — reescrito com as duas camadas descritas acima.
- **`iniciais.dart`** — a paleta dos avatares (`_coresAvatar`) estava aqui
  escrita à mão; passou a apontar para `TemasCores.paletaAvatares`. A ordem da
  lista foi preservada, porque a cor de cada pessoa deriva do `hashCode` do nome
  e mudar a ordem mudaria a cor dos avatares existentes.

### `lib/screens/dashboard_admin/`

Todos os ecrãs receberam `import '../../core/temas_cores.dart'` e tiveram as
cores substituídas por tokens:

| Ficheiro | Cores substituídas |
|---|---|
| `painel_controlo_screen.dart` | 97 |
| `criar_encomenda_screen.dart` | 73 |
| `informacoes_clientes_screen.dart` | 72 |
| `relatorios_admin_screen.dart` | 55 |
| `gestao_utilizadores_screen.dart` | 45 |
| `gestao_fluxos_screen.dart` | 39 |
| `dashboard_principal_screen.dart` | 37 |
| `dashboard_admin_shell.dart` | 32 |
| `postos_trabalho_screen.dart` | 29 |
| `widgets/cartao_kpi.dart` | 14 |
| `pedidos_clientes_admin_screen.dart` | 14 |

`widgets/etiqueta_estado.dart` e `widgets/mouse_drag_scroll_behavior.dart` não
tinham cores próprias — recebem-nas de quem os usa — e ficaram intactos.

## Notas sobre decisões concretas

- **`0xFF111625`** aparecia como fundo da barra lateral *e* como cor de botões,
  barras de progresso e breadcrumbs. Passou a chamar-se `marcaEscura` (e não
  `marcaFundoEscuro`), porque é o tom escuro da marca e não apenas um fundo.
- **`Colors.white.withOpacity(0.08)`** na barra lateral tornou-se a constante
  `realceSobreEscuro` = `0x14FFFFFF` (0.08 × 255 = 20 = 0x14, o mesmo valor).
  Isto eliminou 2 avisos de `withOpacity` deprecado.
- **Cinzas fora da rampa Material** (`0xFF707070` e `0xFFEAEAEA`, usados nas
  etiquetas de acesso ao portal) ganharam nomes próprios — `estadoAtivoFundo` e
  `estadoInativoFundo` — em vez de serem arredondados para o cinza mais próximo,
  o que teria mudado o aspeto.
- **Comportamentos estranhos foram preservados**, tal como pedido. Por exemplo,
  em `pedidos_clientes_admin_screen.dart` o estado "Aprovado" mostra-se a verde
  e *todos* os outros estados não-pendentes a vermelho, incluindo "Em Produção".
  A troca de cores por tokens não alterou esta regra.

## Verificação

`flutter analyze` foi corrido a cada ficheiro alterado e no fim sobre `lib/`:

```
Antes:   69 issues found   (31 em dashboard_admin)
Depois:  67 issues found   (29 em dashboard_admin)
```

Nenhum **erro**. Os 67 avisos que restam são todos anteriores a este trabalho
(`withOpacity` deprecado, `DropdownButtonFormField.value` deprecado,
`avoid_print` nos serviços, etc.). Os 2 que desapareceram são os `withOpacity`
substituídos pela constante `realceSobreEscuro`.

## Como mudar a identidade visual a partir de agora

1. Para trocar um tom (ex.: o azul da marca), editar o valor em `Paleta`.
2. Para mudar o *papel* de uma cor (ex.: os avisos passarem de âmbar a laranja),
   editar a que valor da `Paleta` o token de `TemasCores` aponta.

Em ambos os casos, um ficheiro — não 321 sítios.

---

# Notas de Alterações — Paginação (`dashboard_admin`)

## O problema

Existia um único `.limit()` em toda a camada de dados — nas últimas 15 encomendas
do dashboard. O painel de controlo, a carteira de clientes e os relatórios
carregavam **tabelas inteiras**, com as junções todas. Com 5.000 encomendas o
painel deixava de abrir.

## A decisão que moldou o trabalho

Paginar não era só cortar a query. Nos três ecrãs, **os filtros, a pesquisa e os
KPIs eram calculados em memória sobre a lista completa**. Pôr um `.range()` no
repositório sem mexer em mais nada tornaria a aplicação mentirosa: a pesquisa
deixaria de encontrar a encomenda da página 4, e "12 em produção" passaria a
significar "12 nas 50 que estão carregadas".

Por isso **os filtros e a pesquisa subiram para o servidor ao mesmo tempo que a
paginação desceu**. É a mesma alteração, não duas. Um painel lento é visível; um
KPI errado não é.

## Abordagem

- **Scroll infinito**, não páginas numeradas — as listas são ordenadas por
  recência e "página 7 de 84" não tem significado num painel operacional. Um
  botão "Carregar mais" fica no fim como saída manual, para o caso de a janela
  ser alta o bastante para a página caber sem haver scroll.
- **50 linhas por página** (`tamanhoPaginaPadrao`). Enche mais do que um ecrã em
  qualquer resolução e mantém o primeiro desenho imediato.
- **Pesquisa com 300 ms de espera** (`esperaPesquisa`), para não disparar uma
  query por tecla escrita.
- **`temMais` sem query de `count`**: pede-se `tamanho + 1` linhas e descarta-se
  a última. A linha a mais é a sonda que diz se ainda há resultados a seguir.

## Peças novas

### `lib/core/paginacao.dart`

`PaginaResultado<T>` (itens + `temMais`), `tamanhoPaginaPadrao` e `esperaPesquisa`.
Partilhado pelos três ecrãs, para o tamanho de página não ficar escrito em três
sítios diferentes.

### `FiltroEstadoOrdem` (em `models/estado_ordem.dart`)

Substitui as strings `'TODOS'`/`'EM_PRODUCAO'`/… do `SegmentedButton`. Existe
separado de `EstadoOrdem` porque inclui "todos", que não é estado de ordem nenhuma.

### `FiltroCliente` e `MetricasClientes` (em `models/cliente_model.dart`)

O primeiro substitui as strings do dropdown; o segundo transporta os quatro
contadores do topo do ecrã de clientes.

---

## Ecrã 1 — Painel de Controlo

O primeiro a ser feito, por ser o que rebentava mais cedo e o único com realtime,
filtros e pesquisa em simultâneo. Define o molde dos outros.

### Filtro de estado traduzido para SQL

`EncomendasRepository._aplicarFiltroEstado` segue a mesma precedência de
`EstadoOrdem.derivar` — cancelada → em hold → concluída → em produção:

| Filtro | Condições |
|:---|:---|
| Canceladas | `cancelada = true` |
| Todas | `cancelada = false` |
| ON HOLD | `cancelada = false AND em_suspenso = true` |
| Em Produção | `cancelada = false AND em_suspenso = false AND fase_atual_id IS NOT NULL` |
| Concluídas | `cancelada = false AND em_suspenso = false AND fase_atual_id IS NULL` |

As canceladas continuam a aparecer **apenas** no seu próprio filtro, tal como
quando a filtragem era feita em memória.

### Pesquisa

Cobre código de rastreio e nome de cliente, como antes. O nome vive noutra tabela
e o PostgREST não deixa juntar num único `or` uma coluna própria com uma coluna
de um recurso embebido; os clientes são por isso resolvidos primeiro (tabela
pequena) e entram na query como lista de chaves estrangeiras.

### Realtime

O canal disparava `_carregarDados`, que recarregava tudo. Passou a
`_recarregarMantendoPosicao()`, que **repõe exatamente as linhas que o utilizador
tem à frente** — recarregar só a primeira página faria desaparecer tudo o que já
tinha sido percorrido, e o ecrã saltaria para o topo a meio de uma leitura.

Efeito lateral positivo: os dados de apoio (roteiros, motivos de paragem,
técnicos) passaram para `_carregarAuxiliares()` e são lidos **uma vez**. Antes,
cada evento realtime relia as quatro tabelas.

---

## Ecrã 2 — Informações de Clientes

Mesmo molde. Sem realtime a competir pelo scroll, mas com KPIs.

### Os quatro KPIs deixaram de ser contados em Dart

| KPI | Antes | Agora |
|:---|:---|:---|
| Total de Clientes | `_clientes.length` | `count` no servidor |
| Acesso ao Portal | `.where((c) => c.ativo).length` | `count` com `ativo = true` |
| Clientes c/ Encomendas | `.where((c) => c.temEncomendas).length` | valores distintos de `encomendas.cliente_id` |
| Volume de Encomendas | `fold` sobre a lista | número de encomendas com cliente |

Os dois últimos precisam de contar valores distintos, que o PostgREST não sabe
fazer. Lê-se por isso apenas a coluna `encomendas.cliente_id` — uma coluna de
inteiros. Continua a ser a tabela toda, mas incomparavelmente mais leve do que a
junção completa que alimentava estes números antes. **Se a tabela crescer muito,
é aqui que faz sentido uma função de agregação na base de dados.**

### Filtro "Com Encomendas"

Traduzido para `encomendas!inner(...)` na projeção: é o que transforma a junção
num critério de seleção do próprio cliente, em vez de apenas o acompanhar.

### Mensagens de lista vazia

Existiam duas, distinguidas por comparar a lista completa com a filtrada. Com uma
só lista, a distinção passou a ser feita por *o que está pedido*
(`_semFiltrosAtivos`): carteira vazia vs. filtros sem resultados. O texto
apresentado é o mesmo nos dois casos.

---

## Ecrã 3 — Relatórios

Deixado para último de propósito, porque um relatório é por natureza uma
agregação e o molde não se aplica todo.

### Feito

- **Lista de avaliações paginada** com scroll infinito no painel da direita.
- **Avaliação média apurada no servidor** (`obterAvaliacaoMedia`), lendo só a
  coluna `nota`. Somá-la sobre a lista paginada daria a média das avaliações que
  por acaso estivessem no ecrã.

### ⚠️ Não feito, e porquê

**Os KPIs "Encomendas Concluídas" e "Taxa de Entrega no Prazo" continuam a
carregar duas tabelas inteiras** — todas as encomendas não canceladas
(`obterParaRelatorios`) e **todo** o `historico_producao`
(`obterHistoricoCompleto`).

Não é descuido. Estes números saem de `_obterDataConclusao`, que cruza cada
encomenda com o seu histórico e com a última fase do roteiro do produto. É uma
agregação sobre o conjunto todo: não existe forma de a exprimir em PostgREST, e
paginar as tabelas de origem daria **números errados**, não números lentos.

A resposta certa é uma função de agregação na base de dados (`RPC`), que devolva
os dois valores já calculados. Isso é uma migração ao schema e ficou por decidir
— o código atual mantém-se correto, apenas continua a ser o ponto pesado deste
ecrã. O mesmo se aplica à geração do PDF, que precisa das encomendas do período
escolhido e beneficiaria de filtrar por data já na query.

---

## Fora de âmbito

`gestao_utilizadores` (7 registos), `gestao_fluxos` e `postos_trabalho` (dezenas)
não foram paginados: seria complexidade sem retorno.

## Verificação

`flutter analyze lib`:

```
Antes:   67 issues found
Depois:  67 issues found
```

**Zero erros.** Os 67 avisos são exatamente os mesmos de antes desta alteração
(`withOpacity` e `DropdownButtonFormField.value` deprecados, `avoid_print` nos
serviços) — nenhum foi introduzido nem removido por este trabalho.

O analisador não valida as queries: elas só falham contra a base de dados real.

## Validação manual necessária

1. **Painel de Controlo** — para cada um dos cinco filtros, confirmar que a
   contagem de resultados bate certo com o que se via antes. É o ponto de risco:
   traduzir `EstadoOrdem` para SQL é reimplementar lógica de negócio noutra
   linguagem, e uma divergência não dá erro de compilação.
2. **Pesquisar um código de rastreio antigo** (que esteja além da primeira página)
   — tem de o encontrar. Idem por nome de cliente.
3. **Scroll até ao fim** do painel e da lista de clientes, e confirmar que
   "Carregar mais" traz linhas novas sem repetir as anteriores.
4. **Avançar fase / WIP hold / Line clearance** com a lista deslizada para baixo —
   confirmar que o ecrã não salta para o topo.
5. **KPIs dos clientes** — comparar os quatro números com os anteriores.
6. **Filtro "Com Encomendas"** — confirmar que não duplica clientes (é o efeito
   que o `!inner` teria se o PostgREST devolvesse uma linha por encomenda).

---

# Notas de Alterações — Realtime (`dashboard_admin`)

## O problema

Cada evento de realtime disparava um recarregamento completo do ecrã. No
dashboard principal são **quatro queries por evento**; no painel de controlo, a
lista inteira que o utilizador tivesse percorrida. O canal `escutarProducao`
escuta duas tabelas com `PostgresChangeEvent.all` e **descartava o payload**
(`callback: (_) => aoAlterar()`), pelo que não havia sequer maneira de saber
*o quê* tinha mudado.

Dez operadores a avançar fases geram dezenas de eventos por minuto. Cada um
custava um recarregamento — mesmo quando dizia respeito a uma ordem que nem
estava à frente do utilizador.

## A ideia

Duas alterações independentes que se reforçam:

1. **Agrupar** (debounce) os eventos que obrigam mesmo a recarregar.
2. **Aplicar o payload** diretamente ao que está em memória, quando ele chega
   para isso — o que elimina o recarregamento por completo.

O critério que decidiu o desenho: **o utilizador não pode notar atraso**.

## Peça nova — `lib/core/realtime.dart`

`RecarregadorDebounced`. Três comportamentos:

- **Aresta inicial.** O primeiro evento de uma rajada é aplicado *imediatamente*.
  Um debounce só com aresta final atrasaria todas as atualizações, incluindo a
  primeira — exatamente o atraso que se queria evitar — e com eventos contínuos
  poderia nunca disparar.
- **Janela de coalescência.** Os eventos seguintes que caiam dentro da janela
  fundem-se num único recarregamento no fim dela.
- **Teto de espera.** Uma rajada ininterrupta não pode adiar o ecrã
  indefinidamente.

Mais um quarto, tão importante como o debounce e que não é debounce nenhum:
**bloqueio de recarregamentos sobrepostos**. Se chegava um evento enquanto um
pedido estava no ar, partiam dois em paralelo — e a resposta mais antiga podia
chegar depois da mais recente e escrever dados velhos por cima dos novos. Agora
fica **um** recarregamento marcado para o fim do que está a decorrer.

### Os tempos, e porquê

| Ecrã | Janela | Teto | Razão |
|:---|:---|:---|:---|
| Painel de Controlo | 300 ms | 1,5 s | O mesmo valor de `esperaPesquisa`. Avançar uma fase gera 2–3 eventos em dezenas de ms (a ordem, e por vezes uma incidência); 300 ms junta-os num pedido só. Com disparo imediato, é invisível. |
| Carteira de Clientes e Planeamento | 500 ms | 2 s | Poucos eventos, mas cada recarregamento traz mais do que uma lista (a carteira traz também as quatro métricas). |
| Dashboard Principal | 1 s | 3 s | Quatro queries agregadas por recarregamento, e indicadores de leitura contemplativa, não de reação. 1 s é a diferença entre 40 e 4 pedidos numa rajada. |

## O payload passou a ser usado

`EncomendasRepository.escutarProducao` entrega agora o `PostgresChangePayload` a
quem escuta, em vez de o deitar fora.

**O limite, que moldou tudo o resto:** o payload traz **apenas as colunas em
bruto da tabela alterada**. Nunca traz os recursos embebidos — o nome do
cliente, o do produto, o da fase atual, as incidências. Tudo o que a projeção do
painel junta fica de fora.

### Painel de Controlo — o que cada evento passou a custar

| Evento | Antes | Agora |
|:---|:---|:---|
| Ordem que não está carregada | lista inteira | **nada** (sai sem tocar na rede) |
| DELETE | lista inteira | **nada** — remove pelo `id` |
| Ordem que deixa de casar com o filtro | lista inteira | **nada** — sai da lista |
| UPDATE de `em_suspenso`, `cancelada`, `prioridade`, `data_entrega`, … | lista inteira | **nada** — a linha é reconstruída em memória |
| UPDATE de `fase_atual_id` | lista inteira | **nada** — o nome e o posto da fase saem de `_fasesPorProduto`, já carregado |
| INSERT que pertence à vista | lista inteira | **uma linha** (`obterUmaParaPainel`) |
| Mudou o cliente ou o produto, ou a fase é desconhecida | lista inteira | **uma linha** |
| Evento em `incidencias` | lista inteira | lista inteira, com debounce |

Numa fábrica com milhares de ordens e 50 carregadas, a esmagadora maioria dos
eventos cai na primeira linha da tabela: nem chega a haver pedido.

### Como se decide sem ir ao servidor

- **O filtro.** A precedência `cancelada → em hold → concluída → em produção`
  depende de três colunas que vêm todas no payload. A regra **não é reescrita**:
  deriva-se o estado com `EstadoOrdem.derivar` — a mesma função que o repositório
  traduziu para SQL — e compara-se com `FiltroEstadoOrdem.estado`. Era este o
  risco apontado no comentário do próprio `estado_ordem.dart`, e é por isso que
  não se escreveu aqui um terceiro `switch`.
- **A pesquisa.** Cobre código de rastreio e nome de cliente; ambos existem no
  modelo já carregado.
- **A posição.** A lista está ordenada por `id` decrescente. Uma ordem com `id`
  menor do que a última carregada vive na parte que ainda não foi percorrida —
  aparecerá sozinha quando o scroll lá chegar, e é ignorada agora.
- **A reconstrução da linha.** Reutiliza-se o `EncomendaModel.fromJson`,
  fundindo o payload com os campos de junção da linha que já lá estava. Não
  existe um segundo caminho de parsing a manter em sincronia.

### Casos que continuam a exigir recarregamento

- **O dashboard principal, na íntegra.** Ocupação por fase, OEE, atrasadas,
  concluídas hoje — são agregados sobre o conjunto todo. Incrementá-los a partir
  de um evento isolado arriscaria deriva acumulada: números errados em vez de
  números lentos. Aqui a resposta é só o debounce.
- **Eventos em `incidencias`.** Vêm embebidos na projeção da ordem e alimentam
  os avisos de paragem e o line clearance; o payload é da tabela `incidencias`,
  não da ordem.
- **Qualquer falha** no caminho otimista cai no recarregador. O caminho seguro
  nunca deixou de existir.

## Ficheiros alterados

| Ficheiro | O quê |
|:---|:---|
| `core/realtime.dart` | **novo** — `RecarregadorDebounced` e as constantes de janela |
| `repositories/encomendas_repository.dart` | `escutarProducao` entrega o payload; `obterUmaParaPainel` (leitura de uma linha) |
| `painel_controlo_screen.dart` | tratamento de eventos por payload (insere / atualiza / remove localmente) |
| `dashboard_principal_screen.dart` | debounce de 1 s |
| `informacoes_clientes_screen.dart` | debounce de 500 ms sobre lista + métricas |
| `criar_encomenda_screen.dart` | debounce de 500 ms |

## Decisões concretas

- **`temMais` e as contagens** ficam ligeiramente aproximados depois de
  inserções e remoções locais. É aceitável: corrigem-se sozinhos no scroll
  seguinte ou na mudança de filtro. O alternativo — recarregar para acertar um
  contador — anularia a alteração toda.
- **As ações do próprio utilizador** (avançar fase, WIP hold, cancelar)
  continuam a chamar `_recarregarMantendoPosicao()` diretamente, sem debounce.
  São poucas, são deliberadas e devem responder de imediato.
- **`escutarCarteira` e `escutarPlaneamento` mantiveram a assinatura sem
  payload.** Esses ecrãs não têm como o aproveitar — a carteira mistura três
  tabelas em métricas agregadas — e mudá-la seria complexidade sem retorno.

## Verificação

`flutter analyze lib`:

```
Antes:   67 issues found
Depois:  67 issues found
```

**Zero erros.** Os 67 avisos são exatamente os mesmos de antes (`withOpacity` e
`DropdownButtonFormField.value` deprecados, `avoid_print` nos serviços) —
nenhum foi introduzido nem removido.

O analisador não testa concorrência: a lógica de rajada e de sobreposição só se
confirma com vários operadores em simultâneo.

## Validação manual necessária

1. **Dois separadores abertos no painel** — avançar uma fase num e confirmar que
   o outro reflete a mudança **de imediato**, sem a lista saltar para o topo.
2. **Rajada** — avançar várias ordens em rápida sucessão e confirmar que o ecrã
   converge para o estado correto (não fica uma linha desatualizada por a última
   atualização se ter perdido).
3. **Filtro "Em Produção" ativo** — concluir uma ordem noutro terminal: tem de
   **desaparecer** da lista. Com "Concluídas" ativo, tem de **aparecer**.
4. **Pesquisa ativa** — criar uma ordem que não corresponde ao termo: não pode
   entrar na lista.
5. **Ordem cancelada** — só pode aparecer no filtro "Canceladas".
6. **Nome da fase após avanço** — confirmar que a linha mostra a fase nova e não
   fica em branco (é o caso resolvido em memória por `_fasesPorProduto`).
7. **Produto novo**, criado depois do ecrã estar aberto — a ordem tem de mostrar
   o nome da fase à mesma (deve cair no caminho de leitura de uma linha).

---

# Notas de Alterações — Estado de erro na UI (`dashboard_admin`)

## O problema

Uma falha de carregamento não chegava ao utilizador de forma que ele a pudesse
usar. O tratamento era um de dois:

- um **SnackBar** que desaparece ao fim de 4 segundos;
- um **`debugPrint`**, que ninguém vê fora do modo de depuração.

Em qualquer dos casos, o que ficava no ecrã era **uma lista vazia** com a
mensagem de "não há dados" por baixo. E essas mensagens são afirmações sobre a
fábrica, não sobre a ligação:

| Ecrã | O que se lia depois de uma falha de rede |
|:---|:---|
| Painel de Controlo | "Não existem ordens de produção ativas correspondentes à pesquisa." |
| Postos de Trabalho | "Nenhum posto de trabalho encontrado." |
| Gestão de Utilizadores | "Nenhum utilizador encontrado." |
| Carteira de Clientes | "Nenhum cliente registado na base de dados." |
| Pedidos de Clientes | "Nenhum pedido de encomenda registado." |
| Fluxos Produtivos | "Nenhuma fase definida para este fluxo." |
| Dashboard Principal | todos os KPIs a **zero** |
| Relatórios | indicadores a **zero** e taxa de entrega a **0%** |

Nenhuma destas dizia a verdade, e **nenhuma tinha forma de tentar outra vez** a
não ser sair do ecrã e voltar a entrar. As duas últimas são as mais perigosas: um
zero parece um resultado. "Nenhuma fase definida para este fluxo" chega a ser um
convite a desenhar de raiz um roteiro que já existe.

## Peça nova — `lib/widgets/estado_erro.dart`

Primeiro ficheiro em `lib/widgets/` (a pasta não existia).

### `EstadoErro` — ocupa o lugar dos dados

Ícone, o que falhou em linguagem do utilizador, o motivo técnico em segundo
plano, e um botão **"Tentar novamente"**. Usa-se onde os dados deviam estar: o
corpo do ecrã, um painel, uma coluna.

### `EstadoErro.compacto` — barra fina

Para quando **já há dados no ecrã** e o que falhou foi um pedido posterior: a
atualização em tempo real, ou a página seguinte de uma lista. As linhas antigas
ficam — são a última leitura boa — mas deixam de se apresentar como atuais.

### `descreverErro(Object)`

Tira o prefixo `…Exception:` e corta aos 160 caracteres. O ruído do PostgREST não
diz nada a quem está a usar o ecrã, e uma linha de stack rebenta o espaço. O
painel de controlo já tinha o seu `_limparErro`, que foi mantido.

## O princípio que decidiu o desenho

**Vazio por falha e vazio por ausência de dados são estados diferentes e passam a
ter ecrãs diferentes.** Daí a distinção entre as duas formas do widget:

| Situação | O que se mostra |
|:---|:---|
| Falhou e **não há nada** carregado | `EstadoErro` no lugar dos dados |
| Falhou mas **há dados** de uma leitura anterior | `EstadoErro.compacto` por cima, dados mantidos |
| Correu bem e não há dados | a mensagem de lista vazia que já existia, **inalterada** |

Nunca se esconde o que já foi lido por causa de uma atualização falhada: num
painel de fábrica, dados de há um minuto valem mais do que um ecrã em branco —
desde que se saiba que são de há um minuto.

## Scroll infinito depois de uma falha

Nos três ecrãs paginados, `_erroPaginacao` é um campo **separado** do erro
principal: o que já está carregado continua válido, só o rodapé muda.

E o scroll **deixa de pedir sozinho** enquanto esse erro estiver ativo. Sem isso,
cada gesto relançaria o mesmo pedido a falhar, dezenas de vezes por segundo,
contra um servidor que já se sabe não estar a responder. A retoma passa a ser
deliberada, pelo botão de repetir. O campo é limpo em cada nova tentativa e em
cada recarregamento com sucesso.

## Ficheiros alterados

| Ficheiro | O que passou a distinguir |
|:---|:---|
| `widgets/estado_erro.dart` | **novo** |
| `painel_controlo_screen.dart` | lista, atualização e paginação (três estados) |
| `informacoes_clientes_screen.dart` | carteira, atualização e paginação |
| `relatorios_admin_screen.dart` | ecrã inteiro (todos os números vêm do mesmo carregamento) + paginação das avaliações |
| `dashboard_principal_screen.dart` | ecrã inteiro à primeira leitura; barra sobre os KPIs nas seguintes |
| `criar_encomenda_screen.dart` | ecrã inteiro à primeira leitura; barra nas seguintes |
| `gestao_utilizadores_screen.dart` | tabela e atualização |
| `postos_trabalho_screen.dart` | grelha de postos e atualização |
| `gestao_fluxos_screen.dart` | tipologias e fases, em separado |
| `pedidos_clientes_admin_screen.dart` | lista e atualização |

**A lógica de carregamento não mudou em ecrã nenhum.** As queries, a paginação, o
debounce de realtime e a ordem das chamadas são exatamente os mesmos. O que mudou
foi só o que se faz com a exceção depois de apanhada.

## Dois bugs corrigidos pelo caminho

Em `gestao_fluxos_screen.dart`, os blocos `catch` de `_carregarTipologias` e
`_carregarFases` **nunca punham `_isLoading…` a `false`**. Uma falha deixava o
indicador de progresso a rodar para o resto da sessão — e como o SnackBar já
tinha desaparecido, sem nada que explicasse porquê. Ambos os caminhos passam a
terminar o estado de carregamento.

## Decisões concretas

- **Dashboard Principal e Criar Encomenda** usam um `_carregouUmaVez` em vez de
  olhar para uma lista: um deles mostra números agregados (zero é um valor
  legítimo) e o outro é um formulário. Não há lista cuja vacuidade sirva de sinal.
- **Relatórios substitui o ecrã inteiro.** Aqui não há meio-termo: todos os
  números saem do mesmo carregamento, e mostrar parte deles seria apresentá-los
  como o resultado do período escolhido.
- **`_carregarAuxiliares` do painel de controlo mantém o SnackBar.** Não alimenta
  a lista — traz roteiros, motivos de paragem e técnicos para os diálogos de ação.
  Falhar aí não produz nenhum ecrã vazio enganador; o aviso passageiro chega.
- **`dashboard_admin_shell.dart` ficou de fora.** O único carregamento que faz é
  o nome e o email do administrador para a barra lateral, e já tem valores de
  recurso ("Administrador"). Não é uma lista e não pode ser confundido com
  ausência de dados.
- **Os SnackBars de escrita ficam todos.** Criar, atualizar, cancelar, avançar
  fase — são ações pontuais do utilizador, com resultado imediato e sem estado
  persistente a contradizer. O problema era exclusivamente de leitura.

## Verificação

`flutter analyze lib`:

```
Antes:   67 issues found   (29 em dashboard_admin)
Depois:  67 issues found   (29 em dashboard_admin)
```

**Zero erros.** Os 67 avisos são os mesmos de sempre (`withOpacity` e
`DropdownButtonFormField.value` deprecados, `avoid_print` nos serviços) — nenhum
introduzido nem removido.

## Validação manual necessária

O caminho a testar é o da falha, e o analisador não lá chega. A forma mais
simples é desligar a rede com o ecrã aberto.

1. **Entrar em cada ecrã sem rede** — tem de aparecer o estado de erro com botão,
   e nunca uma mensagem de "não há dados".
2. **Repetir com a rede de volta** — o botão tem de carregar os dados e o estado
   de erro desaparecer, sem sair do ecrã.
3. **Cortar a rede com o ecrã já carregado** e provocar um evento realtime — as
   linhas têm de **ficar**, com a barra fina por cima.
4. **Scroll até ao fim sem rede** — o rodapé mostra a falha, e continuar a
   arrastar **não** dispara mais pedidos.
5. **Lista genuinamente vazia** (pesquisa sem resultados, com rede) — tem de
   continuar a mostrar a mensagem de vazio de sempre, não o estado de erro.
6. **Fluxos Produtivos sem rede** — confirmar que o indicador de progresso *para*
   (era o bug), tanto na coluna das tipologias como no painel das fases.

---

# O que fica por fazer

Por ordem de retorno:

1. **RPC de agregação para os relatórios.** Continua a ser o ponto pesado que
   ficou por resolver na paginação: os KPIs "Encomendas Concluídas" e "Taxa de
   Entrega no Prazo" carregam duas tabelas inteiras porque a agregação não se
   exprime em PostgREST. Exige uma migração ao schema.
2. **Métricas da carteira de clientes.** Dois dos quatro KPIs leem a coluna
   `encomendas.cliente_id` da tabela toda para contar valores distintos. É leve
   hoje; deixa de o ser com volume. Mesma resposta: agregação na base de dados.
3. **Filtrar o PDF por data já na query**, em vez de trazer as encomendas todas
   e cortar em Dart.
4. **`escutarCarteira` a aproveitar o payload**, se o ecrã de clientes vier a
   sofrer com o volume de eventos. Hoje não sofre.
5. **Estender o `EstadoErro` aos outros módulos.** `portal_cliente` e
   `terminal_operador` continuam com o padrão antigo. O widget é agnóstico do
   módulo — está em `lib/widgets/`, não em `dashboard_admin` — e o
   `terminal_operador` é o caso com mais a ganhar: quem está no chão de fábrica
   não tem como saber que a fila de trabalho vazia é uma falha de rede.
6. **Avisos deprecados** (`withOpacity` → `withValues`,
   `DropdownButtonFormField.value` → `initialValue`) e os `avoid_print` nos
   serviços. São os 67 avisos que atravessam todo este trabalho sem nunca terem
   sido tocados — limpeza mecânica, sem risco, mas também sem urgência.
