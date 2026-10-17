open-notebook is installed.

## Next steps

1. Open the app and log in with the **application password**. You can read it
   from the app's **config panel** in the YunoHost admin interface.
2. Go to **Settings → Models** and add an AI provider (an API key, or the URL of
   a local model server such as Ollama). Add at least a language model and an
   embedding model so that sources can be processed and chats can work.
3. Create a notebook, add a source (document, web page, audio or video) and watch
   it being processed by the background worker.

If a source stays "queued" for a long time, the worker or the AI provider is not
reachable; check the logs from the YunoHost admin interface.
