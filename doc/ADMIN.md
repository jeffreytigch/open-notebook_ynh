open-notebook is an open-source research assistant (inspired by Google NotebookLM).
It indexes your sources, lets you chat with them, generates notes, insights and
podcasts.

## Access

Access is controlled by YunoHost: only members of the group allowed on the app's
permission can reach it. In addition, the open-notebook API is protected by a
shared **application password** (also used to log in to the web interface).

The current application password is:

    __OPEN_NOTEBOOK_PASSWORD__

open-notebook has no accounts of its own, so the user name is not checked. Change
the password from the app's **Configuration** tab in the YunoHost admin interface
(the value is masked there: the field above is the readable copy). Users need it
to log in to the app itself, on top of their YunoHost account.

The two layers are independent: if you allow **visitors** on the app's
permission, YunoHost stops gating the URL and only the application password
protects the app; if you restrict the permission to a group, both apply.

Because open-notebook has no per-user accounts of its own, every allowed user
shares the same workspace and the same password. If you need separate users,
install a second instance.

Repeated failures of that password are rate-limited by a **fail2ban jail**: an
IP that fails the app password 20 times in 10 minutes is temporarily blocked.
The threshold is deliberately generous, so a browser holding an out-of-date
password cannot lock a legitimate user out.

## Capabilities and dependencies

open-notebook talks to AI providers, but **does not ship one**. Configure one
after installation from the app: **Settings → Models**. You can use a cloud
provider (an API key for OpenAI, Anthropic, Google, Mistral, OpenRouter…) or a
local one (Ollama, LM Studio, or any OpenAI-compatible endpoint).

* Sources do not need any AI provider to be *imported*, but text extraction,
  chat, insights and podcasts require at least a language model and an
  embedding model.
* Audio/video transcription and podcast generation require **ffmpeg**, which is
  installed with the package.
* The optional **Docling** and **Crawl4AI** runtimes can be enabled from the
  config panel. They are heavier (extra Python packages / a headless browser)
  and are disabled by default.

## Data and backups

All persistent data (sources, notebooks, notes, chat history, podcasts, the
database) lives in the app's data directory and is included in YunoHost backups
and restores.

## External services / privacy

If you configure a cloud AI provider, the text of your sources and your
questions are sent to that provider. Use a local provider if your documents must
stay on the server.
