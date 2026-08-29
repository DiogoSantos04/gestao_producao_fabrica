# 8.5 Funcionalidades por perfil implementadas na Parte II

## 8.5.1 Enquadramento

A Parte I entregou **protótipos de alta fidelidade**: ecrãs desenhados, navegação simulada e
dados fictícios. Definiram três perfis — administrador, operador e cliente — e a aparência das
suas interfaces, mas não continham lógica de negócio, persistência nem regras de estado.

A Parte II implementa esses ecrãs sobre uma base de dados real, e o que se segue não é apenas
«ligar os protótipos ao Supabase». Três coisas distintas aconteceram:

1. **Implementação** do que o protótipo previa (o fluxo de produção, o rastreio, a fila de
   trabalho);
2. **Crescimento** de funcionalidades que o protótipo apenas insinuava, ou que se revelaram
   necessárias quando os dados passaram a ser reais (postos de trabalho, motivos estruturados,
   registo de conformidade);
3. **Um perfil novo**, o técnico de manutenção, que não existia na Parte I.

Nem tudo veio dos protótipos: várias funcionalidades nasceram da correção de defeitos
encontrados na própria implementação — o portal B2B de pedidos, por exemplo, existia como
formulário de submissão sem que o cliente alguma vez visse o que tinha submetido.

| Perfil | Ecrãs (Parte II) | Estado face à Parte I |
| --- | --- | --- |
| Administrador | 8 ecrãs + 9 diálogos, `lib/screens/dashboard_admin/` | Implementado e muito ampliado |
| Operador | 4 ecrãs + popup, `lib/screens/terminal_operador/` | Implementado e ampliado |
| Cliente | 4 ecrãs, `lib/screens/portal_cliente/` | Implementado e ampliado |
| **Técnico de manutenção** | 4 ecrãs, `lib/screens/terminal_tecnico/` | **Perfil novo** |

---

## 8.5.2 Perfil Administrador

O dashboard é o módulo que mais cresceu. Além do painel de controlo e do lançamento de ordens
já previstos, a Parte II acrescentou quatro áreas funcionais.

### Painel de controlo com transições de estado reais

O protótipo mostrava uma lista de ordens com badges de estado. A implementação acrescentou as
operações que mudam esse estado, todas através das RPC transacionais descritas em 8.4:
avançar de fase, aplicar WIP Hold (`dialogo_wip_hold.dart`), aprovar Line Clearance
(`dialogo_line_clearance.dart`) e cancelar a ordem (`dialogo_cancelar_ordem.dart`).

Duas mudanças de fundo relativamente ao que os ecrãs faziam inicialmente:

- **O cancelamento deixou de apagar.** A versão inicial executava um `DELETE` físico, que
  destruía com a ordem o histórico e as incidências (bug (e)). Passou a cancelamento lógico com
  motivo obrigatório e data — a ordem cancelada continua a existir e a ser consultável.
- **O estado deixou de ser derivado por comparação de nomes de fase.** Passou a
  `EstadoOrdem.derivar`, com `FiltroEstadoOrdem` traduzido para condições SQL no repositório e
  filtragem feita no servidor, com paginação, em vez de sobre a lista carregada.

Acrescentou-se ainda o **realtime** (`escutarProducao`): o painel reage a alterações em
`encomendas` e `incidencias` sem que o administrador tenha de recarregar.

### Gestão de fluxos — roteiros configuráveis

`gestao_fluxos_screen.dart` permite definir, por tipo de produto, a sequência de fases do
roteiro: nome técnico, ordem, descrição, tempo estimado, posto de trabalho que a executa,
**nome público** e **checklist de pontos de controlo**.

É a funcionalidade que torna o sistema configurável em vez de fixo. Duas consequências
diretas:

- O `nome_publico` de cada fase existe porque o roteiro é editável pelo administrador. Um
  dicionário de tradução escrito em Dart deixaria de cobrir qualquer fase criada depois da
  compilação — o cliente veria terminologia interna de fábrica.
