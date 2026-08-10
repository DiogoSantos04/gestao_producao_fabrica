// Consome a fila `fila_emails` e entrega as mensagens através do Resend.
//
// Vive fora da base de dados de propósito. O trigger que enfileira faz apenas
// um INSERT local, dentro da transação que avança ou cancela a ordem; se a
// entrega fosse feita aí, uma falha de rede do fornecedor de email bloquearia o
// operador no chão de fábrica. Aqui, uma falha custa um atraso e uma nova
// tentativa.
//
// Invocada periodicamente (pg_cron). Não devolve os corpos das mensagens — só
// contagens — porque a resposta pode ficar em registos de execução.

import { createClient } from 'jsr:@supabase/supabase-js@2';

/// Quantas mensagens processa por invocação.
///
/// Limitado para a função terminar dentro do tempo máximo de execução mesmo
/// quando a fila acumulou: o que sobra fica para a invocação seguinte, que é
/// daí a um minuto.
const LOTE = 20;

/// Ao fim de quantas tentativas se desiste de uma mensagem.
///
/// Sem teto, um endereço permanentemente inválido seria retentado para sempre e
/// bloquearia a fila à frente das mensagens válidas.
const MAX_TENTATIVAS = 3;

const REMETENTE = Deno.env.get('EMAIL_REMETENTE') ?? 'onboarding@resend.dev';

Deno.serve(async () => {
  const chaveResend = Deno.env.get('RESEND_API_KEY');
  if (!chaveResend) {
    return json({ erro: 'RESEND_API_KEY não está configurada nos secrets.' }, 500);
  }

  // Service role: a função tem de ler e escrever a fila, que está fechada a
  // toda a gente exceto ao administrador. Não há sessão de utilizador aqui.
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: pendentes, error: erroLeitura } = await supabase
    .from('fila_emails')
    .select('id, destinatario, assunto, corpo, tentativas')
    .eq('estado', 'pendente')
    .order('created_at', { ascending: true })
    .limit(LOTE);

  if (erroLeitura) {
    return json({ erro: `Não foi possível ler a fila: ${erroLeitura.message}` }, 500);
  }
  if (!pendentes || pendentes.length === 0) {
    return json({ processados: 0, enviados: 0, falhados: 0 });
  }

  let enviados = 0;
  let falhados = 0;

  for (const msg of pendentes) {
    const tentativas = (msg.tentativas ?? 0) + 1;

    try {
      const resposta = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${chaveResend}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: REMETENTE,
          to: [msg.destinatario],
          subject: msg.assunto,
          text: msg.corpo,
        }),
      });

      if (resposta.ok) {
        await supabase
          .from('fila_emails')
          .update({ estado: 'enviado', enviado_em: new Date().toISOString(), tentativas, ultimo_erro: null })
          .eq('id', msg.id);
        enviados++;
        continue;
      }

      // O texto do erro do Resend é guardado tal e qual: em modo de teste, a
      // recusa por destinatário não autorizado é a causa mais provável, e sem a
      // mensagem original isso é indistinguível de uma chave errada.
      const detalhe = await resposta.text();
      await registarFalha(supabase, msg.id, tentativas, `HTTP ${resposta.status}: ${detalhe.slice(0, 500)}`);
      falhados++;
    } catch (e) {
      await registarFalha(supabase, msg.id, tentativas, String(e).slice(0, 500));
      falhados++;
    }
  }

  return json({ processados: pendentes.length, enviados, falhados });
});

async function registarFalha(
  supabase: ReturnType<typeof createClient>,
  id: number,
  tentativas: number,
  erro: string,
) {
  await supabase
    .from('fila_emails')
    .update({
      // Só desiste ao fim do teto; até lá continua pendente para a invocação
      // seguinte voltar a tentar.
      estado: tentativas >= MAX_TENTATIVAS ? 'falhado' : 'pendente',
      tentativas,
      ultimo_erro: erro,
    })
    .eq('id', id);
}

function json(corpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
