# Claude Usage Counter

A Claude Code mod that keeps your plan usage on screen, in the terminal and in the Claude desktop app's Code tab:

```
5h 23% (resets in 2h 10m)  ·  Week 41% (resets in 3d 4h)  ·  Context 34%
```

- **5h** and **Week**: your 5-hour session and weekly limits, with countdowns to their resets (refreshed every minute)
- **Context**: how full the current conversation's context window is
- A toast when either limit passes 80% and again at 90%

The figures come from the rate-limit data Claude's own replies carry, so they appear after the first reply of a session. Off a Claude subscription (API key billing) there are no rate-limit windows to show.

Inspired by [Claude Counter](https://github.com/she-llac/claude-counter), the browser extension that does the same for claude.ai.

## Install

At the prompt of a Claude Code terminal session:

```
/plugin install usage-counter --marketplace Hadi5yed/claude-usage-counter
```

Answer `y` to add the marketplace, then pick a scope (user scope loads it in every session).

From a shell:

```bash
claude plugin install usage-counter --marketplace Hadi5yed/claude-usage-counter
```

In the Claude desktop app, where `/plugin` does not run: click **+** next to the prompt box, then **Plugins**, **Add marketplace** with `Hadi5yed/claude-usage-counter`, then **Add plugin**.

## Privacy

Everything stays local: the mod reads the usage figures Claude Code already has and makes no network requests.

## License

MIT