- A checklist deixou de ser um texto fixo por fase e passou a ser conteúdo gerido pelo
  administrador, o que é o pré-requisito do registo de conformidade descrito em 8.5.6.

### Relatórios e indicadores

`relatorios_admin_screen.dart` cruza dados que nenhum ecrã da Parte I produzia:

- **Desempenho por fase** — RPC `obter_desempenho_fases`, com filtros de período, cliente e
  tipo de produto. A agregação é feita no servidor.
- **Análise de Pareto das paragens** — `agregarPareto`, com dois critérios alternativos
  (número de ocorrências ou minutos totais parados). Uma paragem ainda aberta conta desde o
  início até ao instante presente, «porque é exatamente o tempo que está a custar».
- **Taxa de entrega no prazo** — `EncomendaModel.cumpriuPrazo`, comparada ao dia.
- **Ocupação por posto físico** — ver 8.5.5.

O Pareto só é possível por causa dos *reason codes* estruturados (8.5.5): a função ignora
explicitamente as incidências sem `reason_code_id`, «não há por onde as agrupar sem cair no
texto livre».

### Gestão de utilizadores e de clientes

`gestao_utilizadores_screen.dart` acrescentou aprovação de contas (`estado_conta`), atribuição
de perfil e afetação a posto de trabalho. `informacoes_clientes_screen.dart` acrescentou a
carteira de clientes com KPIs apurados no servidor (`MetricasClientes`), filtros
(`FiltroCliente`) e painel de detalhe com encomendas e pedidos do cliente.

Foi também aqui que se removeu a coluna `utilizadores.password` (bug (c)): as credenciais
passaram a viver exclusivamente no Supabase Auth.

---

## 8.5.3 Perfil Operador

O terminal do operador foi implementado como o protótipo previa — fila de trabalho, detalhe da
tarefa, conclusão de fase — e ganhou depois quatro coisas que o protótipo não tinha.

**A fila mostra apenas ordens trabalháveis.** A versão inicial filtrava só por `fase_atual_id`
e mostrava ao operador ordens canceladas e em WIP Hold, que ele podia iniciar (bug (E)).
Passou a usar a precedência de `EstadoOrdem`.

**A conclusão de fase passou pela RPC transacional.** O ecrã fazia `insert` no histórico
seguido de `update` na encomenda, e reimplementava em Dart a regra «próxima fase = índice + 1»
(bug (A)). Passou a `avancarFase()`, e a mensagem de sucesso usa o retorno da RPC para
distinguir «ordem finalizada» de «avançou para \<fase\>».

**O bloqueio de tarefa passou a estruturado.** `bloquear_tarefa_screen.dart` deixou de
concatenar texto livre e passou a escolher um *reason code* do catálogo (8.5.5).

**Relatórios próprios do operador.** `relatorios_operador_screen.dart` e
`historico_operador_screen.dart` dão-lhe visibilidade do seu próprio trabalho — fases
concluídas, tempos, incidências reportadas — que o protótipo não contemplava.

Acrescentou-se ainda o **cronómetro de fase**, alimentado por `encomendas.data_inicio_fase`
escrito pela RPC na mesma transação da transição, com `segundos_parados_fase` a descontar o
tempo em WIP Hold para que o tempo de avaria não conte como tempo de produção.

---

## 8.5.4 Portal B2B do cliente — `pedidos_encomenda`

Esta é a funcionalidade que mais se afasta do protótipo, porque o protótipo mostrava apenas o
lado do rastreio.

### O que existe

`solicitar_encomenda_screen.dart` permite ao cliente submeter um pedido de encomenda: tipo de
produto, quantidade e observações, gravado em `pedidos_encomenda` com estado `Pendente`. Do
lado do administrador, `pedidos_clientes_admin_screen.dart` analisa o pedido e aprova-o pela
RPC `aprovar_pedido_encomenda`, que numa só transação cria a ordem de fabrico, atualiza o
estado do pedido e gera a notificação para o cliente. O ciclo completo é
**Pendente → Aprovado → Em Produção**, ou **Rejeitado**, modelado por `EstadoPedido`.

