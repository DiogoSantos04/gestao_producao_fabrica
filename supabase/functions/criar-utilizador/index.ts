// Cria a conta de um membro do pessoal interno, com o perfil que o
// administrador escolher.
//
// Substitui o caminho anterior (`UtilizadoresRepository._criarCredencial`), que
// fazia `signUp` num `SupabaseClient` temporário a contar com o isolamento de
// sessão entre instâncias. Esse isolamento existe em memória, mas em Flutter web
// todo o `GoTrueClient` abre um `BroadcastChannel` cuja chave deriva apenas do
// URL do projeto (gotrue `_mayStartBroadcastChannel`): o cliente temporário
// publicava nele o `SIGNED_IN` da conta nova e o cliente partilhado adotava essa
// sessão. O administrador ficava autenticado como a conta que acabara de criar.
// Enquanto isto só criava Operadores o estrago passava despercebido; a escolher
// o perfil, qualquer criação derrubaria a sessão.
//
// Aqui não há `signUp`: a conta nasce pela Admin API do Auth, que não emite
// evento de sessão para lado nenhum.
//
// Dois clientes, de propósito — o mesmo desenho de `criar-cliente`, deixado
// autónomo em vez de partilhado, para que cada função possa ser lida e
// reimplantada sem arrastar a outra:
//
//   - `comoAdmin` leva a chave pública mais o `Authorization` de quem chamou.
//     A promoção do perfil passa por ele, com a identidade real do
//     administrador: o RLS e os triggers continuam a ser a barreira.
//   - `servico` leva a service role e serve exclusivamente a Admin API do Auth,
//     que nenhuma sessão de utilizador pode usar.
//
// A promoção **não** pode ir pela service role: `trg_impedir_autopromocao` só
// deixa passar alterações de `perfil`/`estado_conta` quando `e_admin()` é
// verdadeiro, e sem `auth.uid()` é falso.

import { createClient } from 'jsr:@supabase/supabase-js@2';

/// Mínimo imposto pelo Auth do Supabase; repetido aqui para a recusa chegar em
/// português e antes de se criar coisa nenhuma.
const MIN_PASSWORD = 6;

/// Perfis que esta função aceita, nos valores exatos da coluna `perfil`.
///
/// `Cliente` fica de fora de propósito: uma conta de cliente sem ficha em
/// `clientes` não aparece na carteira e não tem com que se ligar — foi assim que
/// nasceram as contas órfãs. O caminho dos clientes é a Edge Function
/// `criar-cliente`, que cria conta e ficha juntas.
const PERFIS = ['Admin', 'Operador', 'Tecnico'] as const;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

interface Payload {
  nome?: string;
  email?: string;
  password?: string;
  perfil?: string;
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

  // `verify_jwt` garante que o token é válido, não que é de um administrador.
  // Sem esta verificação qualquer conta autenticada criaria contas de pessoal,
  // porque a credencial é criada pela service role.
  const { data: ehAdmin, error: erroPerfil } = await comoAdmin.rpc('e_admin');
  if (erroPerfil) {
    return json({ erro: `Não foi possível confirmar o perfil: ${erroPerfil.message}` }, 500);
  }
  if (ehAdmin !== true) {
    return json({ erro: 'Apenas o Administrador pode criar utilizadores.' }, 403);
  }

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return json({ erro: 'Corpo do pedido inválido.' }, 400);
  }

  const nome = (payload.nome ?? '').trim();
  const email = (payload.email ?? '').trim().toLowerCase();
  const password = payload.password ?? '';
  const perfil = (payload.perfil ?? '').trim();

  if (!nome) return json({ erro: 'O nome é obrigatório.' }, 400);
  if (!email) return json({ erro: 'O email é obrigatório.' }, 400);
  if (password.length < MIN_PASSWORD) {
    return json({ erro: `A palavra-passe tem de ter pelo menos ${MIN_PASSWORD} caracteres.` }, 400);
  }
  if (perfil === 'Cliente') {
    return json({
      erro: 'As contas de cliente criam-se no ecrã de Clientes, para nascerem já com ficha.',
    }, 400);
  }
  if (!(PERFIS as readonly string[]).includes(perfil)) {
    return json({ erro: 'Perfil de acesso inválido.' }, 400);
  }

  const servico = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // `email_confirm` dispensa o email de confirmação: a conta é criada pelo
  // administrador e tem de poder entrar de imediato com as credenciais que ele
  // entrega em mão.
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
  const utilizadorId = criada.user.id;

  // O trigger `trg_criar_perfil_utilizador` já criou a linha de perfil, como
  // `Cliente`/`Pendente` — é o que `trg_forcar_registo_pendente` impõe a quem
  // não é administrador. Dar-lhe o papel final é um UPDATE, pela sessão do
  // administrador.
  //
  // O `select()` não é decorativo: um UPDATE barrado pelo RLS afeta zero linhas
  // e **não** devolve erro. Sem contar as linhas, a conta ficava `Pendente` —
  // sem conseguir entrar — e a aplicação anunciava sucesso.
  const { data: promovidas, error: erroPromocao } = await comoAdmin
    .from('utilizadores')
    .update({ nome_utilizador: nome, perfil, estado_conta: 'Ativo' })
    .eq('utilizador_id', utilizadorId)
    .select('utilizador_id');

  if (erroPromocao || !promovidas || promovidas.length === 0) {
    // Compensação: uma credencial que não chegou ao perfil certo não pode
    // sobreviver, ou fica a queimar o email e a repetição dá "User already
    // registered". O cascade de `auth.users` limpa também `utilizadores`.
    await servico.auth.admin.deleteUser(utilizadorId);
    return json({
      erro: erroPromocao
        ? `Não foi possível ativar a conta: ${erroPromocao.message}`
        : 'A conta foi criada mas não pôde ser ativada; nada foi gravado.',
    }, 500);
  }

  return json({ utilizador_id: utilizadorId, perfil });
});

function json(corpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}
