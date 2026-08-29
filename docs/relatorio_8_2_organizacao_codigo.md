# 8.2 Organização do código-fonte

## 8.2.1 Critério de organização

O código da aplicação reside integralmente em `lib/`, organizado **por
responsabilidade técnica** (camada) e não por funcionalidade. A raiz contém apenas
`main.dart` — ponto de entrada, configuração global de erros e arranque do Supabase — e seis
diretórios, cada um correspondendo a uma camada com uma regra de dependência clara: as
camadas superiores conhecem as inferiores, nunca o inverso.

```
lib/
├── main.dart          Ponto de entrada; inicialização e tratamento global de erros
├── core/              Infraestrutura transversal (não conhece ecrãs nem domínio)
├── models/            Entidades de domínio e mapeamento JSON
├── repositories/      Acesso a dados (única camada que fala com o Supabase)
├── services/          Serviços aplicacionais (sessão, geração de documentos)
├── screens/           Ecrãs, segmentados por perfil de utilizador
└── widgets/           Componentes de interface partilhados por vários perfis
```

A direção das dependências é: `screens` → `services`/`repositories` → `models` → `core`.
Nenhum repositório importa um ecrã e nenhum modelo importa um repositório, o que permite
testar as camadas inferiores sem construir interface.

## 8.2.2 Conteúdo e justificação de cada diretório

### `main.dart`

Faz três coisas antes de mostrar o primeiro ecrã: substitui o *ecrã vermelho* de erro do
Flutter por um ecrã legível (uma *stack trace* não pode ser o que um operador vê no chão de
fábrica), instala um manipulador global de erros não tratados, e aguarda
`SupabaseConfig.init()` dentro de um `try/catch` — sem este, uma falha de rede no arranque
deixava a aplicação a terminar com ecrã preto, sem explicação. Declara ainda duas chaves
globais (`chaveNavegador`, `chaveMensagens`) necessárias para ações que não partem de um
ecrã concreto, nomeadamente o encaminhamento forçado para o login quando a sessão se perde.

### `core/` — infraestrutura transversal

Contém o que é usado por várias camadas e não pertence a nenhum domínio de negócio. É a
camada mais baixa e não importa nada do projeto acima dela.

| Ficheiro | Responsabilidade |
|---|---|
| `supabase_config.dart` | URL, chave pública e inicialização única do SDK; atalho `client` |
| `sessao.dart` | `VigilanteSessao` — subscreve `onAuthStateChange` e reencaminha para o login quando a sessão termina involuntariamente |
| `sessao_local.dart` | Estado local da sessão (ex.: distinguir logout intencional de sessão perdida) |
| `realtime.dart` | `RecarregadorDebounced` e as janelas de coalescência de eventos Realtime |
| `paginacao.dart` | Tamanho de página e tempo de espera da pesquisa, partilhados pelas listas |
| `ecra_recarregavel.dart` | Contrato comum aos ecrãs que se recarregam por evento |
| `breakpoints.dart` | Pontos de corte do comportamento responsivo (Web vs. terminal móvel) |
| `temas_cores.dart` | Tema visual e paleta |
| `formatos.dart`, `iniciais.dart`, `mensagens.dart` | Formatação de datas/números, cálculo de iniciais para avatar, textos de mensagens |

A existência deste diretório resolve duplicação real: o cálculo das iniciais do avatar, por
exemplo, estava replicado em dois ecrãs e produzia resultados diferentes para o mesmo nome.

### `models/` — domínio

Classes imutáveis que representam as entidades do negócio, com `fromJson` e, quando
necessário, `copyWith`. Isolam o resto da aplicação da forma exata das colunas da base de
dados: se uma coluna mudar de nome, muda-se um `fromJson` e não dez ecrãs.

Entidades: `utilizador_model`, `cliente_model`, `encomenda_model`, `pedido_model`,
`fase_model`, `historico_model`, `incidencia_model`, `checklist_model`,
`reason_code_model`, `estado_ordem`.

Aqui vivem também os **enumerados de domínio**, que normalizam num único ponto os valores
que a base de dados guarda como texto livre — `PerfilUtilizador`, `EstadoConta`,
`EstadoOrdem`, `EstadoPedido`. Cada enumerado expõe `desdeTexto()` (leitura tolerante) e
`valorBd` (escrita canónica). Antes desta normalização, cada ecrã repetia a sua própria
lista de comparações em minúsculas.

Nota de segurança: `UtilizadorModel` não tem — nem pode ter — campo de palavra-passe. As
credenciais residem exclusivamente no Supabase Auth.