### O que cresceu durante a implementação

**O cliente passou a ver os seus pedidos.** Na primeira versão, `solicitar_encomenda` inseria
na tabela e nunca mais mostrava nada: o cliente não sabia se o pedido ficara pendente, fora
aprovado ou rejeitado — e, por não ter forma de saber que já tinha submetido, voltava a
submeter. Acrescentou-se a secção **«Os Meus Pedidos»**, com artigo, quantidade, data,
observações e badge de estado, relida imediatamente após cada submissão.

**A identidade do cliente passou a ser uma chave estrangeira.** O portal resolvia o cliente
por **comparação de nomes em texto** entre `utilizadores.nome_utilizador` e
`clientes.nome_cliente` (bug (A) do portal). Consequências reais: dois clientes com o mesmo
nome podiam ver o histórico um do outro; renomear um cliente no painel de administração
desligava-lhe o portal. Passou a resolver-se por `clientes.utilizador_id`, num único método
(`obterClienteAutenticado()`), com índice único parcial a impedir que uma conta represente dois
clientes.

**O rastreio público passou a anónimo.** Pesquisava por `codigo_rastreio` sem filtro e devolvia
o nome do cliente destinatário, num ecrã acessível sem autenticação e com códigos de formato
enumerável (`TRC-XXXXXX`). Decidiu-se manter o rastreio público — é requisito de negócio — mas
através da função `SECURITY DEFINER` `rastrear_encomenda`, que devolve o produto, a data e o
roteiro e **nunca** devolve cliente, observações ou motivo de cancelamento. O modelo
`RastreioEncomenda` não tem sequer um campo onde guardar o cliente, o que fecha a porta a uma
regressão futura.

**O estado mostrado ao cliente passou a ser o real.** O portal não pedia `cancelada` nem
`em_suspenso` e derivava o estado por comparação de strings sobre o nome da fase (bug (B)) —
uma encomenda cancelada aparecia como «EM PRODUÇÃO», e uma fase chamada «Concluir montagem»
fazia o portal oferecer o **Certificado de Conformidade** de um produto ainda na linha. O
certificado passou a exigir `EstadoOrdem.concluida`.

**Confirmação de receção pelo cliente.** `painel_por_confirmar.dart` mostra à entrada do portal
as entregas por confirmar. Existia apenas como pedido por email, e um email que não chegasse
— remetente por verificar, spam, ninguém o ler — deixava o cliente sem saber que lhe pediam
alguma coisa. O painel não substitui o email; é o caminho que não depende de nada externo.
`data_confirmacao_rececao` fica deliberadamente fora de `EstadoOrdem`: a receção é logística
posterior ao fabrico.

**Avaliações, paginação e realtime.** Acrescentou-se a avaliação de encomendas concluídas, com
restrição única `(encomenda_id, cliente_id)` no servidor (dois toques rápidos davam duas
avaliações), paginação do histórico por `PaginaResultado`, e realtime sobre `encomendas` e
`pedidos_encomenda` — a promessa de «tempo real» estava no texto do ecrã antes de ser verdade.

---

## 8.5.5 Gestão de postos de trabalho e *reason codes* estruturados

### Postos de trabalho

`postos_trabalho_screen.dart` e `PostosRepository` introduzem o posto como **recurso físico
de primeira classe**: nome, estado (`Livre` / `Em Produção` / `Parado`) e operador atribuído.

Três problemas concretos resolvidos por esta introdução:

**1. Os estados escritos à mão não coincidiam com a base de dados.** O ecrã usava valores
diferentes dos aceites pelo `CHECK` da coluna, pelo que **todos os updates falhavam em
silêncio** (bug (a)). A classe `EstadoPosto` fixa as três constantes num só sítio.

