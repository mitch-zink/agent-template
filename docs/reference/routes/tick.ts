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

type Db = ReturnType<typeof admin>

// In-flight runs reserve a full per-run budget: cost_usd is written only when the run finishes,
// so a count of finished cost alone would let a burst of routine runs start before any of them bill.
async function dailyBudgetClosed(db: Db, agentId: string, runBudget: number, dayBudget: number) {
  if (!Number.isFinite(runBudget) || !Number.isFinite(dayBudget) || runBudget <= 0 || dayBudget <= 0) return true
  const now = new Date()
  const dayStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())).toISOString()
  const { data: rows, error } = await db.from('agent_runs').select('status, cost_usd').eq('agent_id', agentId).gte('started_at', dayStart)
  if (error) throw new Error('budget read failed')
  const used = (rows ?? []).reduce((sum, row) => {
    if (row.status === 'running' || row.status === 'awaiting_approval') return sum + runBudget
    const cost = Number(row.cost_usd ?? 0)
    return sum + (Number.isFinite(cost) ? cost : runBudget)
  }, 0)
  return used >= dayBudget
}

// POST /api/agents/tick
export async function tick(req: Request) {
  if (!authorized(req)) return new Response('no', { status: 401 })
  const db = admin()
  // One due routine per owner, window clamped to 25. See agent_kit_claim_due_routines.
  const { data: due } = await db.rpc('agent_kit_claim_due_routines', { max_n: 25 })

  const fired: string[] = []
  for (const r of due ?? []) {
    try {
      const period = new Date(r.next_run_at)
      const { data: owner, error: ownerErr } = await db.from('agents').select('owner_id, current_version_id').eq('id', r.agent_id).single()
      if (ownerErr || !owner?.current_version_id) continue

      const { data: version, error: verErr } = await db.from('agent_versions')
        .select('budget_run_usd, budget_day_usd').eq('id', owner.current_version_id).single()
      if (verErr || !version) continue
      const closed = await dailyBudgetClosed(db, r.agent_id, Number(version.budget_run_usd), Number(version.budget_day_usd))

      const next = new Cron(r.cron, { timezone: r.timezone }).nextRun(new Date())
      await db.from('agent_routines').update({ next_run_at: next?.toISOString() ?? null }).eq('id', r.id)

      // The unique index on (routine_id, period_start) makes a duplicate tick a no-op.
      const { data: run, error } = await db.from('agent_runs').insert({
        agent_id: r.agent_id, version_id: owner.current_version_id, user_id: owner.owner_id,
        trigger: 'routine', routine_id: r.id, period_start: period.toISOString(),
        ...(closed ? { status: 'budget_stopped', finished_at: new Date().toISOString() } : {}),
      }).select('id').single()
      if (error || closed || !run) continue

      // Fan out only under budget: each call is a host-billed Gateway run.
      void fetch(new URL(`/api/agents/run-routine/${run.id}`, req.url), {
        method: 'POST', headers: { 'x-agent-kit-secret': process.env.AGENT_KIT_TICK_SECRET! },
      })
      fired.push(run.id)
    } catch {
      // One bad cron, timezone, or read must not drop the other tenants in this batch.
      continue
    }
  }
  return Response.json({ fired })
}
