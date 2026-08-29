# 8.4 Lógica de negócio crítica no servidor

## 8.4.1 Porque existe uma camada de lógica no servidor

A aplicação tem **três clientes distintos** a operar sobre os mesmos dados: o dashboard do
administrador, o terminal do operador e o portal do cliente (mais o terminal do técnico, um
quarto perfil introduzido depois). Antes da reorganização, cada um implementava em Dart as
transições de estado da produção, com dois problemas estruturais.

**Primeiro, falta de atomicidade.** Quatro fluxos críticos faziam entre duas e quatro
chamadas independentes ao Supabase, sem transação a envolvê-las (bug (d),
`docs/BUGS_RESOLVIDOS.md`):

| Fluxo | Escritas separadas | Consequência de falha intermédia |
| --- | --- | --- |
| Avançar fase | `INSERT` histórico → `UPDATE` encomenda | Histórico órfão; ordem presa na fase anterior |
| WIP Hold | `INSERT` incidência → `UPDATE em_suspenso` | Incidência aberta sem a ordem suspensa |
| Line Clearance | `UPDATE` incidência → `UPDATE` encomenda | Incidência fechada com a ordem presa em hold |
| Aprovar pedido | 4 escritas | Ordem lançada com o pedido ainda `Pendente` |

Uma quebra de rede a meio da sequência — o caso normal num tablet de chão de fábrica — deixa
a base de dados num estado que nenhuma regra de negócio admite, e sem qualquer indicação
disso ao utilizador.

**Segundo, divergência da regra.** As regras de negócio (não avançar uma ordem em hold, não
aplicar dois holds seguidos, não validar *clearance* sem manutenção registada) não estavam
validadas em lado nenhum, e o cálculo da fase seguinte estava escrito em Dart em mais do que
um ecrã. Foi exatamente essa duplicação que originou o bug (b) dos relatórios. Uma regra
validada apenas na interface é, além disso, uma regra que **qualquer chamada direta à API
contorna** — a chave pública do Supabase está no cliente por definição.

A resposta foi mover as transições de estado para funções PL/pgSQL invocadas por RPC. O
servidor passou a ser o guardião: a regra existe num só sítio, corre dentro de uma transação,
e é a mesma independentemente de quem chama.

---

## 8.4.2 As cinco RPCs de negócio

| Função | Chamada em | Responsabilidade | Guardas de negócio |
| --- | --- | --- | --- |
| `avancar_fase_encomenda(bigint, jsonb)` | `encomendas_repository.dart:936` | Histórico + checklist + transição de fase | Rejeita ordem cancelada, em hold ou já concluída; exige checklist quando a fase a tem |
| `aplicar_wip_hold(bigint, integer, text)` | `encomendas_repository.dart:954` | Incidência + suspensão da ordem | Rejeita hold duplicado; valida o *reason code* |
| `aprovar_line_clearance(bigint)` | `encomendas_repository.dart:965` | Fecha a incidência + liberta a ordem | Exige manutenção previamente registada |
| `cancelar_ordem(bigint, text)` | `encomendas_repository.dart:974` | Cancelamento lógico + fecho de incidências | Exige motivo não vazio |
| `aceitar_incidencia(bigint)` e `concluir_intervencao_tecnica(bigint, text, text, text)` | `tecnico_repository.dart:91` e `:108` | Registo da intervenção técnica | Atribuição ao técnico autenticado; a ordem **não** retoma no fecho |

Existe ainda uma sexta função da mesma família, `aprovar_pedido_encomenda(bigint, date, text)`
(`clientes_repository.dart:177`), que converte um pedido do portal B2B em ordem de fabrico e
que segue exatamente os mesmos princípios.

### `avancar_fase_encomenda` — a transição central