**2. O estado do posto era inferido em vez de lido.** O dashboard deduzia a disponibilidade a
partir das incidências abertas, o que ignorava postos parados sem incidência registada e
contava fases em vez de postos físicos. A coluna `estado` passou a ser a fonte de verdade.

**3. O gráfico de ocupação agrupava pelo nome da fase.** «Corte» do produto A e «Corte» do
produto B caíam na mesma barra, sem que exista um recurso único por trás dela. `distribuirOrdens`
agrupa por posto — o recurso finito da fábrica — e mantém explicitamente um balde
*«Sem posto»* para as ordens cuja fase não aponta para posto nenhum, em vez de as somar a um
posto qualquer. Postos vazios aparecem a zero, porque um posto vazio é informação.

A ligação `fases_padrao.posto_trabalho_id` é o que sustenta tudo isto; a coluna de texto
`posto_trabalho` ficou como legado sincronizado por *trigger*. A RPC `aplicar_wip_hold` deriva
o posto da fase atual, o que corrigiu de passagem o `posto_trabalho_id` das incidências, que
antes ficava sempre nulo.

### *Reason codes* estruturados

O terminal do operador tinha **cinco strings escritas em Dart**, concatenadas no campo de texto
livre da incidência no formato `'[Motivo] observações'` (bug (D)).

Duas consequências: o catálogo de motivos só se alterava recompilando a aplicação, e **uma
análise de Pareto das paragens era impossível** — não há como agrupar texto livre.

A tabela `reason_codes` (categoria, descrição, tempo estimado de paragem) passou a ser o
catálogo, com `ReasonCodeModel` do lado da aplicação. A incidência guarda `reason_code_id`, e
não texto. Detalhes de implementação que valem nota:

- `obterReasonCodes()` **deduplica por `id`** no repositório e não em cada ecrã: o
  `DropdownButtonFormField` lança em runtime se receber dois itens com o mesmo valor, e tanto
  o painel do administrador como o terminal do operador alimentam um a partir desta lista.
- `IncidenciaModel.rotulo` percorre `motivo → descricaoReasonCode → categoriaReasonCode`, para
  que as incidências antigas — gravadas quando só existia texto livre — continuem a aparecer
  preenchidas ao lado das novas.

O resultado é que a mesma paragem passou a ser simultaneamente legível por uma pessoa e
contável por um relatório.

---

## 8.5.6 Registo de conformidade Poka-Yoke — `checklist_execucoes`

A checklist obrigatória de uma fase era, até à Parte II, **um *gate* de interface**: o operador
marcava os pontos, o diálogo devolvia um `bool`, a fase avançava e **nada ficava gravado**.

Um mecanismo à prova de erro sem registo não é rastreável. Ninguém sabia quem validou que
ponto, a que horas, em que unidade produzida — e, numa reclamação de cliente, não havia forma
de demonstrar que a verificação tinha sido feita.

### Como ficou

O ciclo tem quatro peças:

1. **Definição** — o administrador edita a checklist da fase em `gestao_fluxos_screen.dart`.
   A coluna é `jsonb` e chega em três formatos diferentes conforme quem a escreveu, que
   `FaseModel._checklist` normaliza (sem isso, o operador via `{item: Verificar solda}`).
2. **Validação** — no terminal, cada ponto marcado produz um `PontoValidado` com **o instante
   em que a caixa foi marcada**, e não o da conclusão da fase: a diferença entre os dois é o
   que distingue uma verificação feita ponto a ponto de uma série de cliques no fim.
3. **Gravação** — a RPC `avancar_fase_encomenda` escreve os pontos em `checklist_execucoes`
   na **mesma transação** que grava o histórico e avança a ordem. Ou fica prova de
   conformidade, ou não há avanço. Numa segunda chamada, cada quebra de rede produziria uma
   fase fechada sem registo — precisamente o caso em que interessa saber o que foi verificado.
