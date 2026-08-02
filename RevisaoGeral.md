# Revisão Geral do Projeto

**Data:** 2 de agosto de 2026
**Âmbito:** revisão transversal de bugs, segurança, estrutura de código e dívida técnica em todo o projeto.
**Nota:** esta análise **não** inclui funcionalidades novas. Cobre apenas o que existe e o que precisa (ou não) de ser melhorado.

**Estado base no momento da análise:**

| Verificação | Resultado |
|---|---|
| `flutter test` | 194 testes, todos passam |
| `flutter analyze` | 41 issues — 0 errors, 2 warnings, 39 infos |
| Advisors de segurança do Supabase | 12 ERROR + 8 WARN |

Esta revisão fecha o ciclo de análise por módulos (`dashboard_admin`, `terminal_operador`, `portal_cliente`) e cobre sobretudo o que ficou **fora** desses três: `main.dart`, `auth_service.dart`, `login_screen.dart`, `registo_screen.dart`, `core/`, a base de dados e a infraestrutura de testes.

---

## 1. Segurança — crítico

### 1.1 RLS desligado em 12 tabelas

Row Level Security não está ativo em nenhuma destas tabelas do schema `public`:

`utilizadores`, `clientes`, `encomendas`, `pedidos_encomenda`, `avaliacoes`, `notificacoes`, `incidencias`, `historico_producao`, `fases_padrao`, `tipos_produto`, `postos_trabalho`, `reason_codes`

