# Validation

Journal à compléter avec les résultats finaux de cette exécution.

- Python 3.12 : compilation des modules effectuée ; 22 tests unitaires hors ligne réussis.
- PAP : 7 fiches résidentielles réelles décodées et normalisées lors du diagnostic ciblé. La couverture ville est appliquée par le générateur.
- SeLoger : requête réelle HTTP 403 ; non fonctionnel.
- Swift : tests et compilation à exécuter sur le runner macOS GitHub ; non revendiqués avant résultat.
- Aucun binaire issu de l’IPA proposée par l’utilisateur intégré au projet.

Tests backend : normalisation, champs requis, nombres invalides, URL, identité stable, géographie, déduplication conservatrice, regroupement, isolation d’une panne, persistance prix, rétention, états vides, lot invalide, robots avec jokers, parser PAP et suppression des contacts.

Tests Swift : contrat backend réel, filtres, recherche, badge 24 h, encodage/restauration des préférences, prix inconnu, rayon, source masquée, alias d’identités et tri.

À vérifier sur un iPhone signé : lancement à froid, retour au premier plan, mode avion, Dynamic Type maximal, VoiceOver, défilement des photos, persistance après fermeture, signature RustSign. La compilation ne remplace pas ces essais matériels.
