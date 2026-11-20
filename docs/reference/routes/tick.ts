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

// Spend is aggregated in SQL (agent_kit_agent_spend_today). Selecting the day's rows and summing
// them here would stop at PostgREST's silent 1000-row cap and could fan out after the cap was hit.
async function dailyBudgetClosed(db: Db, agentId: string, runBudget: number, dayBudget: number) {
  if (!Number.isFinite(runBudget) || !Number.isFinite(dayBudget) || runBudget <= 0 || dayBudget <= 0) return true
  const { data, error } = await db.rpc('agent_kit_agent_spend_today', { p_agent: agentId, p_run_budget: runBudget })
  if (error) throw new Error('budget read failed')
  const spent = Number(data)
  if (!Number.isFinite(spent)) return true
  return spent >= dayBudget
}

// A row we cannot fire must leave the due set. Left at its old next_run_at, it stays the oldest
// bucket and a handful of such owners can hold every claim slot. disable is for a cron/timezone
// that will throw again on every tick; retry is a backoff for a blip.
async function releaseRoutine(db: Db, id: string, mode: 'retry' | 'disable') {
  const hours = mode === 'disable' ? 24 : 1
  await db.from('agent_routines').update({
    next_run_at: new Date(Date.now() + hours * 60 * 60 * 1000).toISOString(),
    ...(mode === 'disable' ? { enabled: false } : {}),
  }).eq('id', id)
}

// POST /api/agents/tick
export async function tick(req: Request) {
  if (!authorized(req)) return new Response('no', { status: 401 })
  const db = admin()
  // One due routine per owner, window clamped to 25. See agent_kit_claim_due_routines.
  const { data: due } = await db.rpc('agent_kit_claim_due_routines', { max_n: 25 })

  const fired: string[] = []
  for (const r of due ?? []) {
    let scheduled = false
    try {
      const period = new Date(r.next_run_at)
      const { data: owner, error: ownerErr } = await db.from('agents').select('owner_id, current_version_id').eq('id', r.agent_id).single()
      if (ownerErr || !owner) {
        await releaseRoutine(db, r.id, 'retry')
        continue
      }
      if (!owner.current_version_id) {
        await releaseRoutine(db, r.id, 'retry')
        continue
      }

      const { data: version, error: verErr } = await db.from('agent_versions')
        .select('budget_run_usd, budget_day_usd').eq('id', owner.current_version_id).single()
      if (verErr || !version) {
        await releaseRoutine(db, r.id, 'retry')
        continue
      }
      const closed = await dailyBudgetClosed(db, r.agent_id, Number(version.budget_run_usd), Number(version.budget_day_usd))

      let nextIso: string | null
      try {
        nextIso = new Cron(r.cron, { timezone: r.timezone }).nextRun(new Date())?.toISOString() ?? null
      } catch {
        await releaseRoutine(db, r.id, 'disable')
        continue
      }
      await db.from('agent_routines').update({ next_run_at: nextIso }).eq('id', r.id)
      scheduled = true

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
      // One bad read must not drop the other tenants. If this row was not rescheduled, push it
      // forward so it cannot sit at the front of the next claim.
      if (!scheduled) {
        try { await releaseRoutine(db, r.id, 'retry') } catch { /* failing closed is enough */ }
      }
    }
  }
  return Response.json({ fired })
}
