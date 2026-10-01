// Cria a ficha de um cliente e, quando pedido, a sua conta de acesso ao portal.
//
// Existe por causa de um defeito do lado do browser, não por preferência de
// arquitetura. O caminho anterior fazia `signUp` num `SupabaseClient` temporário
// dentro da aplicação, a contar com o isolamento de sessão entre instâncias.
// Esse isolamento existe em memória, mas em Flutter web todo o `GoTrueClient`
// abre um `BroadcastChannel` cuja chave deriva apenas do URL do projeto
// (gotrue `_mayStartBroadcastChannel`). O cliente temporário publicava nele o
// `SIGNED_IN` do utilizador recém-criado e o cliente partilhado adotava essa
// sessão: o administrador passava a estar autenticado como o cliente que
// acabara de criar, e o INSERT seguinte em `clientes` morria em violação de RLS.
//
// Aqui não há `signUp` nenhum. A conta nasce pela Admin API do Auth, que não
// emite evento de sessão para lado nenhum.
//
// Dois clientes, de propósito:
//
//   - `comoAdmin` usa a chave pública mais o `Authorization` de quem chamou.
//     Todas as escritas na base de dados passam por ele, com a identidade real
//     do administrador. O RLS e os triggers continuam a ser a barreira — esta
//     função não os contorna, só deixa de perder a sessão a meio.
//   - `servico` usa a service role e serve exclusivamente a Admin API do Auth
//     (criar e apagar credenciais), que nenhuma sessão de utilizador pode fazer.
//
// Se a ficha de cliente não chegar a ser gravada, a credencial criada é
// apagada. Sem essa compensação cada tentativa falhada deixava para trás um
// par `auth.users` + `utilizadores` sem ficha e queimava o email: a repetição
// passava a dar "User already registered".

import { createClient } from 'jsr:@supabase/supabase-js@2';

/// Mínimo imposto pelo Auth do Supabase; repetido aqui para a recusa chegar em
/// português e antes de se criar coisa nenhuma.
const MIN_PASSWORD = 6;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

interface Payload {
  nome?: string;
  email?: string;
  contacto?: string;
  nif?: string;
  pessoa_contacto?: string;
  morada?: string;
  ativo?: boolean;
  /// Ausente ou vazia quando o administrador cria a ficha sem acesso ao portal.
  password?: string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS });
  }
  if (req.method !== 'POST') {
    return json({ erro: 'Método não suportado.' }, 405);
  }

  const authorization = req.headers.get('Authorization');
  if (!authorization) {
    return json({ erro: 'Pedido sem sessão.' }, 401);
  }

  const url = Deno.env.get('SUPABASE_URL')!;
  const comoAdmin = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // `verify_jwt` garante que o token é válido, não que é de um administrador:
  // sem esta verificação qualquer cliente autenticado criava fichas, porque as
  // escritas que se seguem usariam a service role.
  const { data: ehAdmin, error: erroPerfil } = await comoAdmin.rpc('e_admin');
  if (erroPerfil) {
    return json({ erro: `Não foi possível confirmar o perfil: ${erroPerfil.message}` }, 500);
  }
  if (ehAdmin !== true) {
    return json({ erro: 'Apenas o Administrador pode criar clientes.' }, 403);
  }

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return json({ erro: 'Corpo do pedido inválido.' }, 400);
  }

  const nome = (payload.nome ?? '').trim();
  const email = (payload.email ?? '').trim().toLowerCase();
  const contacto = (payload.contacto ?? '').trim();
  const password = payload.password ?? '';
  const comAcesso = password.length > 0;

  if (!nome) return json({ erro: 'O nome do cliente é obrigatório.' }, 400);
  if (!contacto) return json({ erro: 'O contacto é obrigatório.' }, 400);
  if (comAcesso) {
    if (!email) return json({ erro: 'O email é obrigatório para criar acesso ao portal.' }, 400);
    if (password.length < MIN_PASSWORD) {
      return json({ erro: `A palavra-passe tem de ter pelo menos ${MIN_PASSWORD} caracteres.` }, 400);
    }
  }

  const servico = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let utilizadorId: string | null = null;

  if (comAcesso) {
    // `email_confirm` dispensa o email de confirmação: a conta é criada pelo
    // administrador, que já validou o cliente, e tem de poder entrar de imediato.
    const { data: criada, error: erroAuth } = await servico.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { nome_utilizador: nome },
    });

    if (erroAuth || !criada?.user) {
      const msg = erroAuth?.message ?? 'Não foi possível criar a conta de acesso.';
      const jaExiste = /already (been )?registered|already exists/i.test(msg);
      return json(
        { erro: jaExiste ? 'Já existe uma conta com este email.' : msg },
        jaExiste ? 409 : 400,
      );
    }
    utilizadorId = criada.user.id;

    // O trigger `trg_criar_perfil_utilizador` já criou a linha de perfil como
    // `Cliente`/`Pendente`. Promover é um UPDATE, e vai pela sessão do
    // administrador: `trg_impedir_autopromocao` recusa-o a qualquer outra
    // identidade, que é precisamente o que impede uma conta de se promover.
    //
    // O `select()` não é decorativo: um UPDATE barrado pelo RLS afeta zero
    // linhas e **não** devolve erro. Sem contar as linhas, um cliente ficava
    // `Pendente` — sem conseguir entrar — e a aplicação anunciava sucesso.
    const { data: promovidas, error: erroPromocao } = await comoAdmin
      .from('utilizadores')
      .update({ nome_utilizador: nome, perfil: 'Cliente', estado_conta: 'Ativo' })
      .eq('utilizador_id', utilizadorId)
      .select('utilizador_id');

    if (erroPromocao || !promovidas || promovidas.length === 0) {
      await servico.auth.admin.deleteUser(utilizadorId);
      return json({
        erro: erroPromocao
          ? `Não foi possível ativar a conta: ${erroPromocao.message}`
          : 'A conta foi criada mas não pôde ser ativada; nada foi gravado.',
      }, 500);
    }
  }

  // `trg_ligar_utilizador_cliente` pode já ter preenchido `utilizador_id` numa
  // ficha anterior com o mesmo email; aqui a ficha é nova, por isso a ligação
  // vai explícita.
  const { data: ficha, error: erroFicha } = await comoAdmin
    .from('clientes')
    .insert({
      nome_cliente: nome,
      email: email || null,
      contacto,
      nif: (payload.nif ?? '').trim(),
      pessoa_contacto: (payload.pessoa_contacto ?? '').trim(),
      morada: (payload.morada ?? '').trim(),
      ativo: payload.ativo ?? true,
      ...(utilizadorId ? { utilizador_id: utilizadorId } : {}),
    })
    .select('id')
    .single();

  if (erroFicha || !ficha) {
    // Compensação: a credencial não pode sobreviver à ficha que a justificava.
    // O cascade de `auth.users` limpa também a linha de `utilizadores`.
    if (utilizadorId) {
      await servico.auth.admin.deleteUser(utilizadorId);
    }
    return json(
      { erro: erroFicha?.message ?? 'Não foi possível gravar a ficha do cliente.' },
      400,
    );
  }

  return json({ id: ficha.id, utilizador_id: utilizadorId });
});

function json(corpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}
