// Reference sketch of @agent-kit/react: chat with inline approval cards. @ai-sdk/react@4 (React 18 or 19).
import { useChat } from '@ai-sdk/react'
import { DefaultChatTransport } from 'ai'
import { useRef, useState } from 'react'

export function AgentChat({ agentId, accessToken }: { agentId: string; accessToken: string }) {
  const [input, setInput] = useState('')
  const conversationId = useRef<string | undefined>(undefined)
  const { messages, sendMessage, status } = useChat({
    transport: new DefaultChatTransport({
      api: `/api/agents/${agentId}/turn`,
      headers: { Authorization: `Bearer ${accessToken}` },
      // Send only the new text; the server owns the history (see the turn route).
      prepareSendMessagesRequest: ({ messages }) => {
        const last = messages[messages.length - 1]
        const text = last?.parts.map(p => (p.type === 'text' ? p.text : '')).join('') ?? ''
        return { body: { text, conversationId: conversationId.current } }
      },
      fetch: async (url, init) => {
        const res = await fetch(url, init)
        conversationId.current = res.headers.get('x-conversation-id') ?? conversationId.current
        return res
      },
    }),
  })

  return (
    <div className="ak-chat">
      {messages.map(m => (
        <div key={m.id} className={`ak-msg ak-msg--${m.role}`}>
          {m.parts.map((p, i) => {
            if (p.type === 'text') return <p key={i}>{p.text}</p>
            if (p.type.startsWith('tool-') && 'approval' in p && p.state === 'approval-requested')
              return <ApprovalCard key={i} part={p} accessToken={accessToken} />
            return null
          })}
        </div>
      ))}
      <form onSubmit={e => { e.preventDefault(); sendMessage({ text: input }); setInput('') }}>
        <input id="ak-input" value={input} onChange={e => setInput(e.target.value)} disabled={status !== 'ready'} placeholder="Ask this agent" />
      </form>
    </div>
  )
}

// The card shows the exact args that will run. Approve/Decline go to the server; the client never edits an action.
function ApprovalCard({ part, accessToken }: { part: any; accessToken: string }) {
  const [state, setState] = useState<'idle' | 'sending' | 'done'>('idle')
  const decide = async (approved: boolean) => {
    setState('sending')
    await fetch(`/api/agents/actions/${part.approval.id}/decide`, {
      method: 'POST', headers: { Authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ approved }),
    })
    setState('done')
  }
  return (
    <div className="ak-card" role="group" aria-label="Approval needed">
      <strong>{part.type.replace('tool-', '').replaceAll('_', ' ')}</strong>
      <dl>{Object.entries(part.input ?? {}).map(([k, v]) => <div key={k}><dt>{k}</dt><dd>{String(v)}</dd></div>)}</dl>
      <button onClick={() => decide(false)} disabled={state !== 'idle'}>Decline</button>
      <button onClick={() => decide(true)} disabled={state !== 'idle'}>Approve</button>
    </div>
  )
}
