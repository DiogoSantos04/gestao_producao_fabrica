# 8.1 Visão geral da arquitetura implementada

## 8.1.1 Modelo arquitetural adotado

A aplicação segue um modelo **cliente-servidor de duas camadas**, assente no paradigma
*Backend-as-a-Service* (BaaS). Não existe servidor aplicacional desenvolvido de raiz: o
Flutter constitui a totalidade da camada de apresentação e de orquestração de interface,
enquanto o Supabase assume o papel de camada de dados e de serviços de retaguarda
(autenticação, persistência, notificação em tempo real, armazenamento de ficheiros e
execução de código no servidor).

Um único código-fonte Dart/Flutter (`lib/`) é compilado para **Web** (dashboard de
administração e portal do cliente, tipicamente usados em posto fixo) e para **Mobile**
Android/iOS (terminais de operador e de técnico, usados no chão de fábrica). A partilha de
código abrange modelos, repositórios, regras de sessão e widgets; apenas o comportamento
responsivo difere, controlado centralmente em `lib/core/breakpoints.dart`.

A comunicação entre as duas camadas faz-se exclusivamente através do SDK oficial
`supabase_flutter` (versão ^2.16.0), inicializado uma única vez no arranque da aplicação,
em `SupabaseConfig.init()` (`lib/core/supabase_config.dart`), com o URL do projeto e a
chave pública (*anon key*, designada `publishableKey` nas versões recentes do SDK). Esta
inicialização é aguardada antes do primeiro *frame*; se falhar — por exemplo, por
indisponibilidade de rede no arranque — a aplicação apresenta um ecrã de erro explicativo
em vez de terminar com ecrã preto (`lib/main.dart`).

## 8.1.2 Organização interna do cliente Flutter

O cliente está organizado em quatro camadas com responsabilidades separadas:

| Camada | Localização | Responsabilidade |
|---|---|---|
| Apresentação | `lib/screens/`, `lib/widgets/` | Ecrãs por perfil de utilizador e componentes reutilizáveis |
| Acesso a dados | `lib/repositories/` | Todas as chamadas ao Supabase; tradução de erros |
| Domínio | `lib/models/` | Mapeamento entre JSON e objetos tipados |
| Infraestrutura | `lib/core/`, `lib/services/` | Configuração, sessão, *realtime*, paginação, temas, geração de PDF |

A camada de apresentação está segmentada pelos quatro perfis do sistema, correspondentes
aos quatro papéis definidos na tabela `utilizadores`: `dashboard_admin`,
`terminal_operador`, `terminal_tecnico` e `portal_cliente`.

O elemento estruturante desta organização é o **padrão Repository**. Existem dez
repositórios (`clientes`, `encomendas`, `fluxos`, `operador`, `portal_cliente`, `postos`,
`relatorios`, `tecnico`, `utilizadores`), todos derivados de `BaseRepository`
(`lib/repositories/base_repository.dart`). Nenhum ecrã acede diretamente a
`Supabase.instance.client`. Esta restrição foi introduzida deliberadamente: antes da sua
existência, cada ecrã do dashboard repetia a mesma query com variações, o que permitiu que
a mesma entidade fosse lida de formas divergentes em ecrãs diferentes.

`BaseRepository` fornece dois mecanismos transversais:

- **`guarda(contexto, operação)`** — envolve qualquer operação e converte
  `PostgrestException`, `StorageException` e `AuthException` numa exceção única de domínio,
  `RepositoryException`, com mensagem já redigida em linguagem de negócio. Quando a
  mensagem vem do servidor já legível (caso das funções SQL, ver 8.1.3), é preservada tal e
  qual, para poder ser mostrada diretamente ao utilizador.
- **`comoLista(resposta)`** — normaliza a resposta do driver para `List<Map<String, dynamic>>`.

## 8.1.3 Serviços Supabase utilizados

### a) Auth (GoTrue) — autenticação e gestão de sessão