**O que faz.** Recebe o identificador da ordem e a lista de pontos de controlo Poka-Yoke
validados pelo operador. Numa única transação: grava a linha em `historico_producao` com a
fase que fecha, escreve os pontos validados em `checklist_execucoes`, determina a fase
seguinte a partir da ordem do roteiro do tipo de produto, e atualiza `encomendas` —
`fase_atual_id`, `data_inicio_fase` e reposição de `segundos_parados_fase`. Se não houver
fase seguinte, deixa `fase_atual_id` a `NULL`, que é como o modelo `EstadoOrdem` deriva
*concluída*. Devolve `concluida`, `proxima_fase_id`, `proxima_fase_nome`, `historico_id` e
`checklist_registada`.

**Porque corre no servidor.** Três razões acumuladas:

1. *Atomicidade.* O histórico e o avanço têm de acontecer juntos, ou nenhum. Feito do cliente
   eram duas chamadas: uma falha entre elas deixava um registo de histórico órfão com a ordem
   parada na mesma fase.
2. *Unicidade da regra da fase seguinte.* O `detalhe_tarefa_screen` reimplementava em Dart
   «próxima fase = índice + 1», paralelamente ao dashboard. Duas cópias da mesma regra é
   como o bug (b) apareceu. Hoje é o servidor que decide qual é a fase seguinte, e os ecrãs
   limitam-se a mostrar o nome que a RPC devolve.
3. *Prova de conformidade.* A checklist é gravada na **mesma transação** do avanço: ou fica
   prova do que foi verificado, ou não há avanço. Numa segunda chamada, cada quebra de rede
   produziria uma fase fechada sem registo — precisamente o caso em que interessa saber o que
   foi verificado. Uma fase com checklist chamada sem checklist é recusada, exceto para o
   perfil Administrador, e aí o desvio fica gravado como não conformidade (`conforme = false`)
   em vez de desaparecer.

**Guardas que o cliente não conseguia garantir.** Recusa o avanço de uma ordem cancelada, em
WIP Hold, ou já concluída. Nenhuma destas verificações é fiável na interface: entre o momento
em que o ecrã carregou a ordem e o momento em que o operador carrega no botão, outro
utilizador pode ter posto a ordem em hold.

### `aplicar_wip_hold` — suspender a linha

**O que faz.** Cria a incidência em `incidencias` a partir do *reason code* e da descrição do
operador, deriva o `posto_trabalho_id` da fase atual da ordem, e marca `em_suspenso = true`
na ordem — tudo numa transação.

**Porque corre no servidor.** Além da atomicidade (uma incidência aberta com a ordem **não**
suspensa é o pior estado possível: a linha parece disponível e não está), há aqui uma
derivação de dados que o cliente fazia mal. O posto de trabalho era resolvido em Dart e ficava
sempre nulo em `incidencias.posto_trabalho_id`; a RPC deriva-o da fase atual, o que corrigiu
o campo de passagem. A validação de hold duplicado só é fiável no servidor, porque depende do
estado no instante da escrita e não do estado que o ecrã leu.

### `aprovar_line_clearance` — retomar a linha

**O que faz.** Marca `line_clearance_validado = true`, `line_clearance_por` e
`data_line_clearance` na incidência, acumula em `encomendas.segundos_parados_fase` o tempo que
a ordem esteve parada, e repõe `em_suspenso = false`. A ordem volta a ser trabalhável.

**Porque corre no servidor.** É o simétrico do WIP Hold e tem o mesmo risco invertido: uma
incidência fechada com a ordem presa em hold deixa a ordem parada sem que nada na interface
explique porquê. O acumulador de tempo parado é outra razão: é uma escrita de leitura-e-soma
(`segundos_parados_fase = segundos_parados_fase + …`) que, feita do cliente, perderia
incrementos sempre que dois *line clearances* coincidissem. E a guarda «exige manutenção
previamente registada» é uma regra de qualidade — não se valida a limpeza de linha de uma
avaria que ninguém reparou.

### `cancelar_ordem` — cancelamento sem perder rastreabilidade

**O que faz.** Marca `cancelada = true`, grava `motivo_cancelamento` e `data_cancelamento`, e
fecha as incidências que a ordem tenha em aberto. Não apaga nada.

