import type { EngineInterface, Register, SessionContextUsage, SessionRateLimit } from 'claude-code'

const LABELS: Record<string, string> = {
  five_hour: '5h',
  seven_day: 'Week',
  spend_limit: 'Spend',
}
const WARN_AT = [80, 90]

type Reading = { limits: SessionRateLimit[]; context?: SessionContextUsage }

function label(kind: string) {
  return LABELS[kind] ?? kind
}

function countdown(resetsAt: string | undefined, now: number) {
  if (resetsAt === undefined) return ''
  const minutes = Math.max(0, Math.round((Date.parse(resetsAt) - now) / 60000))
  const days = Math.floor(minutes / 1440)
  const hours = Math.floor((minutes % 1440) / 60)
  const left = days > 0 ? `${days}d ${hours}h` : hours > 0 ? `${hours}h ${minutes % 60}m` : `${minutes}m`

  return ` (resets in ${left})`
}

async function draw($: EngineInterface, reading: Reading) {
  const now = await $.clock.now()
  const parts = reading.limits.map(
    l => `${label(l.kind)} ${Math.round(l.percentUsed)}%${countdown(l.resetsAt, now)}`,
  )

  if (reading.context?.percent !== undefined) {
    parts.push(`Context ${reading.context.percent}%`)
  }

  $.ui.status(parts.length > 0 ? parts.join('  ·  ') : 'Usage: shows after the first reply')
}

export const register: Register = on => {
  const reading: Reading = { limits: [] }
  const warned = new Set<string>()

  on('session.start', async ($, e, next) => {
    const result = await next(e)
    const usage = await $.session.usage()
    reading.limits = usage.rateLimits
    reading.context = usage.context
    await draw($, reading)
    $.clock.every(60_000, () => draw($, reading))

    return result
  })

  on('session.measure', async ($, e, next) => {
    reading.limits = e.rateLimits
    reading.context = e.context
    await draw($, reading)

    for (const l of reading.limits) {
      for (const at of WARN_AT) {
        const key = `${l.kind}:${l.resetsAt ?? ''}:${at}`
        if (l.percentUsed >= at && !warned.has(key)) {
          warned.add(key)
          $.ui.toast(`${label(l.kind)} usage is at ${Math.round(l.percentUsed)}%`)
        }
      }
    }

    return next(e)
  })
}
