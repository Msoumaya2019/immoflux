# Gratuité et limites

Documentation vérifiée le 12 septembre 2026. Les services tiers peuvent modifier leurs règles.

## GitHub

- Actions : runners GitHub **standard** gratuits pour les dépôts publics. Ce projet refuse le build/collecteur sur dépôt privé. Aucun runner « larger », serveur payant, Codespaces ni service de signature payant utilisé. Voir [facturation Actions](https://docs.github.com/en/actions/concepts/billing-and-usage).
- Fréquence choisie : toutes les 6 heures, minute 17 UTC, plus déclenchement manuel et modifications du backend. Minimum théorique GitHub : 5 minutes, mais ce projet ne l’utilise pas. Une collecte n’est pas garantie à l’heure prévue ; files d’attente et exécutions retardées/supprimées sont possibles. Planifications désactivées après 60 jours d’inactivité sur un dépôt public. Voir [événements et planification](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows).
- Limites internes : 10 minutes collecte, 10 minutes publication, 15 minutes tests, 30 minutes build iOS. La limite GitHub d’un job hébergé est supérieure (6 heures), mais les jobs de ce projet sont arrêtés avant. Concurrence par compte également limitée. Voir [limites Actions](https://docs.github.com/en/actions/reference/limits).
- Pages : site publié maximum 1 Go, bande passante indicative 100 Go/mois, déploiement interrompu après 10 minutes. Pas de garantie de disponibilité. Usage personnel non commercial. Voir [limites Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits).
- Les artefacts IPA expirent après 3 jours, ceux de Pages après 1 jour. Télécharger l’IPA utile et supprimer les anciens artefacts si nécessaire ; pas de stockage volontairement illimité. Aucun achat ni carte bancaire requis par ce projet.
- Le dépôt est public : code, données et historique peuvent être copiés par des tiers. Les supprimer du dernier commit ne les retire pas de l’historique ni des copies.

## Stockage

Maximum 2000 annonces mémorisées par défaut (plafond dur 5000), rétention 90 jours, 30 changements de prix par annonce. Aucun fichier image ni SQLite versionné. La taille du dernier JSON est bornée ; **l’historique Git reste cumulatif** et doit être surveillé (`git count-objects -vH`). Si le dépôt grossit, espacer les commits, externaliser l’historique vers une solution gratuite appropriée ou reconstruire l’historique après sauvegarde et accord explicite. Aucune réécriture automatique destructrice.

## Ce que « actualiser » signifie

L’iPhone relit la dernière génération distante, pas les sites eux-mêmes. Une ville absente de la configuration n’est pas collectée. Les interrupteurs iPhone filtrent les sources déjà publiées ; ils ne déclenchent aucun workflow authentifié. Aucun token GitHub dans l’app.

Le fallback raw GitHub couvre une panne de Pages, pas une panne de GitHub entière. Hors ligne, cache JSON et favoris restent lisibles. Les photos absentes du cache ne peuvent pas être inventées.

## Qualité des données

PAP : premières pages autorisées seulement, sans pagination interdite ; résultat partiel. SeLoger : accès bloqué HTTP 403. Les autres portails sont des modules réservés. Pas d’exhaustivité multi-sites dans cette version. Un bien non revu peut rester 90 jours avec date de dernière observation. L’app ne garantit ni disponibilité commerciale, ni exactitude de la description originale.

Un rayon exclut les annonces sans coordonnées. PAP ne fournit pas forcément ces coordonnées : préférer ville/code postal dans ce cas. Les résultats MapKit peuvent ne pas lister tous les codes postaux ; saisie manuelle disponible.

## Signature iOS

Windows ne contient pas Xcode. Les compilations réelles s’effectuent sur macOS local ou le runner GitHub macOS standard. L’archive/IPA non signée est un produit de compilation, pas une application installable telle quelle. La signature, le provisioning et l’enregistrement éventuel de l’appareil doivent correspondre à votre outil/certificat. Le projet n’achète ni ne renouvelle de certificat.
