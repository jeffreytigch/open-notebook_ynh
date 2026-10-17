open-notebook runs four services (a SurrealDB database, the API, a background
worker and the web frontend) natively. No Docker is used.

## Requirements

* A YunoHost server with **at least 2 GB of RAM** (4 GB or more is recommended,
  especially if you plan to use local AI models).
* Enough disk space: the package itself is small, but sources, models and
  generated podcasts can grow. Plan for at least a few GB.

## Before installing

* Choose the domain and the path where open-notebook will be reachable. It can
  live on a dedicated sub-domain or in a sub-path of an existing one.
* Decide who may access it through the YunoHost permission system.
* Have an AI provider ready (an API key, or a local model server you can reach).
  You will configure it *after* installation, inside the app.

::: warning
Installation builds the web frontend and a Python virtual environment on the
server, so it can take **several minutes**. Do not interrupt it.
:::