**Porque corre no servidor.** A versão anterior executava um `DELETE` físico a partir do ecrã
(bug (e)): a ordem desaparecia da base de dados, e com ela o histórico de produção e as
incidências associadas. Um sistema MES não pode perder o rasto de uma ordem só porque foi
cancelada — o cancelamento é ele próprio informação de gestão. A RPC transforma a operação
num cancelamento **lógico**, e a limpeza das incidências em aberto tem de ir na mesma
transação para não ficarem paragens abertas de uma ordem que já não existe na linha. A guarda
de motivo não vazio é o que garante que o registo serve para alguma coisa.

### `aceitar_incidencia` e `concluir_intervencao_tecnica` — a intervenção técnica

Estas duas RPC cobrem o troço de manutenção do ciclo da incidência, e existem separadas
porque marcam dois instantes distintos que o modelo `IncidenciaModel` distingue.

**`aceitar_incidencia(p_incidencia_id)`** atribui a incidência ao técnico autenticado
(`tecnico_id`) e escreve `data_inicio_intervencao`. É esse instante — e não o do registo da
avaria — que abre a contagem do MTTR; o intervalo anterior é `tempoEspera`. Correr no
servidor é o que garante que o `tecnico_id` gravado é o do utilizador da sessão e não um
identificador enviado pelo cliente, e que dois técnicos não assumem a mesma incidência em
simultâneo.

**`concluir_intervencao_tecnica(p_incidencia_id, p_diagnostico, p_acoes, p_pecas)`** fecha a
intervenção: grava o diagnóstico (a causa apurada, distinta do sintoma relatado pelo
operador), o relatório de ações, as peças substituídas, marca `manutencao_concluida = true`,
`data_fim_manutencao`, e leva o estado a `AGUARDA_LINE_CLEARANCE`.

O ponto de negócio importante é o que esta função **não** faz: **a ordem não retoma aqui**.
Fica a aguardar o *line clearance* da qualidade, que é a `aprovar_line_clearance` descrita
acima. A separação entre «reparado» e «autorizado a produzir» é uma regra de qualidade, e
tê-la codificada em duas funções distintas impede que um técnico, sozinho, devolva uma ordem
à linha sem validação — o que aconteceria se o fecho da intervenção fizesse as duas coisas.

> **Nota sobre o caminho alternativo do administrador.**
> `EncomendasRepository.registarIntervencaoTecnica()` (`:892`) permite ao administrador
> preencher o registo à mão, e é um `UPDATE` direto e não uma RPC. Existe para o caso da
> assistência externa, em que não há técnico com conta na aplicação para executar a RPC. O
> comentário no código regista que chega deliberadamente ao **mesmo estado**
> (`AGUARDA_LINE_CLEARANCE`): a origem do registo muda, o ponto do ciclo em que a ordem fica
> não muda. Sendo escrita numa só tabela, não precisa da garantia transacional das outras.

---

## 8.4.3 `SECURITY INVOKER` e não `SECURITY DEFINER`

Uma função PL/pgSQL corre com as permissões de quem a chama (`SECURITY INVOKER`, o
comportamento por omissão) ou com as do seu criador (`SECURITY DEFINER`). As cinco RPC de
negócio são todas `SECURITY INVOKER` — verificado no servidor, `prosecdef = false` — com
`EXECUTE` concedido a `anon` e `authenticated`.

A escolha é deliberada e assenta em três argumentos.

**1. Não abrir um *bypass* permanente ao RLS.** Uma função `SECURITY DEFINER` executa com os
privilégios do dono, tipicamente um papel com acesso total, e ignora as políticas de
*Row Level Security* das tabelas que toca. Se estas RPC fossem *definer*, qualquer detentor da
chave pública passaria a poder mover **qualquer** ordem da fábrica — as políticas de RLS que
venham a ser ativadas não teriam efeito nenhum sobre o caminho mais crítico do sistema.
Sendo *invoker*, as funções continuam sujeitas às políticas do utilizador autenticado: quando
o RLS for ativado, ele aplica-se automaticamente também aqui, sem ser preciso reescrever
função nenhuma.

