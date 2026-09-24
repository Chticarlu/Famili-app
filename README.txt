FAMILI V5.2 FINAL

À déposer à la racine du dépôt GitHub Famili-app.

Principales évolutions :
- Assistant Famili déplacé sur l'accueil
- Menus IA intégrés dans Repas
- récapitulatif « À faire aujourd'hui »
- onboarding du foyer
- planning groupé et états vides
- tâches et courses mieux triées
- confirmations avant suppression
- statut de résiliation plus clair
- affichage du quota IA 100 requêtes / mois / foyer
- messages IA plus clairs pour quota ou abonnement
- possibilité pour un membre de quitter le foyer
- mot de passe oublié et écran de définition du nouveau mot de passe
- manifest PWA ajouté et cache service worker V5.2

Important : après déploiement, vérifier dans Supabase Authentication > URL Configuration que l'URL de production Vercel est autorisée pour la récupération du mot de passe.


V5.3 — gestion du compte : transfert de propriété du foyer et suppression sécurisée du compte.


V5.4 finale avant bêta :
- gestion et suppression sécurisée du compte ;
- transfert de propriété du foyer ;
- export JSON des données ;
- support par e-mail ;
- échappement des données affichées pour réduire les risques XSS ;
- en-têtes de sécurité Vercel ;
- cache PWA mis à jour.

V5.5 — pages juridiques intégrées :
- mentions légales ;
- politique de confidentialité / RGPD ;
- CGU ;
- CGV Famili Premium ;
- rétractation, résiliation et remboursements ;
- contact, réclamations et médiation ;
- coordonnées de l’éditeur ajoutées ;
- adresse de contact temporaire : contact@fretixo.fr.
À compléter avant ouverture commerciale : SIREN/SIRET, mention EI après immatriculation, régime TVA, médiateur de la consommation.

V5.6 finale bêta :
- accès aux informations légales avant connexion ;
- acceptation explicite CGU + confidentialité à l'inscription ;
- horodatage/version de l'acceptation conservés côté Supabase ;
- acceptation explicite des CGV avant ouverture de Stripe ;
- conservation côté Supabase de l'acceptation des CGV Premium ;
- rappel clair : 14 jours gratuits puis 5,99 €/mois jusqu'à résiliation.

V5.7 — durcissement bêta :
- limitation de longueur sur les principaux champs de saisie ;
- service worker limité au même domaine ;
- navigation en stratégie réseau d’abord pour réduire les risques de version obsolète ;
- cache PWA versionné V5.7.
Le backend Supabase a également été renforcé avec :
- un seul foyer maximum par utilisateur ;
- un seul propriétaire par foyer ;
- contraintes de longueur côté base sur les principales données.