Responsável pelo registo (`signUp`) e pelo início de sessão (`signInWithPassword`),
encapsulados em `AuthService` (`lib/services/auth_service.dart`). O SDK guarda o *token*
JWT emitido e anexa-o automaticamente a todos os pedidos subsequentes, o que permite que a
identidade do utilizador seja conhecida no servidor e usada pelas políticas de autorização.

`AuthService` é implementado como *singleton*. A razão é concreta: com instâncias
independentes por ecrã, o perfil carregado no login ficava numa instância que nenhum outro
ecrã via, e o utilizador atual aparecia sempre nulo fora do ecrã de login.

Os dados de perfil que não pertencem ao domínio da autenticação — nome, papel e
`estado_conta` — residem na tabela `utilizadores`, associada ao utilizador de Auth. No
login, a aplicação valida o `estado_conta`: contas pendentes de aprovação ou inativadas
pelo administrador são recusadas e a sessão é imediatamente encerrada.

Como essa validação só ocorre no login e no arranque, foi acrescentado o **`VigilanteSessao`**
(`lib/core/sessao.dart`), que subscreve `auth.onAuthStateChange` durante todo o ciclo de
vida da aplicação e encaminha para o ecrã de login quando a sessão termina sem ser a pedido
do utilizador (expiração do *token*, ou desativação da conta a meio do turno). Antes desta
subscrição, a aplicação continuava a mostrar dados em cache e a falhar em silêncio nas
queries seguintes, sem que o utilizador percebesse que precisava de voltar a autenticar-se.

### b) Postgres via PostgREST — operações de leitura e escrita simples

O acesso corrente aos dados faz-se por HTTP/REST, através da API PostgREST que o Supabase
expõe automaticamente sobre o esquema da base de dados. No SDK traduz-se em
`client.from('tabela').select(...)`, com filtros (`.eq`), ordenação (`.order`) e paginação
por intervalo (`.range`), bem como `insert` e `update`.

A autorização não é feita no cliente: cada pedido transporta o JWT do utilizador e é
filtrado por **políticas de Row Level Security (RLS)** definidas na base de dados. Um
cliente só consegue ler as suas próprias encomendas porque a política o impõe no servidor,
e não porque o ecrã omite as restantes. Esta opção é relevante numa aplicação Web, em que o
código do cliente é inspecionável.

### c) Postgres via RPC — transações de negócio

Operações que não são um simples CRUD são implementadas como **funções SQL invocadas por
RPC** (`client.rpc('nome', params: {...})`). São os pontos em que uma única ação do
utilizador altera várias tabelas e tem de o fazer de forma atómica, validando regras de
negócio.

Funções invocadas pela aplicação:

| Função | Repositório | Finalidade |
|---|---|---|
| `aprovar_pedido_encomenda` | `clientes_repository.dart:177` | Converte um pedido do cliente em encomenda e ordem de fabrico |
| `aplicar_wip_hold` | `encomendas_repository.dart:954` | Retém uma ordem em curso (*work-in-progress hold*) |
| `aprovar_line_clearance` | `encomendas_repository.dart:965` | Valida a limpeza de linha antes de novo lote |
| `cancelar_ordem` | `encomendas_repository.dart:974` | Cancela uma ordem de fabrico |
| `obter_desempenho_fases` | `encomendas_repository.dart:703` | Agregação de desempenho por fase produtiva |
| `concluir_intervencao_tecnica` | `tecnico_repository.dart:108` | Fecha uma intervenção de manutenção |
| `obter_email_suporte` | `operador_repository.dart:747`, `portal_cliente_repository.dart:449` | Endereço de suporte configurado |

A justificação para esta abordagem é dupla. Primeiro, **atomicidade**: o avanço de uma
ordem escreve na ordem, no histórico e, em certos casos, em incidências; executado a partir
do cliente seriam vários pedidos independentes, sem garantia de que todos se concretizassem.
Segundo, **unicidade da regra**: a mesma regra teria de ser reimplementada no dashboard, no
terminal do operador e no portal do cliente, com risco de divergência.

