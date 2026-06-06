# Google Gemini — Login with Google (no API key)

Use Google's **Gemini** models in Hermes by signing in with your Google
account — no API key, no billing setup. This rides hermes-agent's native
`google-gemini-cli` provider, which authenticates with **OAuth (PKCE)** and
calls Google's **Cloud Code Assist** backend (`cloudcode-pa.googleapis.com`) —
the same backend that powers Google's own `gemini-cli` free / subscription
tiers.

## How to use it

1. Launch Hermes (`./launch.sh`), open **Switch Model / Provider** (press `m`).
2. Choose **`[4] Google Gemini — login with Google (no API key)`**.
3. A browser window opens. Sign in to your Google account and approve access.
4. Back in the terminal, pick a model when prompted (default
   `gemini-3-pro-preview`).

That's it — Hermes is now pointed at Gemini.

## Models

The Cloud Code Assist channel serves these slugs (offered at the prompt):

| Model                      | Notes                                              |
|----------------------------|----------------------------------------------------|
| `gemini-3-pro-preview`     | Default. Strong general / agentic model.           |
| `gemini-3.1-pro-preview`   | Newer pro preview.                                 |
| `gemini-3-flash-preview`   | Fast; the flash slug most OAuth users can reach.   |
| `gemini-3.5-flash`         | GA-channel-gated — may 404 for non-GA accounts.    |

If a model 404s for your account tier, switch to `gemini-3-flash-preview`.

## Where the login is stored (and why it's portable)

The OAuth credential is written to:

```
data/auth/google_oauth.json      (chmod 0600)
```

Because that lives under `data/` **on the USB itself** (and `data/` is
gitignored), your Gemini login travels with the drive — plug into another
machine and you're still signed in. Nothing is written to the host's home
directory.

- **Check status:** `hermes auth status google-gemini-cli` → `logged in`
- **Sign out / re-login:** `hermes auth add google-gemini-cli` (re-runs the
  flow) or remove `data/auth/google_oauth.json`.

The access token is refreshed automatically; if Google revokes the refresh
token (`invalid_grant`) the credential file is cleared and you'll be asked to
sign in again.

## No `gemini-cli` install required

hermes-agent ships Google's **public** gemini-cli desktop OAuth client baked in
(desktop OAuth clients use PKCE, not a confidential secret), so you do **not**
need to `npm install -g @google/gemini-cli`. Power users can override the
client via `HERMES_GEMINI_CLIENT_ID` / `HERMES_GEMINI_CLIENT_SECRET` in
`data/.env`.

## ⚠️ Google policy note

Google's policy treats using the gemini-cli OAuth client with **third-party**
software as a Terms-of-Service gray-area. hermes-agent shows an upfront warning
before sign-in. This is an account-level decision — use it with your own
account at your discretion. If you'd rather stay fully within Google's
supported terms, use **`[5] Google Gemini — cloud (API key)`** with a key from
Google AI Studio instead.

## Troubleshooting

- **Browser didn't open** — the terminal prints the sign-in URL; paste it into
  any browser on the same machine (the callback returns to
  `http://127.0.0.1:8085`).
- **Headless / SSH** — the flow auto-falls back to "paste mode": open the URL
  elsewhere, then paste the redirected URL (or just the `code=` value) back.
- **`not logged in` after switching** — re-run option `[4]`, or
  `hermes auth add google-gemini-cli` directly.