**Porque é que isto é grave.** A anon key está compilada em [supabase_config.dart:8](lib/core/supabase_config.dart#L8) e é pública por natureza — vai no bundle web e dentro do APK, qualquer pessoa a extrai. Sem RLS, essa chave dá acesso direto e total à API REST:

```
GET   /rest/v1/clientes                              -> carteira de clientes completa
GET   /rest/v1/encomendas                            -> todas as encomendas de todos os clientes
PATCH /rest/v1/utilizadores?utilizador_id=eq.<id>    -> {"perfil":"Admin","estado_conta":"Ativo"}
```

O último pedido promove qualquer utilizador registado a administrador, sem passar pela aplicação.

**Consequência para o trabalho já feito.** Todo o controlo de acesso da aplicação vive na UI. As correções de identidade por chave estrangeira feitas no `portal_cliente` (usar `clientes.utilizador_id` em vez de comparar nomes) impedem um cliente de ver dados errados *através da app* — mas não impedem ninguém de contornar a app por completo. Enquanto o RLS estiver desligado, essas correções são de correção funcional, não de segurança.

Este item foi marcado como *deferred* na análise do `portal_cliente`. Continua a ser o item nº1 do projeto, acima de qualquer outro deste documento.

### 1.2 Política RLS permissiva em `historico_relatorios`

A tabela `historico_relatorios` tem a política `Permitir leitura e escrita para todos` aplicada a `ALL` com `USING (true)` e `WITH CHECK (true)`. Tem RLS ligado, mas a política não filtra nada — leitura e escrita livres para qualquer role.

### 1.3 Bucket público `relatorios` permite listagem

O bucket `relatorios` é público e tem uma política SELECT ampla em `storage.objects` (`Permitir Leitura Pública de Relatorios`) que permite **listar** todos os ficheiros, não apenas aceder a um objeto por URL conhecido. Relatórios de produção de todos os clientes ficam enumeráveis por quem tenha a anon key. O acesso por URL direto não precisa desta política.

### 1.4 Funções `SECURITY DEFINER` executáveis por `anon`

Quatro funções correm com os privilégios do dono e são chamáveis sem sessão iniciada:

| Função | Avaliação |
|---|---|
| `rastrear_encomenda(p_codigo text)` | Intencional — suporta o rastreio público. Manter. |
| `ligar_cliente_utilizador()` | Sem argumentos, `SECURITY DEFINER`, chamável por `anon`. Revogar `EXECUTE` a `anon`. |
| `ligar_utilizador_cliente()` | Idem. Liga identidades — não deve ser acessível a anónimos. |
| `sync_fase_posto_texto()` | Parece ser função de trigger. Não deve estar exposta via `/rest/v1/rpc/`. |

### 1.5 Proteção contra passwords comprometidas desativada

O Supabase Auth pode validar passwords contra a HaveIBeenPwned. Está desligado. Ativação é uma opção de configuração, sem alterações de código.

---

## 2. Bugs de código — ✅ RESOLVIDO (2 de agosto de 2026)

> Todos os pontos desta secção foram corrigidos. Estado após as correções:
> **197 testes passam** (+3), **`flutter analyze`: 33 issues, 0 errors, 0 warnings** (eram 41 com 2 warnings).
> O detalhe do que foi feito em cada ponto está em [8. Resoluções aplicadas](#8-resoluções-aplicadas).

### 2.1 `lib/services/auth_service.dart`

Este ficheiro ficou fora de todas as revisões por módulo. É o único do projeto com *warnings* reais do analisador.

| Local | Problema |
|---|---|
| [auth_service.dart:68](lib/services/auth_service.dart#L68) | `session.user != null` é sempre verdadeiro — `Session.user` é não-nullable. Condição morta. |
| [auth_service.dart:70](lib/services/auth_service.dart#L70) | `session.user!` — o `!` não tem efeito, pela mesma razão. |
| [54](lib/services/auth_service.dart#L54), [103](lib/services/auth_service.dart#L103), [120](lib/services/auth_service.dart#L120), [122](lib/services/auth_service.dart#L122) | Quatro `print()` em código de produção. São os únicos do projeto — todo o resto usa `debugPrint`. `print` continua a escrever no output em release. |
| [auth_service.dart:37-39](lib/services/auth_service.dart#L37-L39) | `try { ... } catch (e) { rethrow; }` não faz nada. Remover o bloco. |

**Erros indistinguíveis.** [`obterUtilizadorPorId`](lib/services/auth_service.dart#L44) apanha tudo e devolve sempre `'Erro ao carregar dados do perfil do utilizador.'`. Um utilizador autenticado sem linha na tabela `utilizadores` (o `.single()` rebenta) fica indistinguível de uma falha de rede. Para o utilizador e para quem faz suporte, são o mesmo ecrã.

**Sessão fica aberta em falha de perfil.** Em [`login()`](lib/services/auth_service.dart#L27), se `obterUtilizadorPorId` falhar, a exceção sobe sem `logout()`. O `signInWithPassword` já foi bem-sucedido, portanto a sessão Supabase fica ativa e persistida enquanto a UI diz que o login falhou. Ao reabrir a app, `verificarSessaoAtiva()` encontra essa sessão. O travão de `estado_conta` [na linha 31](lib/services/auth_service.dart#L31) faz logout corretamente; este caminho não.

**Fora do padrão da camada de dados.** `AuthService` é a única classe de acesso a dados que não estende `BaseRepository` nem usa `guarda()`. Lança `Exception` cru, obrigando [login_screen.dart:95](lib/screens/login_screen.dart#L95) a limpar a mensagem com `replaceAll('Exception: ', '')` — existe `descreverErro` em [estado_erro.dart](lib/widgets/estado_erro.dart) exatamente para isto.

### 2.2 `lib/screens/registo_screen.dart`

**`BuildContext` através de async gaps.** [Linhas 82 e 86](lib/screens/registo_screen.dart#L82) usam `ScaffoldMessenger.of(context)` depois de `await`, sem verificação de `mounted`. São os dois únicos `use_build_context_synchronously` que restam no projeto — todos os outros já foram corrigidos nas revisões anteriores. O bloco `finally` na [linha 90](lib/screens/registo_screen.dart#L90) já faz a verificação; os `catch` não.

**`perfil` usado como estado de aprovação.** [Linhas 44-51](lib/screens/registo_screen.dart#L44-L51) inserem `'perfil': 'Pendente'` e **não escrevem `estado_conta`**. Mas `'Pendente'` não é um perfil válido:

- `PerfilUtilizador.desdeTexto('Pendente')` cai no `default` e devolve `desconhecido`
- `PerfilUtilizador.desconhecido.valorBd` devolve `'Operador'`
- `PerfilUtilizador.desconhecido.etiqueta` devolve `'Funcionário'`

Ou seja, uma conta acabada de registar aparece na gestão de utilizadores como "Funcionário". O campo `perfil` está a codificar aprovação, papel que pertence a `estado_conta` — que existe, tem enum próprio ([utilizador_model.dart:47](lib/models/utilizador_model.dart#L47)) e falha fechado em `pendente`. Dois campos a representar o mesmo conceito de formas inconsistentes.

**Falha parcial deixa conta órfã.** O registo são dois passos do lado do cliente: `signUp` no Auth, depois `insert` em `utilizadores`. Se o segundo falhar, fica uma conta no Auth sem linha de perfil. O utilizador não consegue registar-se de novo (o email já existe no Auth) nem iniciar sessão (não há perfil). Não há recuperação pela aplicação. Devia ser uma RPC transacional ou um trigger em `auth.users`.

**Validação fraca.** O email só é validado como não-vazio — sem verificação de formato. A password não tem campo de confirmação.

**Acesso direto ao Supabase.** Junto com `operador_shell_screen`, é um dos dois únicos sítios em `lib/screens/` que ainda chamam `Supabase.instance.client` para ler/escrever dados. Todo o resto do projeto já passa por repositórios.

### 2.3 `lib/main.dart`

**Sem tratamento de falha na inicialização.** [`SupabaseConfig.init()`](lib/main.dart#L11) é aguardado antes de `runApp`, sem `try/catch`. Se falhar — rede indisponível no arranque, por exemplo — a aplicação morre com ecrã preto, antes de existir qualquer UI para mostrar o erro.

**Sem sistema de rotas.** Não há `navigatorKey`, `routes` nem `onGenerateRoute`. A navegação é toda `MaterialPageRoute` construído inline. Isto torna manual em cada ecrã tudo o que dependa de navegação global: deep-links, e sobretudo o logout forçado (voltar ao login a partir de qualquer ponto da app).

**Sem captura global de erros.** Não há `ErrorWidget.builder` nem `FlutterError.onError`. Qualquer exceção durante o `build` mostra o ecrã vermelho de erro do Flutter ao utilizador final.

### 2.4 Gestão de sessão

**Ninguém subscreve `onAuthStateChange`.** Se o token expirar ou a sessão for revogada — por exemplo, um administrador desativa uma conta a meio do turno — a aplicação não reage. Fica a mostrar a UI com os dados em cache e a falhar silenciosamente nas queries seguintes, em vez de encaminhar para o login.

O travão `estado_conta != ativo` só corre em dois momentos: no login e no arranque (`verificarSessaoAtiva`). O [`operador_shell_screen`](lib/screens/terminal_operador/operador_shell_screen.dart#L85) é o único ecrã que vigia o perfil em tempo real, através de um stream próprio — comportamento correto que não foi generalizado aos outros dois módulos.

---

## 3. Estrutura de código

### 3.1 Ecrãs do `dashboard_admin` por partir

| Ficheiro | Linhas |
|---|---|
| [painel_controlo_screen.dart](lib/screens/dashboard_admin/painel_controlo_screen.dart) | 1761 |
| [informacoes_clientes_screen.dart](lib/screens/dashboard_admin/informacoes_clientes_screen.dart) | 1230 |
| [criar_encomenda_screen.dart](lib/screens/dashboard_admin/criar_encomenda_screen.dart) | 1100 |
| [gestao_utilizadores_screen.dart](lib/screens/dashboard_admin/gestao_utilizadores_screen.dart) | 1024 |

Quatro ficheiros, 5115 linhas — cerca de 30% de todo o `lib/`. O `portal_cliente` e o `terminal_operador` foram reestruturados nas revisões anteriores; o `dashboard_admin` teve a camada de dados extraída para repositórios, mas a UI não foi partida. É a maior dívida estrutural que resta.

### 3.2 Poucos widgets extraídos

A pasta [lib/screens/dashboard_admin/widgets/](lib/screens/dashboard_admin/widgets/) tem apenas três ficheiros (`cartao_kpi`, `etiqueta_estado`, `mouse_drag_scroll_behavior`) — nenhum widget foi extraído dos quatro ecrãs acima.

Fora do `dashboard_admin` não existe biblioteca de widgets partilhada além de [estado_erro.dart](lib/widgets/estado_erro.dart). Diálogos de confirmação, tabelas ordenáveis, badges de estado e barras de filtro estão reimplementados em cada módulo.

### 3.3 Sem gestão de estado partilhado

Cada ecrã é um `StatefulWidget` com `setState` e a sua própria cópia dos dados. `AuthService` é instanciado de novo em cada sítio que precisa dele (`AuthService()`), portanto o campo `_utilizadorAtual` nunca é partilhado — cada ecrã volta a ir buscar o perfil à base de dados. Não existe uma fonte única de verdade para "quem está autenticado".

### 3.4 Documentos de análise na raiz

Cinco ficheiros markdown na raiz do repositório: `NotasDeAlteracoes.md`, `BUGS_RESOLVIDOS.md`, `ARQUITETURA_REFACTOR.md`, `AlteracoesNoOperador.md`, `AlteracoesNoPortalCliente.md` (mais este). São histórico de trabalho, não documentação do produto. Arrumar em `docs/`, deixando o `README.md` como entrada.

---

## 4. Testes

**194 testes, cobertura desequilibrada.** Cobrem modelos, `estado_erro` e três repositórios. Ficam sem qualquer teste:

- [encomendas_repository.dart](lib/repositories/encomendas_repository.dart) — 431 linhas, o núcleo do negócio: `lancar`, `avancarFase`, `cancelar`, `aplicarWipHold`, `registarIntervencaoTecnica`, `aprovarLineClearance`
- `clientes_repository`, `fluxos_repository`, `utilizadores_repository`, `postos_repository`, `relatorios_repository`
- `pdf_service` (410 linhas), `auth_service`

**Zero testes de widget para ecrãs.** Nenhum ecrã tem teste.

**`RecarregadorDebounced` sem testes.** [realtime.dart](lib/core/realtime.dart) tem lógica de temporização não trivial — aresta inicial imediata, teto de rajada, proteção contra recarregamentos sobrepostos e reentrância no `finally`. É exatamente o tipo de código que se parte em silêncio numa alteração futura e só dá sinal em produção.

**Sem CI.** Não existe `.github/workflows`. Nada garante que `flutter analyze` e `flutter test` corram antes de um commit ou merge.

---

## 5. Menor

**Lints (41 no total, nenhum error):**

| Tipo | Nº | Nota |
|---|---|---|
| `withOpacity` deprecated | ~20 | Trivial: trocar por `.withValues()`. Espalhado por vários ecrãs. |
| `DropdownButtonFormField.value` deprecated | ~15 | Os do `portal_cliente` são **deliberados e documentados** (`initialValue` não reage a mudanças de estado). Os do `dashboard_admin` não foram avaliados — verificar caso a caso antes de mexer. |
| `onReorder` deprecated | 1 | [gestao_fluxos_screen.dart:483](lib/screens/dashboard_admin/gestao_fluxos_screen.dart#L483) — usar `onReorderItem`. |
| `anonKey` deprecated | 1 | [supabase_config.dart:14](lib/core/supabase_config.dart#L14) — usar `publishableKey`. |
| `avoid_print` | 4 | Todos em `auth_service` (ver 2.1). |
| `use_build_context_synchronously` | 2 | Ambos em `registo_screen` (ver 2.2). |
| `unnecessary_null_comparison` / `unnecessary_non_null_assertion` | 2 | Os únicos warnings. Ambos em `auth_service` (ver 2.1). |
| `unnecessary_to_list_in_spreads` | 1 | [postos_trabalho_screen.dart:377](lib/screens/dashboard_admin/postos_trabalho_screen.dart#L377). |

**Outros:**

- `pubspec.yaml` — a `description` tem mojibake (`AplicaÃ§Ã£o de GestÃ£o de ProduÃ§Ã£o`): o ficheiro foi gravado com encoding errado. Versão presa em `1.0.0+1` desde o início.
- A pasta `coverage/` está na raiz apesar de `/coverage/` constar do `.gitignore` — confirmar com `git ls-files coverage` se está a ser versionada.
- Revisar `analysis_options.yaml`: com apenas o `flutter_lints` base, regras como `avoid_print` ficam em `info` e passam despercebidas.

---

## 6. Ordem recomendada

1. **RLS e restantes avisos da base de dados (secção 1).** Primeiro e sozinho. Enquanto o RLS estiver desligado, todo o restante trabalho de segurança é cosmético.
2. **`auth_service.dart` + `registo_screen.dart` (2.1, 2.2).** Cerca de meio dia. Fecha o último módulo por rever e elimina os 2 únicos warnings e os 2 únicos `use_build_context_synchronously` do projeto.
3. **Robustez do arranque e da sessão (2.3, 2.4).** `try/catch` no init, captura global de erros, `onAuthStateChange` com logout forçado.
4. **Partir os quatro ecrãs grandes do `dashboard_admin` (3.1, 3.2).**
5. **Testes do `encomendas_repository` e do `RecarregadorDebounced`, mais CI (secção 4).** Antes de qualquer funcionalidade nova.
6. **Lints e limpezas (secção 5).** Em qualquer altura; sem urgência.

---

## 7. Decisões pendentes

Duas questões que precisam de resposta antes de avançar:

**7.1 — RLS: quem escreve as políticas?**
As políticas por perfil (administrador: acesso total; operador: leitura de produção e escrita de histórico; cliente: apenas as suas linhas via `clientes.utilizador_id`) podem ser escritas e aplicadas como migração a partir daqui, ou feitas manualmente na consola do Supabase. É preciso decidir qual.

**7.2 — `perfil: 'Pendente'` no registo: intencional?** — ✅ **Decidido a 2 de agosto de 2026.**
Confirmado na base de dados que **nenhuma** linha usa `perfil='Pendente'` (7 utilizadores: 5 Operador, 1 Cliente, 1 Administrador, todos Ativo), logo o custo de migração era zero. Decisão: passar a usar `estado_conta: 'Pendente'` como travão, com `perfil` a conter apenas papéis reais. Aplicado — ver 8.2.

---

## 8. Resoluções aplicadas

**Data:** 2 de agosto de 2026. Âmbito: toda a secção 2 (bugs de código). As secções 1, 3, 4 e 5 continuam por resolver.

### 8.1 `auth_service.dart` reescrito

- Passou a **estender `BaseRepository`** e a envolver as operações em `guarda()`. Deixa de lançar `Exception` cru: todas as falhas saem como `RepositoryException` com texto de negócio.
- **Condição morta e `!` inútil removidos** — `verificarSessaoAtiva` passou a verificar apenas `currentSession == null` e usa `sessao.user.id` diretamente. Eram os 2 únicos *warnings* do projeto.
- **4 `print()` eliminados.** Eram os únicos do projeto; o diagnóstico agora vem da mensagem da própria exceção.
- **`try/catch/rethrow` vazio removido.**
- **`obterUtilizadorPorId` passou a usar `maybeSingle`**, distinguindo "credencial sem perfil associado" (mensagem própria, que encaminha para o Administrador) de falha de rede.
- **Sessão órfã em falha de perfil corrigida.** Se `obterUtilizadorPorId` falhar depois de um `signInWithPassword` bem-sucedido, `login()` faz agora `logout()` antes de propagar o erro. Antes, ficava uma sessão ativa e persistida enquanto a interface dizia que o login tinha falhado — e a app entrava autenticada no arranque seguinte.
- **`login()` devolve `UtilizadorModel` não-nullable.** O caminho "sem erro mas sem utilizador" deixou de existir, e com ele a verificação redundante no `login_screen`.
- **`logout()` não usa `guarda`** de propósito: é chamado a partir de caminhos de erro (incluindo o do próprio `login`) e uma falha a fechar sessão não pode substituir o erro original.
- **`obterTodosUtilizadores` e `atualizarEstadoUtilizador` removidos** — duplicavam `UtilizadoresRepository.obterTodos` / `alterarEstadoConta` e não tinham uma única utilização.

### 8.2 `registo_screen.dart`

- **Os 2 `use_build_context_synchronously` desapareceram.** Todos os caminhos verificam `mounted` antes de tocar no `context`.
- **`perfil: 'Pendente'` substituído** por `perfil: 'Cliente'` (papel real, o menos privilegiado, que o Administrador ajusta ao aprovar) + `estado_conta: 'Pendente'`, que é o campo que o `AuthService` usa efetivamente como travão de login. O campo `perfil` deixou de codificar aprovação.
- **Acesso ao Supabase movido para `UtilizadoresRepository.registarPedidoDeAcesso`** — o ecrã deixou de ser um dos dois últimos em `lib/screens/` a chamar `Supabase.instance.client` para ler/escrever dados.
- **Conta órfã tratada.** Se o `insert` falhar depois do `signUp`, a sessão é fechada e a mensagem encaminha explicitamente para o Administrador, em vez de sugerir nova tentativa — que nunca poderia funcionar, porque o email já existe no Auth. A eliminação da causa (RPC transacional ou trigger em `auth.users`) fica para o trabalho da secção 1, que já mexe na base de dados.
- **A sessão aberta pelo `signUp` é fechada.** Uma conta pendente de aprovação não pode ficar autenticada.
- **Validação de e-mail por formato** e **campo de confirmação de palavra-passe** adicionados. Um engano a escrever a password só se descobria no primeiro login, que falha sem explicação possível porque a conta até existe.
- Campos passam a ficar desativados durante a submissão.

### 8.3 `main.dart`

- **`SupabaseConfig.init()` protegido com `try/catch`.** Em caso de falha, arranca um `_AppArranqueFalhado` com mensagem legível em vez de morrer com ecrã preto. O detalhe técnico só aparece em `kDebugMode`.
- **`ErrorWidget.builder`** substitui o ecrã vermelho do Flutter em release por um aviso contido. Em debug, o ecrã vermelho mantém-se — é útil a quem está a desenvolver.
- **`FlutterError.onError`** encadeado sobre o anterior, para registo dos erros não tratados.
- **`navigatorKey` e `scaffoldMessengerKey` globais** adicionados, o que torna possível navegar e mostrar mensagens a partir de código que não pertence a nenhum ecrã.

### 8.4 Perda de sessão involuntária

Criados dois ficheiros:

- **`lib/core/sessao.dart` — `VigilanteSessao`.** Subscreve `onAuthStateChange` e, quando a sessão termina sem ser a pedido, faz `pushAndRemoveUntil` para o login com a mensagem "A sua sessão terminou. Inicie sessão novamente.". Cobre token expirado e conta desativada pelo Administrador a meio do turno — situações em que a app ficava a mostrar dados em cache e a falhar em silêncio nas queries seguintes.
- **`lib/core/sessao_local.dart` — `SessaoLocal`.** Distingue o término pedido pela aplicação (botão de logout, `signOut` após `signUp`) do involuntário. Sem isto, cada logout normal daria uma navegação a mais e uma mensagem de erro que não corresponde a nada. É uma **marca temporal com janela de 5 segundos**, não um booleano, para não ficar presa: se o `signOut` falhar a meio, expira sozinha em vez de mascarar a perda de sessão seguinte.

O travão de `estado_conta` do `AuthService` continua a existir e a correr no login e no arranque; o vigilante cobre o intervalo entre os dois.

### 8.5 `login_screen.dart`

- `replaceAll('Exception: ', '')` substituído por **`descreverErro`**, que já existia em `estado_erro.dart` para este efeito.
- Verificação de `utilizador == null` removida (`login()` já não devolve `null`).
- **`_redirecionarPorPerfil` passou a `Future<void>`** e o `logout()` do caso `desconhecido` é agora **aguardado**. Antes era *fire-and-forget*: a sessão podia ficar aberta e a conta entrava sozinha no arranque seguinte, apesar de não ter perfil válido.

### 8.6 Testes

Adicionado `test/core/sessao_local_test.dart` — 3 testes que cobrem a marca ausente, a marca consumida e o facto de a marca servir apenas uma vez (um segundo `signOut`, este involuntário, não pode aproveitar a marca do primeiro).

**Total: 197 testes, todos a passar.**
