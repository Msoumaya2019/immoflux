# Validation

Journal à compléter avec les résultats finaux de cette exécution.

- Python 3.12 : compilation des modules effectuée ; 22 tests unitaires hors ligne réussis.
- PAP : 7 fiches résidentielles réelles décodées lors du diagnostic ciblé ; 5 annonces de Montmagny validées et publiées après application de la couverture. Une collecte complète suivante a réussi.
- SeLoger : requête réelle HTTP 403 ; non fonctionnel.
- Swift : 11 tests du cœur réussis sur le runner macOS GitHub. Compilation complète relancée après correction de compatibilité Xcode et d’un conflit de nom Swift.
- Aucun binaire issu de l’IPA proposée par l’utilisateur intégré au projet.

Tests backend : normalisation, champs requis, nombres invalides, URL, identité stable, géographie, déduplication conservatrice, regroupement, isolation d’une panne, persistance prix, rétention, états vides, lot invalide, robots avec jokers, parser PAP et suppression des contacts.

Tests Swift : contrat backend réel, filtres, recherche, badge 24 h, encodage/restauration des préférences, prix inconnu, rayon, source masquée, alias d’identités et tri.

À vérifier sur un iPhone signé : lancement à froid, retour au premier plan, mode avion, Dynamic Type maximal, VoiceOver, défilement des photos, persistance après fermeture, signature RustSign. La compilation ne remplace pas ces essais matériels.