Estas funções sinalizam violações de regra com `RAISE EXCEPTION`, usando texto de negócio
já redigido em português. O `BaseRepository` reconhece esse caso e propaga a mensagem sem a
substituir, pelo que a mensagem que o operador lê no terminal é a que a base de dados
produziu.

### d) Realtime — sincronização entre postos

Os ecrãs que precisam de refletir alterações produzidas noutro posto subscrevem canais
Realtime sobre WebSocket, com `client.channel(nome).onPostgresChanges(...)`. Cada canal
declara as tabelas relevantes para o ecrã — por exemplo, o ecrã de carteira comercial
escuta `clientes`, `encomendas` e `pedidos_encomenda`
(`clientes_repository.dart:203`), e o planeamento escuta `pedidos_encomenda`, produtos e
últimas ordens. Existem subscrições análogas em `encomendas_repository`, `postos_repository`
e `portal_cliente_repository`.

O consumo direto dos eventos revelou-se ineficiente: uma única ação — avançar uma fase —
gera dois ou três eventos em dezenas de milissegundos, e cada um provocaria um
recarregamento completo do ecrã. Foi por isso implementado o **`RecarregadorDebounced`**
(`lib/core/realtime.dart`), com três características:

1. **Aresta inicial** — o primeiro evento de uma rajada é aplicado imediatamente; um
   *debounce* apenas com aresta final atrasaria também a primeira atualização, que é
   precisamente a que se pretende rápida.
2. **Coalescência com teto** — os eventos seguintes dentro da janela são fundidos num único
   recarregamento; um teto de espera impede que uma rajada contínua adie o ecrã
   indefinidamente. As janelas são calibradas por tipo de ecrã: 300 ms/1,5 s para listas,
   500 ms/2 s para ecrãs de carteira, 1 s/3 s para ecrãs agregados (o dashboard principal
   executa quatro queries por recarregamento, e a diferença é entre 40 e 4 pedidos numa
   rajada).
3. **Não sobreposição** — se chegar um evento enquanto um pedido está em curso, fica
   marcado um — e apenas um — recarregamento para o fim. Sem esta salvaguarda, duas
   respostas podiam chegar por ordem trocada e a mais antiga sobrepor-se aos dados mais
   recentes.

O comportamento temporal do `RecarregadorDebounced` é verificável em testes através de um
relógio virtual (pacotes `clock` e `fake_async`).

### e) Storage — relatórios em PDF

Os relatórios de turno são gerados no próprio cliente (pacotes `pdf` e `printing`, em
`lib/services/pdf_service.dart` e `relatorio_turno.dart`) e enviados para um *bucket* de
Storage com `uploadBinary`, obtendo-se depois o URL público
(`relatorios_repository.dart:57`). O URL é registado na tabela `historico_relatorios`, que
funciona como registo de auditoria imutável das emissões — permitindo, mais tarde, saber
que relatório foi emitido, quando e por quem, e voltar a obtê-lo.

### f) Edge Functions — trabalho assíncrono fora da base de dados

Ver secção 8.1.5.

## 8.1.4 Fluxo típico de uma operação

Aprovação de um pedido de encomenda, do clique à propagação:

1. O ecrã de planeamento invoca o método correspondente do `ClientesRepository`.
2. O repositório executa `rpc('aprovar_pedido_encomenda')` com os parâmetros do pedido.
3. A função SQL valida as regras de negócio e escreve nas tabelas envolvidas, numa única
   transação; se alguma regra falhar, lança `RAISE EXCEPTION` com mensagem em português.
4. Ainda dentro dessa transação, um *trigger* insere a notificação por email na tabela
   `fila_emails` (apenas um `INSERT` local — ver 8.1.5).
5. O Realtime propaga os eventos de alteração a todos os clientes subscritos.
6. Em cada cliente, o `RecarregadorDebounced` funde os eventos da rajada e recarrega o ecrã
   uma só vez.
7. Em caso de erro, a mensagem de negócio sobe intacta pelo `guarda()` do
   `BaseRepository` e é apresentada ao utilizador.

## 8.1.5 A Edge Function `enviar-emails`

