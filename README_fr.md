# open-notebook pour YunoHost

Un paquet d'application [YunoHost](https://yunohost.org/) pour
[**open-notebook**](https://github.com/lfnovo/open-notebook) — un assistant de
recherche auto-hébergé et open source (une alternative à « Google NotebookLM ») :
importez des documents, des pages web, de l'audio et de la vidéo, puis discutez
avec eux, générez des notes, des analyses et des podcasts.

> **État : implémenté, pas encore éprouvé.** Le paquet complet (manifest,
> scripts, gabarits de configuration, panneau de configuration, CI) est écrit et
> passe les vérifications statiques. Il **n'a pas encore été vérifié sur une
> instance YunoHost réelle** et **n'est pas encore dans le catalogue YunoHost**.
> Voir [`docs/open-questions.md`](docs/open-questions.md) pour ce qu'il reste à
> valider.

## Pourquoi ce paquet existe

Les méthodes d'installation officielles d'open-notebook supposent toutes
**Docker Compose** (ou une base de données hébergée par Docker). Ce paquet
l'installe **nativement, sans Docker**, ce qui lui permet de s'intégrer à tout
l'écosystème YunoHost : accès contrôlé par les permissions, sauvegarde et
restauration, mise à jour, `change_url`, la visionneuse de journaux de
l'administration et la boutique d'applications.

### Comment cela fonctionne

Quatre services systemd natifs, tous détenus par un utilisateur système dédié :

| Service | Rôle | Écoute sur |
|---|---|---|
| `__APP__-surreal` | Base de données SurrealDB (RocksDB) | `127.0.0.1` |
| `__APP__-api` | Backend FastAPI (migrations, API REST) | `127.0.0.1` |
| `__APP__-worker` | Tâches d'arrière-plan (indexation, embeddings, podcasts) | — |
| `__APP__` | Frontend Next.js | `127.0.0.1` |

nginx joue le rôle de proxy inverse pour le frontend et l'API (`/api/`), avec la
mise en mémoire tampon désactivée afin que les réponses du chat/de « Ask »
puissent être diffusées en flux (Server-Sent Events). Toutes les données
persistantes (base de données, fichiers importés, podcasts, historique des
conversations) résident dans le répertoire de données de l'application et sont
incluses dans les sauvegardes YunoHost.

## Prérequis

* YunoHost 12 (Debian Bookworm), `amd64` ou `arm64`.
* **≥ 2 Go de RAM** (4 Go ou plus recommandé).
* Un **fournisseur d'IA** (une clé d'API, ou un serveur de modèles local comme
  Ollama) — configuré **dans l'application** après l'installation. open-notebook
  ne fournit aucun modèle.

## Contrôle d'accès

L'accès est contrôlé par le système de permissions de YunoHost, **et**
l'application conserve son propre mot de passe partagé (consultable et
modifiable depuis le panneau de configuration). open-notebook n'a pas de comptes
utilisateurs individuels : tous les utilisateurs autorisés partagent un seul
espace de travail. Installez une seconde instance si vous avez besoin de
séparer les usages.

## Installation (depuis ce dépôt)

Une fois publié :

```bash
yunohost app install https://github.com/<owner>/open-notebook_ynh
```

Pendant le développement, installez depuis une copie locale :

```bash
yunohost app install /path/to/open-notebook_ynh
```

## Fonctionnalités optionnelles

Le panneau de configuration peut activer deux environnements optionnels plus
lourds (désactivés par défaut) : **Docling** (conversion avancée de documents) et
**Crawl4AI** (exploration de pages riches en JavaScript, qui télécharge un
navigateur sans interface graphique).

## Organisation du dépôt

```
manifest.toml            Définition du paquet (format v2, helpers 2.1)
config_panel.toml        Réglages exposés à l'administration
conf/                    Gabarits nginx, unités systemd et .env
scripts/                 install / remove / upgrade / backup / restore / change_url / config
patches/                 Petits correctifs amont (prise en charge des sous-chemins)
doc/                     Documentation utilisateur et administrateur affichée dans YunoHost
tests.toml               Configuration de la suite de tests YunoHost
.github/workflows/       CI de vérification (package_linter, shellcheck, TOML/schéma)
docs/                    Documentation de conception et de planification (voir ci-dessous)
```

## Documentation

| Document | Objet |
|---|---|
| [`docs/PLAN.md`](docs/PLAN.md) | Objectif, périmètre, phases et critères d'acceptation. |
| [`docs/open-notebook-analysis.md`](docs/open-notebook-analysis.md) | Ce qu'est open-notebook et les contraintes qu'il impose. |
| [`docs/yunohost-packaging-reference.md`](docs/yunohost-packaging-reference.md) | Référence condensée du packaging YunoHost (v2 / helpers 2.1). |
| [`docs/integration-matrix.md`](docs/integration-matrix.md) | Inventaire de toutes les fonctionnalités d'intégration YunoHost et de leur applicabilité. |
| [`docs/architecture-decisions.md`](docs/architecture-decisions.md) | Décisions d'architecture (processus, données, sauvegarde, SSO, sous-chemins). |
| [`docs/open-questions.md`](docs/open-questions.md) | Décisions prises et vérifications en attente. |

## Vérifications de qualité

`.github/workflows/lint.yml` exécute, à chaque envoi et à chaque demande de
fusion : [`package_linter`](https://github.com/YunoHost/package_linter)
(l'analyseur statique officiel), `bash -n` + `shellcheck` sur les scripts, ainsi
qu'une validation TOML/schéma. Les tests d'**intégration** officiels de YunoHost
([`package_check`](https://github.com/YunoHost/package_check)) s'exécutent sur la
CI de YunoHost une fois l'application hébergée sur `YunoHost-Apps`. Les gabarits
de demande de fusion incluent le déclencheur `!testme` pour la CI de
développement.

## Licence

Le **paquet** est sous licence **AGPL-3.0** (voir [`LICENSE`](LICENSE)).
open-notebook lui-même est sous licence MIT ; voir son
[dépôt](https://github.com/lfnovo/open-notebook).
