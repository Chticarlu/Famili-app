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
