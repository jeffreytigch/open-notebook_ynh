open-notebook is installed.

## Log in

Open the app and log in with the **application password** generated during this
installation:

    __OPEN_NOTEBOOK_PASSWORD__

open-notebook has no user accounts of its own: the user name is not checked, the
single shared password is what protects the workspace. Note it down now, or read
it back later from the app's **Documentation** tab in the YunoHost admin
interface (it is masked in the Configuration tab, where you can also change it).

## Next steps

1. Go to **Settings → Models** and add an AI provider (an API key, or the URL of
   a local model server such as Ollama). Add at least a language model and an
   embedding model so that sources can be processed and chats can work.
2. Create a notebook, add a source (document, web page, audio or video) and watch
   it being processed by the background worker.

If a source stays "queued" for a long time, the worker or the AI provider is not
reachable; check the logs from the YunoHost admin interface.
