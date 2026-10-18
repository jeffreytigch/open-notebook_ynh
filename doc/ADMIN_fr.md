open-notebook est un assistant de recherche open source (inspiré de Google
NotebookLM). Il indexe vos sources, vous permet de discuter avec elles et génère
des notes, des analyses et des podcasts.

## Accès

L'accès est contrôlé par YunoHost : seuls les membres du groupe autorisé sur la
permission de l'application peuvent y accéder. De plus, l'API d'open-notebook est
protégée par un **mot de passe d'application** partagé (également utilisé pour se
connecter à l'interface web).

Le mot de passe d'application actuel est :

    __OPEN_NOTEBOOK_PASSWORD__

open-notebook n'a pas de comptes propres : le nom d'utilisateur n'est pas
vérifié. Modifiez le mot de passe depuis l'onglet **Configuration** de
l'application dans l'interface d'administration YunoHost (la valeur y est
masquée : la copie lisible est celle ci-dessus). Les utilisateurs en ont besoin
pour se connecter à l'application, en plus de leur compte YunoHost.

Chaque installation, mise à jour, restauration et modification de configuration
vérifie que le mot de passe enregistré est bien celui qu'accepte le service en
cours d'exécution. Si les deux divergent un jour, l'opération s'arrête avec un
message explicatif plutôt que de laisser une application qui refuse toute
connexion ; définir un nouveau mot de passe depuis l'onglet **Configuration**
répare une telle instance.

Les deux couches sont indépendantes : si vous autorisez les **visiteurs** sur la
permission de l'application, YunoHost cesse de protéger l'URL et seul le mot de
passe d'application protège l'application ; si vous restreignez la permission à
un groupe, les deux s'appliquent.

Comme open-notebook n'a pas de comptes utilisateurs propres, tous les
utilisateurs autorisés partagent le même espace de travail et le même mot de
passe. Si vous avez besoin d'utilisateurs séparés, installez une seconde
instance.

Les échecs répétés de ce mot de passe sont limités par une **prison fail2ban** :
une IP qui échoue 20 fois en 10 minutes est temporairement bloquée. Le seuil est
volontairement généreux, afin qu'un navigateur conservant un mot de passe obsolète
ne puisse pas bloquer un utilisateur légitime.

## Capacités et dépendances

open-notebook dialogue avec des fournisseurs d'IA, mais **n'en fournit aucun**.
Configurez-en un après l'installation, depuis l'application : **Settings →
Models**. Vous pouvez utiliser un fournisseur cloud (une clé d'API pour OpenAI,
Anthropic, Google, Mistral, OpenRouter…) ou un fournisseur local (Ollama, LM
Studio, ou tout point d'accès compatible OpenAI).

* L'*import* des sources ne nécessite aucun fournisseur d'IA, mais l'extraction
  de texte, le chat, les analyses et les podcasts exigent au minimum un modèle de
  langage et un modèle d'embeddings.
* La transcription audio/vidéo et la génération de podcasts nécessitent
  **ffmpeg**, installé avec le paquet.
* Les environnements optionnels **Docling** et **Crawl4AI** peuvent être activés
  depuis le panneau de configuration. Ils sont plus lourds (paquets Python
  supplémentaires / navigateur sans interface graphique) et désactivés par
  défaut.

## Données et sauvegardes

Toutes les données persistantes (sources, carnets, notes, historique des
conversations, podcasts, base de données) résident dans le répertoire de données
de l'application et sont incluses dans les sauvegardes et restaurations
YunoHost.

## Services externes / confidentialité

Si vous configurez un fournisseur d'IA cloud, le texte de vos sources et vos
questions sont envoyés à ce fournisseur. Utilisez un fournisseur local si vos
documents doivent rester sur le serveur.