**2. Estas funções não precisam de privilégios que o chamador não tenha.** É o critério que
decide. `SECURITY DEFINER` justifica-se quando a função tem de aceder a dados a que o
chamador legitimamente não tem acesso, expondo apenas um resultado controlado. Não é o caso:
o administrador que cancela uma ordem, o operador que avança de fase e o técnico que fecha
uma intervenção têm todos acesso legítimo às tabelas envolvidas. A RPC existe para garantir
**atomicidade e regra única**, não para elevar privilégios — e elevar privilégios sem
necessidade é aumentar a superfície de ataque a troco de nada.

**3. A identidade do chamador é usada dentro da função.** `auth.uid()` identifica quem está a
executar, e é assim que o histórico grava o `utilizador_id` correto, que
`aceitar_incidencia` atribui o técnico certo e que `avancar_fase_encomenda` decide se o
chamador é administrador para autorizar o avanço sem checklist. Em `SECURITY DEFINER` a
identidade continuaria disponível, mas a autorização deixaria de ser verificada pelo motor:
passaria a depender inteiramente de `IF` escritos à mão dentro da função — mais código, mais
fácil de esquecer num ramo, e sem qualquer rede de segurança por baixo.

**Onde `SECURITY DEFINER` é usado, e porquê.** O projeto usa *definer* exatamente nos casos
inversos, em que o chamador **não** deve ter acesso à tabela:

- `rastrear_encomenda(p_codigo text)` — o portal público consulta uma encomenda por código de
  rastreio sem estar autenticado. Ler a tabela `encomendas` diretamente exporia a carteira
  inteira; a função *definer* devolve apenas as colunas dessa encomenda, com os nomes de fase
  já resolvidos para linguagem de cliente.
- `obter_email_suporte()` — devolve um único valor de configuração sem dar acesso à tabela de
  definições.

O contraste é o que fundamenta a regra seguida: `SECURITY DEFINER` para **restringir** a
exposição de dados a quem não tem acesso; `SECURITY INVOKER` para operações de quem já tem
acesso e precisa apenas de garantias transacionais.

> **Limitação assumida.** A verificação de permissões de 2026-07-31 mostrou
> `relrowsecurity = false` em todas as tabelas do módulo e privilégios totais concedidos a
> `anon`. Ou seja: hoje o controlo de negócio vive nas RPC, mas nada obriga um cliente a
> passar por elas. A opção por `SECURITY INVOKER` é precisamente o que faz com que a ativação
> do RLS venha a fechar essa porta sem exigir alterações às funções — mas a ativação em si
> continua por fazer, e é a limitação de segurança que resta.

---

## 8.4.4 Tratamento de erros de negócio

As RPC sinalizam violações de regra com `RAISE EXCEPTION` e texto já redigido em português
(«A ordem está em WIP Hold», «É obrigatório indicar o motivo do cancelamento»). O driver do
Supabase converte-o numa `PostgrestException`, e o `BaseRepository` reconhece esse caso e
propaga a mensagem em vez de a substituir por texto genérico:

```dart
} on PostgrestException catch (e) {
  // As RPCs usam RAISE EXCEPTION com texto de negócio; nesse caso a mensagem
  // do servidor é melhor do que qualquer coisa que possamos compor aqui.
  throw RepositoryException(e.message, e);
}
```

O resultado é que um operador que tenta fechar uma fase de uma ordem entretanto suspensa vê a
mensagem de negócio da RPC, e não um erro do *driver*. A regra e a sua explicação vivem no
mesmo sítio.

---

## 8.4.5 Excerto comentado — `encomendas_repository.dart`

Todas as chamadas ficam agrupadas sob o cabeçalho
`// --- TRANSIÇÕES DE ESTADO (RPCs transacionais) ---`, o que separa visualmente as escritas
transacionais dos `insert`/`update` diretos usados no CRUD administrativo.

