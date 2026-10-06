// Reference sketch of @agent-kit/vercel: framework-free (Request) => Response handlers.
// A host mounts them from api/agents/[...path].ts. maxDuration 800 on Vercel Pro.
import { createClient } from '@supabase/supabase-js'
import type { ModelMessage } from 'ai'
import { runTurn, type Host, type User } from '../core/run-turn.js'

const admin = () => createClient(process.env.SUPABASE_URL!, process.env.SUPABASE_SECRET_KEY!, { auth: { persistSession: false } })

async function userFrom(req: Request): Promise<User | null> {
  const token = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
  if (!token) return null
  const { data } = await admin().auth.getClaims(token) // verifies against the project's JWKS
  return data?.claims ? { id: data.claims.sub, email: String(data.claims.email), accessToken: token } : null
}

// The host app's three answers. Defaults shown: forward the user's own token; trust the host MCP's own checks.
export const defaultHost = (): Host => ({
  servers: { app: { id: 'app', url: process.env.APP_MCP_URL! } },
  getToolToken: async (user) => user.accessToken,
  canUseTool: async () => true,
  db: admin(),
})

// POST /api/agents/:id/turn   body: { messages: ModelMessage[] }
export async function turn(req: Request, agentId: string, host = defaultHost()) {
  const user = await userFrom(req)
  if (!user) return new Response('sign in', { status: 401 })

  // Read the agent as the user, so RLS decides visibility.
  const asUser = createClient(process.env.SUPABASE_URL!, process.env.SUPABASE_PUBLISHABLE_KEY!, {
    global: { headers: { Authorization: `Bearer ${user.accessToken}` } }, auth: { persistSession: false },
  })
  const { data: agent } = await asUser.from('agents').select('id, current_version_id, agent_versions!agents_current_version_fk(*)').eq('id', agentId).single()
  if (!agent) return new Response('not found', { status: 404 })

  const { messages } = (await req.json()) as { messages: ModelMessage[] }
  const { data: run } = await host.db.from('agent_runs')
    .insert({ agent_id: agent.id, version_id: agent.current_version_id, user_id: user.id, trigger: 'chat' })
    .select('id').single()
  const memory = await loadMemory(host, agent.id, user.id)

  const result = await runTurn({ version: agent.agent_versions as never, user, runId: run!.id, messages, host, memory })
  return result.toUIMessageStreamResponse()
}

// POST /api/agents/actions/:approvalId/decide   body: { approved: boolean }
export async function decide(req: Request, approvalId: string, host = defaultHost()) {
  const user = await userFrom(req)
  if (!user) return new Response('sign in', { status: 401 })
  const { approved } = (await req.json()) as { approved: boolean }

  // Ownership first, then a conditional update: a non-owner must not be able to move someone else's action,
  // and the status filter makes a double click (or two tabs) decide only once.
  const { data: owned } = await host.db.from('agent_actions')
    .select('id, approval_id, agent_runs!inner(id, user_id, agent_id, version_id, messages)')
    .eq('approval_id', approvalId).eq('agent_runs.user_id', user.id).single()
  if (!owned) return new Response('not found', { status: 404 })

  const { data: action } = await host.db.from('agent_actions')
    .update({ status: approved ? 'approved' : 'declined', decided_by: user.id, decided_at: new Date().toISOString() })
    .eq('id', owned.id).eq('status', 'pending').gt('expires_at', new Date().toISOString())
    .select('id').single()
  if (!action) return new Response('already decided or expired', { status: 409 })

  // Resume: the stored messages already hold the original tool call, so the SDK executes those exact args.
  const run = owned.agent_runs as unknown as { id: string; user_id: string; agent_id: string; version_id: string; messages: ModelMessage[] }
  const messages: ModelMessage[] = [...run.messages, {
    role: 'tool', content: [{ type: 'tool-approval-response', approvalId: owned.approval_id, approved }],
  }]
  const { data: version } = await host.db.from('agent_versions').select('*').eq('id', run.version_id).single()
  const memory = await loadMemory(host, run.agent_id, user.id)
  const result = await runTurn({ version: version!, user, runId: run.id, messages, host, memory })
  return result.toUIMessageStreamResponse()
}

async function loadMemory(host: Host, agentId: string, userId: string) {
  const { data } = await host.db.from('agent_memory').select('key, value').eq('agent_id', agentId).eq('user_id', userId)
  const text = (data ?? []).map(m => `- ${m.key}: ${m.value}`).join('\n')
  return text ? `What you remember about this user:\n${text}`.slice(0, 2000) : ''
}