**Ficheiro:** `supabase/functions/enviar-emails/index.ts`
**Runtime:** Deno, executado na infraestrutura *edge* do Supabase, fora do processo Postgres.

### Função

A Edge Function é o **consumidor da fila de emails** materializada na tabela `fila_emails`.
Em cada invocação:

1. Lê até `LOTE = 20` mensagens com `estado = 'pendente'`, ordenadas por `created_at`
   ascendente (disciplina FIFO).
2. Para cada mensagem, faz `POST` para `https://api.resend.com/emails` (fornecedor Resend),
   com remetente (`EMAIL_REMETENTE`), destinatário, assunto e corpo em texto.
3. Em caso de sucesso, marca a linha como `enviado`, regista `enviado_em` e limpa
   `ultimo_erro`.
4. Em caso de falha — resposta HTTP não-OK ou exceção de rede — incrementa `tentativas` e
   grava `ultimo_erro` com o texto devolvido pelo fornecedor, truncado a 500 caracteres. A
   mensagem permanece `pendente` até atingir `MAX_TENTATIVAS = 3`, passando então a
   `falhado`.
5. Devolve apenas contagens (`processados`, `enviados`, `falhados`), nunca os corpos das
   mensagens, uma vez que a resposta pode ficar persistida em registos de execução.

### Quando é invocada

Periodicamente, por **pg_cron** (invocação ao minuto). **Não é invocada pela aplicação
Flutter**. O produtor da fila é o *trigger* de base de dados que, dentro da transação que
avança ou cancela uma ordem, executa um simples `INSERT` em `fila_emails`.

### Justificação da separação (padrão *outbox*)

Esta é a decisão de desenho central desta componente. Se o envio do email fosse executado
dentro do *trigger*, uma indisponibilidade do fornecedor de email — que é um serviço
externo, sujeito a latência e falha — prolongaria ou faria abortar a transação, bloqueando
o operador no chão de fábrica numa operação que nada tem a ver com email. Com a separação
entre escrita transacional (`INSERT` local, rápido e fiável) e entrega externa (assíncrona,
com retentativas), **uma falha do fornecedor custa um atraso na notificação, e não uma
paragem de produção**.

### Segurança

A função autentica-se com `SUPABASE_SERVICE_ROLE_KEY`, porque não existe sessão de
utilizador no contexto de uma execução agendada e porque `fila_emails` está fechada por RLS
a todos os utilizadores exceto ao administrador. Tanto esta chave como `RESEND_API_KEY` e
`EMAIL_REMETENTE` residem exclusivamente nos *secrets* da Edge Function, nunca no cliente:
a aplicação Flutter conhece apenas a chave pública (*anon key*), que por si só não dá acesso
a nada que a RLS não permita.

### Limites definidos e sua fundamentação

- **`LOTE = 20`** — garante que a função termina dentro do tempo máximo de execução mesmo
  quando a fila acumulou; o excedente fica para a invocação seguinte, um minuto depois.
- **`MAX_TENTATIVAS = 3`** — sem um teto, um endereço permanentemente inválido seria
  retentado indefinidamente e ocuparia o início da fila, atrasando as mensagens válidas
  atrás de si.

## 8.1.6 Síntese das decisões de arquitetura

| Decisão | Alternativa descartada | Fundamento |
|---|---|---|
| BaaS (Supabase) em vez de backend próprio | API REST desenvolvida de raiz | Auth, RLS, Realtime e Storage prontos; esforço concentrado no domínio industrial |
| Padrão Repository | Queries nos ecrãs | Impede leituras divergentes da mesma entidade; centraliza a tradução de erros |
| RLS no servidor | Filtragem no cliente | O código do cliente Web é inspecionável; a autorização tem de ser inviolável |
| RPC para transações de negócio | Sequência de chamadas REST | Atomicidade e regra única partilhada pelos quatro perfis |
| *Debounce* dos eventos Realtime | Recarregar por evento | Uma ação gera 2–3 eventos; reduz de dezenas para um único recarregamento |
| Fila + Edge Function para email | Envio dentro do *trigger* | Falha de serviço externo não pode bloquear a produção |