4. **Leitura** — `RegistoConformidade` devolve o registo na rastreabilidade da ordem
   (`dialogo_historico_ordem.dart`), com o nome do operador que validou.

### Duas decisões de desenho

**O texto do ponto é copiado, não referenciado.** `checklist_execucoes.item` guarda o texto
*tal como estava* no momento da validação. O administrador pode editar a checklist da fase
depois da produção, e o registo tem de continuar a dizer o que foi efetivamente verificado
nesse dia.

**O desvio é gravado, não escondido.** Uma fase com checklist chamada sem checklist é recusada
pelo servidor — exceto para o perfil Administrador, que pode fazer um avanço administrativo.
Nesse caso o registo fica com `conforme = false`, marcando explicitamente a não conformidade,
em vez de simplesmente não existir. A ausência de registo é ambígua; um registo de desvio não é.

---

## 8.5.7 Perfil novo — Técnico de manutenção

Não existia na Parte I. Foi acrescentado porque o ciclo da incidência tinha um troço sem dono:
entre o operador que para a linha e a qualidade que valida o *line clearance*, alguém tem de
reparar — e esse alguém não tinha interface nem registo.

O perfil é autónomo em quatro dimensões:

1. **Enum e encaminhamento próprios** — `PerfilUtilizador.tecnico`, com `case` próprio no
   login que leva a `TecnicoShellScreen`. Um técnico nunca vê a interface do operador.
2. **Ecrãs próprios** — fila de manutenção, histórico de intervenções, diálogo de conclusão.
3. **RPC próprias** — `aceitar_incidencia` e `concluir_intervencao_tecnica` (ver 8.4).
4. **Referência própria no modelo de dados** — `incidencias.tecnico_id`, distinta de
   `operador_id`. A atribuição filtra por perfil de manutenção; antes, o *dropdown* devolvia a
   tabela inteira e permitia atribuir uma intervenção a um cliente.

O contributo analítico deste perfil é a separação entre **tempo de espera** e **tempo de
reparação**: `duracaoIntervencao` conta a partir do momento em que o técnico assumiu a
incidência, e `tempoEspera` cobre o intervalo anterior. Somados, escondiam qual dos dois está
a custar tempo à fábrica.

---

## 8.5.8 Síntese

| Funcionalidade | Parte I (protótipo) | Parte II (implementação) |
| --- | --- | --- |
| Estado da ordem | Badge desenhado | `EstadoOrdem` derivado de 3 colunas, definição única |
| Avanço de fase | Ecrã de conclusão | RPC transacional com histórico + checklist |
| Cancelamento | Botão | Cancelamento lógico com motivo, preserva rastreabilidade |
| Paragem de linha | Campo de texto | *Reason codes* estruturados + ciclo de manutenção |
| Postos de trabalho | Não existia | Recurso físico com estado, operador e ocupação |
| Checklist | *Gate* visual sem registo | `checklist_execucoes` gravado na transação do avanço |
| Pedidos B2B | Formulário | Ciclo Pendente→Aprovado→Em Produção + visibilidade ao cliente |
| Rastreio público | Ecrã de consulta | Função `SECURITY DEFINER` anónima |
| Confirmação de receção | Não existia | Painel no portal + `data_confirmacao_rececao` |
| Relatórios | Gráficos ilustrativos | Pareto, desempenho por fase, taxa de prazo, ocupação |
| Técnico de manutenção | Não existia | Perfil completo com ecrãs, RPC e métricas próprias |

O padrão que atravessa a tabela é o mesmo: o protótipo definia **o que se vê**, e a
implementação teve de decidir **o que fica registado**. Quase todo o crescimento da Parte II
está nessa diferença — motivos que se conseguem contar, verificações que deixam prova, ordens
canceladas que não desaparecem, e paragens com um responsável identificado.
