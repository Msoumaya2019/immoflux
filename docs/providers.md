# Providers

## État observé

PAP : test réel HTTP 200 sur la page Montmagny et ses fiches. Sept fiches résidentielles décodées et normalisées pendant le test initial, dont certaines peuvent être hors ville ; le générateur applique ensuite la couverture. JSON-LD `Product` des fiches utilisé, liens résidentiels des cartes extraits du HTML. L’autorisation de collecte et de republication a été déclarée par le propriétaire de cette installation. Elle n’est pas une licence ouverte accordée aux tiers et doit être revue pour tout fork.

SeLoger : l’autorisation est également déclarée, mais le test réseau renvoie HTTP 403. Module conservé avec raison explicite, désactivé. Aucun cookie de contournement, CAPTCHA résolu, proxy ou appel à des endpoints privés. Pour l’activer, obtenir un accès technique autorisé et implémenter/tester son adaptateur.

Leboncoin, Bien’ici, ACI Immobilier : modules réservés, non implémentés. Le nom exact de l’agence ACI et son flux restent à identifier. L’interface ne présente pas ces sources comme fonctionnelles.

## Portée PAP

Le provider prend les **premières pages configurées**, maximum 5 pages et 30 fiches par exécution, avec au moins 3 secondes entre appels. Il ne suit pas la pagination `/proximite/`, interdite par robots.txt. La couverture n’est donc pas exhaustive. Pas de promesse de récupérer toutes les annonces de PAP. Les champs absents (terrain, date de publication, coordonnées selon le site) restent nuls.

Les prix/m² proviennent du calcul prix/surface. L’historique commence à la première observation par cette installation. Pas de récupération d’anciennes baisses inventées. Les photos restent des URL publiques originales et sont téléchargées seulement sur l’iPhone.

Le collecteur ne publie pas l’objet vendeur, ses contacts, ni l’adresse de rue structurée. Les emails et numéros français reconnus dans les descriptions sont retirés. Ne publiez jamais de fichiers HTML bruts, exports de comptes, journaux privés ou données personnelles provenant d’une autorisation limitée.

## Ajouter une ville

1. Modifier `config/searches.json` avec ville, code postal, transaction et seuil de collecte (0 pièces recommandé pour filtrer ensuite sur iPhone).
2. Ajouter la page **réelle et permise** à `pap.searchPages` dans `config/providers.json`. Ne pas inventer l’identifiant géographique du site.
3. Lancer `python -m scripts.diagnose_provider pap`, puis le générateur et les tests.
4. Publier puis lancer `collect.yml`. Les préférences iPhone restent locales et ne modifient pas le dépôt.

## Flux JSON autorisé

`authorized_json.py` attend `{"listings": [...]}` avec les noms de champs du modèle commun, notamment `sourceListingId`, `title`, `url`, `city`, `postalCode`, `propertyType`, `transactionType`. Fournir `url`, `permissionReference`, `publicRedistributionAuthorized: true`, puis `enabled: true`. L’URL doit être HTTPS sans identifiants, requête ni fragment ; les redirections et destinations privées sont refusées. Robots inaccessible signifie refus de collecte. Taille 5 Mo et 5000 éléments maximum. Tests locaux disponibles, **aucun flux réel de ce type testé**.

## Nouvel adaptateur

Créer `backend/providers/nom.py` avec `ID`, `NAME`, `REASON` et `fetch(config) -> list[dict]`. Enregistrer dans `REGISTRY`, ajouter sa configuration désactivée par défaut. Conserver les exceptions pour que le générateur marque uniquement ce provider en erreur. Tester structure, droits d’accès, cas vide, format modifié et limites réseau avant activation.

## Diagnostic

`providers.json` donne `status`, `count`, `lastRun` et `lastSuccess`. `ok` signifie récupération et normalisation réussies pendant cette exécution ; `error` garde les anciennes annonces ; `disabled` ne publie pas les anciennes données de cette source ; `unavailable` indique un module sans méthode de collecte. Une exécution verte peut contenir un provider en erreur : examiner le résumé et `health.json`.

`python -m scripts.diagnose_provider pap` est un diagnostic local ciblé. Les logs du générateur ne recopient pas les réponses upstream. Une fiche supprimée ou redirigée peut faire échouer le lot PAP entier ; les anciennes données restent utilisables. Ne pas multiplier les relances : corriger le provider puis attendre le prochain créneau.

## Déduplication

Identifiant stable par source et ID original. Regroupement intersites conservateur : même commune/code/transaction/type, surface proche, pièces égales, prix proches et photo identique ou description longue + agence + titre identiques. Toutes les identités et URL sont conservées. Pas de rapprochement uniquement sur prix/surface pour éviter de fusionner des appartements distincts. Les doublons difficiles peuvent rester séparés ; la détection d’images similaires n’est pas implémentée.

Robots consultés : [PAP](https://www.pap.fr/robots.txt), [SeLoger](https://www.seloger.com/robots.txt). Les règles peuvent changer à tout moment et sont relues à chaque exécution.
