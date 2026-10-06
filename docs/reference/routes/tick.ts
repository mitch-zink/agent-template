// Reference sketch: the scheduler. Supabase Cron POSTs here every minute (see schema.sql).
import { timingSafeEqual } from 'node:crypto'
import { Cron } from 'croner'
import { createClient } from '@supabase/supabase-js'

const admin = () => createClient(process.env.SUPABASE_URL!, process.env.SUPABASE_SECRET_KEY!, { auth: { persistSession: false } })

function authorized(req: Request) {
  const got = Buffer.from(req.headers.get('x-agent-kit-secret') ?? '')
  const want = Buffer.from(process.env.AGENT_KIT_TICK_SECRET ?? '')
  return want.length > 0 && got.length === want.length && timingSafeEqual(got, want)
}

// POST /api/agents/tick
export async function tick(req: Request) {
  if (!authorized(req)) return new Response('no', { status: 401 })
  const db = admin()
  const { data: due } = await db.rpc('agent_kit_claim_due_routines', { max_n: 25 })

  const fired: string[] = []
  for (const r of due ?? []) {
    const period = new Date(r.next_run_at)
    const { data: owner } = await db.from('agents').select('owner_id, current_version_id').eq('id', r.agent_id).single()

    // The unique index on (routine_id, period_start) makes a duplicate tick a no-op.
    const { data: run, error } = await db.from('agent_runs').insert({
      agent_id: r.agent_id, version_id: owner!.current_version_id, user_id: owner!.owner_id,
      trigger: 'routine', routine_id: r.id, period_start: period.toISOString(),
    }).select('id').single()

    const next = new Cron(r.cron, { timezone: r.timezone }).nextRun(new Date())
    await db.from('agent_routines').update({ next_run_at: next?.toISOString() ?? null }).eq('id', r.id)
    if (error) continue // already fired for this period

    // Fan out: each run gets its own function invocation (and its own 800s).
    void fetch(new URL(`/api/agents/run-routine/${run!.id}`, req.url), {
      method: 'POST', headers: { 'x-agent-kit-secret': process.env.AGENT_KIT_TICK_SECRET! },
    })
    fired.push(run!.id)
  }
  return Response.json({ fired })
}