```dart
// lib/repositories/encomendas_repository.dart

// --- TRANSIÇÕES DE ESTADO (RPCs transacionais) ---

/// Avança a ordem para a fase seguinte.
///
/// [checklist] leva os pontos de controlo Poka-Yoke que o operador validou. A
/// RPC grava-os em `checklist_execucoes` na **mesma transação** que escreve o
/// histórico e avança a ordem: ou fica prova de conformidade, ou não há avanço.
Future<Map<String, dynamic>> avancarFase(
  int encomendaId, {
  List<PontoValidado> checklist = const [],
}) {
  // `guarda` é o wrapper do BaseRepository: traduz exceções e preserva a
  // mensagem de negócio que a RPC lançou com RAISE EXCEPTION.
  return guarda('avançar de fase', () async {
    final res = await client.rpc(
      'avancar_fase_encomenda',
      params: {
        'p_encomenda_id': encomendaId,
        // Serialização feita pelo modelo (PontoValidado.toJson), não aqui:
        // o formato aceite pela RPC é conhecimento do modelo.
        'p_checklist': checklist.map((p) => p.toJson()).toList(),
      },
    );
    // A RPC devolve `concluida`, `proxima_fase_id`, `proxima_fase_nome`,
    // `historico_id` e `checklist_registada`. É o servidor que diz qual é a
    // fase seguinte — o cliente já não a calcula.
    return Map<String, dynamic>.from(res as Map);
  });
}

/// Suspende a ordem criando a incidência correspondente.
Future<void> aplicarWipHold({
  required int encomendaId,
  required int reasonCodeId,
  required String descricaoOperador,
}) {
  return guarda('aplicar o WIP Hold', () async {
    // Não se envia posto_trabalho_id: a RPC deriva-o da fase atual da ordem.
    // Enviá-lo daqui era o que deixava a coluna sempre nula.
    await client.rpc('aplicar_wip_hold', params: {
      'p_encomenda_id': encomendaId,
      'p_reason_code_id': reasonCodeId,
      'p_descricao_operador': descricaoOperador,
    });
  });
}

/// Valida o line clearance e retoma a produção.
Future<void> aprovarLineClearance(int incidenciaId) {
  return guarda('aprovar o Line Clearance', () async {
    // Só o id da incidência: quem valida (auth.uid()), quando, e quanto tempo
    // a ordem esteve parada são apurados no servidor.
    await client.rpc('aprovar_line_clearance', params: {
      'p_incidencia_id': incidenciaId,
    });
  });
}

/// Cancela a ordem preservando o histórico.
Future<void> cancelar({required int encomendaId, required String motivo}) {
  return guarda('cancelar a ordem', () async {
    // Cancelamento lógico. Substituiu o DELETE físico que o ecrã executava e
    // que destruía histórico e incidências junto com a ordem (bug (e)).
    await client.rpc('cancelar_ordem', params: {
      'p_encomenda_id': encomendaId,
      'p_motivo': motivo,
    });
  });
}
```

E, no repositório do técnico, o par que cobre a intervenção:

```dart
// lib/repositories/tecnico_repository.dart

/// Assume a incidência: regista o técnico e marca o início da intervenção.
Future<void> aceitar(int incidenciaId) {
  return guarda('aceitar a incidência', () async {
    // O tecnico_id não vai como parâmetro: é auth.uid() dentro da RPC, pelo que
    // não pode ser forjado pelo cliente.
    await client.rpc(
      'aceitar_incidencia',
      params: {'p_incidencia_id': incidenciaId},
    );
  });
}

/// Fecha a intervenção com o relatório do técnico.
///
/// A ordem não retoma aqui: fica a aguardar o Line Clearance da qualidade.
Future<void> concluir({
  required int incidenciaId,
  required String diagnostico,
  required String acoes,
  String? pecas,
}) {
  return guarda('concluir a intervenção', () async {
    await client.rpc('concluir_intervencao_tecnica', params: {
      'p_incidencia_id': incidenciaId,
      'p_diagnostico': diagnostico,   // causa apurada, não o sintoma relatado
      'p_acoes': acoes,
      'p_pecas': pecas,
    });
  });
}
```

O padrão repete-se nas cinco chamadas e resume a divisão de responsabilidades da arquitetura:
o repositório **nomeia a operação, empacota os parâmetros e traduz o erro**; toda a decisão de
negócio — qual é a fase seguinte, se a transição é permitida, quem a executou, quanto tempo a
ordem esteve parada — pertence ao servidor.