### `repositories/` — acesso a dados

Única camada autorizada a comunicar com o Supabase. Dez classes, todas derivadas de
`BaseRepository`:

| Repositório | Âmbito |
|---|---|
| `base_repository.dart` | Classe abstrata: acesso ao cliente, `guarda()`, `comoLista()`, `RepositoryException` |
| `encomendas_repository.dart` | Ordens de fabrico, fases, timeline, WIP hold, line clearance, cancelamento |
| `clientes_repository.dart` | Carteira comercial, pedidos de encomenda e sua aprovação |
| `operador_repository.dart` | Fila de trabalho e execução de tarefas no posto |
| `tecnico_repository.dart` | Fila de manutenção, aceitação e conclusão de intervenções |
| `portal_cliente_repository.dart` | Vista do cliente sobre as suas encomendas e rastreio |
| `postos_repository.dart` | Postos de trabalho |
| `fluxos_repository.dart` | Definição dos fluxos produtivos e das suas fases |
| `relatorios_repository.dart` | Métricas, histórico de emissões e upload de PDF |
| `utilizadores_repository.dart` | Gestão de contas pelo administrador (listar, aprovar, inativar) |

A separação por área de negócio, e não por tabela, é intencional: um único ecrã do operador
lê ordem, fase, histórico e incidência, e a coerência dessa leitura é responsabilidade de um
só repositório.

### `services/` — serviços aplicacionais

Lógica que não é acesso a dados puro nem interface.

- **`auth_service.dart`** — sessão do próprio utilizador: login, registo, logout, cache do
  perfil e validação do `estado_conta`. É *singleton*; com instâncias por ecrã, o perfil
  carregado no login ficava numa instância que nenhum outro ecrã via. Estende
  `BaseRepository` para que também as falhas de autenticação saiam como
  `RepositoryException` com texto de negócio. A gestão de contas *de terceiros* fica
  deliberadamente fora, em `UtilizadoresRepository`.
- **`pdf_service.dart`** e **`relatorio_turno.dart`** — composição dos relatórios em PDF
  (pacotes `pdf` e `printing`), separada do repositório que os envia para o Storage.

### `screens/` — interface, segmentada por perfil

Contém dois ecrãs comuns a todos (`login_screen.dart`, `registo_screen.dart`) e quatro
subdiretórios, um por perfil de utilizador. Cada subdiretório tem um *shell* — o esqueleto
de navegação daquele perfil — e os ecrãs que ele hospeda:

| Diretório | Shell | Ecrãs |
|---|---|---|
| `dashboard_admin/` | `dashboard_admin_shell.dart` | Dashboard principal, painel de controlo, criação de encomendas, gestão de fluxos, gestão de utilizadores, informações de clientes, pedidos de clientes, postos de trabalho, relatórios (+ `dialogos/` e `widgets/` próprios) |
| `terminal_operador/` | `operador_shell_screen.dart` | Fila de trabalho, detalhe de tarefa, histórico, relatórios (+ `popups/`) |
| `terminal_tecnico/` | `tecnico_shell_screen.dart` | Fila de manutenção, histórico, diálogo de conclusão de intervenção |
| `portal_cliente/` | `cliente_shell_screen.dart` | Rastreio, histórico, solicitação de encomenda (+ `widgets/`) |

O encaminhamento para o *shell* correto é feito num único ponto — o método
`_redirecionarPorPerfil` de `login_screen.dart` — a partir do valor de `PerfilUtilizador`.
Um perfil não reconhecido não entra: a sessão de Auth já aberta é imediatamente encerrada,
porque sem esse logout a conta voltava a entrar sozinha no arranque seguinte.

Os diálogos e widgets específicos de um perfil vivem dentro do respetivo subdiretório; só
sobe para `lib/widgets/` o que é efetivamente partilhado por mais do que um perfil.

### `widgets/` — componentes partilhados

Quatro componentes usados transversalmente: `estado_erro.dart` (apresentação uniforme de
falhas), `etiqueta_estado.dart` (cor e texto de um estado de ordem), `rodape_paginacao.dart`
(controlo de paginação das listas) e `dialogo_suporte.dart` (contacto de suporte, obtido por
RPC porque a política de RLS de `utilizadores` não deixa cada utilizador ler linhas alheias).

### Fora de `lib/`

- `supabase/functions/enviar-emails/` — a única Edge Function (ver 8.1.5).
- `test/` e `coverage/` — testes automatizados, incluindo os do `RecarregadorDebounced` com
  relógio virtual.
