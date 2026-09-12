# ImmoFlux

Application iPhone native SwiftUI et générateur Python de flux immobiliers, sans serveur payant ni notifications push.

**État : première version en cours de validation.** PAP a répondu au test réel de collecte. SeLoger renvoie HTTP 403 ; aucun contournement. Leboncoin, Bien’ici et ACI restent présents mais non implémentés faute d’accès autorisé identifié. Aucun résultat fictif n’est publié.

## Architecture

```text
PAP / flux autorisés → providers Python isolés → SQLite temporaire
  → normalisation + déduplication + historique compact
  → data/state.json + public/{listings,providers,stats,health}.json
  → GitHub Pages (+ secours raw.githubusercontent.com)
  → SwiftUI → cache local atomique + favoris + préférences
```

Python 3.12 : aucune dépendance externe. iOS 17 minimum. Xcode et XcodeGen sur macOS. GitHub Actions utilise uniquement des runners standard sur dépôt public.

## Démarrage local

```bash
git clone https://github.com/Msoumaya2019/immoflux.git
cd immoflux
python -m unittest discover -s tests -v
python -m backend.generate
python -m scripts.validate
python -m scripts.check_secrets
python -m http.server 8000 --directory public
```

Le serveur HTTP local sert à inspecter les JSON. L’application exige HTTPS : utilisez Pages ou un serveur local correctement configuré en TLS.

## Dépôt et publication

Pour une nouvelle installation : `gh auth login --web`, `git init -b main`, puis `gh repo create immoflux --public --source=. --remote=origin --push` après votre commit initial. Vérifiez votre configuration Git pour ne pas publier d’adresse personnelle.

Dans **Settings → Pages**, choisissez **GitHub Actions** comme source. Après validation de vos propres droits de collecte/republication, définissez la variable de dépôt **COLLECTION_ENABLED=true**. Un fork n’hérite pas de cette variable et ne lance pas automatiquement les providers.

```bash
gh variable set COLLECTION_ENABLED --body true
gh workflow run collect.yml
gh run list --workflow collect.yml
gh run view ID --log-failed
```

API prévue : `https://msoumaya2019.github.io/immoflux/` ; secours : `https://raw.githubusercontent.com/Msoumaya2019/immoflux/main/public/`. Les URL ne sont opérationnelles qu’après une publication réussie.

## API statique

| Fichier | Contenu |
|---|---|
| `listings.json` | Annonces, sources regroupées, historique, couverture, dates |
| `providers.json` | État réel de chaque provider, compte et dernier essai |
| `stats.json` | Nombre de biens, annonces avant regroupement, baisses |
| `health.json` | Santé, dernière exécution et dernière collecte réussie |

Version de schéma : 1. Dates UTC ISO 8601. Montants EUR ; surfaces m². Valeurs inconnues : `null`. `isFavorite` et `isHidden` sont toujours faux dans l’API ; leurs vraies valeurs restent exclusivement sur l’iPhone. `memberIds` préserve les identités lors du regroupement.

Cette API n’est pas un serveur de recherche. Ouvrir l’application télécharge le dernier fichier publié puis filtre localement. **Modifier la ville sur l’iPhone n’ajoute pas cette ville au collecteur.** Il faut l’ajouter à `config/searches.json` et configurer les pages du provider. Les limites de couverture sont signalées dans l’app. Le backend collecte toutes les pièces pour la ville configurée ; le défaut iPhone est 4 pièces.

## Compilation et signature

```bash
brew install xcodegen
xcodegen generate --spec ios/project.yml
open ios/ImmoFlux.xcodeproj
bash scripts/build-ios.sh
```

L’URL est configurable dans `ios/ImmoFlux/AppConfig.json` et dans Réglages sur l’iPhone. Aucun compte Apple n’est intégré. Sur GitHub : **Actions → Compiler IPA iOS non signée → Run workflow**, puis télécharger **ImmoFlux-unsigned** dans les artefacts (conservation 3 jours).

```bash
gh workflow run ios.yml
gh run list --workflow ios.yml
gh run download ID --name ImmoFlux-unsigned --dir build
```

L’IPA contient `Payload/ImmoFlux.app`, compilée pour appareil arm64. Elle ne peut pas être installée sans signature et profil compatibles. `scripts/build-ios.sh` utilise `xcodebuild archive CODE_SIGNING_ALLOWED=NO` puis emballe l’app ; il n’utilise pas `-exportArchive`, qui peut exiger des informations de signature.

Avec votre outil RustSign : importez l’IPA non signée, sélectionnez votre certificat/profil existants compatibles avec l’appareil et l’identifiant `org.immoflux.app` (ou remplacez cet identifiant lors de la signature), signez puis installez suivant votre outil. Aucun certificat, mot de passe, UDID ou profil ne doit être ajouté au dépôt. La version exacte de RustSign n’étant pas fournie, les boutons et la compatibilité ne sont pas présumés testés. Aucun achat n’est nécessaire à la compilation ; vos conditions de signature restent celles de votre certificat existant.

## Providers et limites

Voir [docs/providers.md](docs/providers.md), [docs/limits.md](docs/limits.md) et [docs/validation.md](docs/validation.md).

## Interface et données locales

- Annonces, Favoris, Recherche, Réglages ; clair/sombre et polices système adaptatives.
- Cache montré avant le réseau ; rafraîchissement à l’ouverture, au retour au premier plan et par glissement.
- Favoris conservés même si le bien disparaît du flux ; annonces masquées restaurables.
- Filtres persistants : ville/code/rayon, vente/location, budget, surface, pièces, chambres, types, terrain, sources et mots-clés.
- Géocodage via MapKit sur demande, code postal manuel possible. Rayon uniquement pour les biens ayant des coordonnées et les villes effectivement collectées.
- Historique limité à 30 changements par annonce ; badge nouveau 24 h après première détection.
- Cache images mémoire et disque, budget disque 150 Mo, validité 7 jours ; images originales non copiées sur GitHub.

L’absence d’une annonce lors d’un passage ne prouve pas qu’elle est vendue : elle est conservée jusqu’à 90 jours, avec date de dernière observation visible. Les cartes datées ne doivent pas être interprétées comme une disponibilité confirmée.

## Sécurité

Gitleaks inspecte l’historique dans CI, un garde local contrôle les fichiers et les formats de secrets les plus courants. Aucun scanner ne garantit une absence absolue : relisez avant publication. Permissions GitHub minimales par job, HTTPS, aucune clé d’accès aux sites dans l’iPhone. Les seules données versionnées sont destinées à être publiques. SQLite est temporaire ; `data/state.json` conserve l’historique entre exécutions.

## Évolutions

La frontière provider/modèle permet de remplacer un adaptateur sans recompiler l’IPA. Un backend HTTP futur pourra exposer `/listings`, `/listings/{id}`, `/search`, `/providers`, `/stats`, `/health` et réutiliser les modèles. PostgreSQL/Supabase peut remplacer la persistance sans devenir une dépendance obligatoire. L’app actuelle attend le contrat statique ; un adaptateur de transport serait nécessaire pour une API dynamique différente.