- `docs/` — documentação de projeto: `ARQUITETURA_REFACTOR.md`, `BUGS_RESOLVIDOS.md`,
  `AlteracoesNoOperador.md`, `AlteracoesNoPortalCliente.md`, `NotasDeAlteracoes.md`.
- `android/`, `ios/`, `web/`, `windows/`, `linux/`, `macos/` — projetos por plataforma,
  gerados pelo Flutter.

## 8.2.3 O perfil Técnico é um perfil autónomo

**Conclusão: sim.** O Técnico de Manutenção é um **quarto perfil de pleno direito**, ao lado
de Administrador, Operador e Cliente — não uma funcionalidade dentro do perfil Operador. A
verificação assenta em cinco pontos independentes do código:

**1. Valor próprio no enumerado de perfil.** Em `lib/models/utilizador_model.dart`,
`PerfilUtilizador` declara `tecnico` como membro distinto de `operador`:

```dart
enum PerfilUtilizador { administrador, operador, tecnico, cliente, desconhecido }
```

Tem leitura própria — `desdeTexto()` aceita `'tecnico'` e `'tecnico'` com acento, mapeando
ambos para `PerfilUtilizador.tecnico` — etiqueta própria (`'Técnico de Manutenção'`, contra
`'Funcionário'` do operador) e valor de gravação próprio: `valorBd` devolve `'Tecnico'`,
enquanto o operador grava `'Operador'`.

**2. Encaminhamento próprio no login.** `login_screen.dart:124` trata `tecnico` como *case*
autónomo do `switch`, levando a `TecnicoShellScreen` — um *shell* de navegação distinto do
`OperadorShellScreen`. Um técnico nunca vê a interface do operador.

**3. Superfície funcional própria.** `lib/screens/terminal_tecnico/` e
`lib/repositories/tecnico_repository.dart` são exclusivos deste perfil e não partilham ecrãs
nem métodos com o operador. O domínio é outro: o operador executa fases de fabrico; o
técnico trata incidências que bloqueiam a linha, através das RPC `aceitar_incidencia` e
`concluir_intervencao_tecnica`.

**4. Referência própria no modelo de dados.** A tabela `incidencias` tem coluna
`tecnico_id` (com chave estrangeira para `utilizadores`), distinta de `operador_id` usada
nos registos de produção e de qualidade. Uma incidência é atribuída a um técnico, e a
timeline da ordem resolve o nome pelo *embed* `utilizadores:tecnico_id (nome_utilizador)`.
Ao atribuir uma intervenção, `UtilizadoresRepository.obterParaAtribuicao()` filtra
explicitamente por perfil de manutenção
(`.or('perfil.ilike.tecnico,perfil.ilike.técnico')`) — restrição introduzida porque antes o
dropdown devolvia toda a tabela e permitia atribuir uma intervenção a um cliente.

**5. Predicado de RLS próprio no servidor.** As tabelas públicas têm RLS ativa com políticas
por perfil, expressas por funções-predicado (`e_admin()`, `e_pessoal()`, `e_tecnico()`). O
acesso do técnico é aberto pelo predicado dedicado `e_tecnico()` — e não por `e_pessoal()`,
que cobre indiferenciadamente o pessoal de produção. A dependência é suficientemente
sensível para estar documentada no próprio código: em
`dashboard_admin/dialogos/dialogo_editar_utilizador.dart:113`, o valor do perfil é gravado
deliberadamente **sem acento** (`'Tecnico'`) para coincidir com o que `e_tecnico()` compara
na base de dados, sob pena de o técnico ficar sem acesso.

> Nota metodológica: as migrações SQL não estão versionadas neste repositório — `supabase/`
> contém apenas a Edge Function, sendo o esquema e as políticas geridos no projeto Supabase.
> A evidência do ponto 5 provém das invocações e das notas de implementação no código Dart,
> que referenciam `e_tecnico()` e a exigência de correspondência exata do valor gravado.

**Observação sobre a coluna `perfil`.** É texto livre e não um tipo `enum` de Postgres, o
que explica as variantes históricas toleradas (`Admin`/`Administrador`,
`Operador`/`Funcionario`, `Tecnico`/`Técnico`). A normalização é feita num ponto único do
lado do cliente (`PerfilUtilizador.desdeTexto`) e por comparação insensível a maiúsculas do
lado do servidor. Como melhoria futura, converter a coluna num tipo enumerado com restrição
eliminaria a classe de erro que a gravação sem acento hoje evita por convenção.
