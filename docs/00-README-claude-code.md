# 00 — Guide de construction pour Claude Code

Ce dépôt contient tout le nécessaire pour développer l'application **en autonomie**. Lis ce fichier en premier, puis les documents référencés.

## Documents du dépôt

| Fichier | Rôle |
|---|---|
| `00-README-claude-code.md` | **Ce fichier** — ordre de travail, décisions, conventions |
| `cahier-des-charges-appli-gestion.md` | Spécification fonctionnelle complète (+ pipeline Mermaid) |
| `schema-supabase.sql` | Schéma de base **prêt à exécuter** (tables, RLS, triggers, vues, config) |
| `backend-edge-functions.md` | Spec + squelettes des Supabase Edge Functions |
| `architecture-et-deploiement.md` | Structure du dépôt, variables d'environnement, étapes de déploiement |

## Ce que tu construis

Un produit en **trois livrables** dans un monorepo :
1. `app/` — application **SwiftUI multiplateforme** (iOS 17+ / macOS 14+).
2. `web-form/` — **formulaire de commande public** (page web).
3. `supabase/` — **migrations** + **Edge Functions** (backend léger).

Source de vérité unique : **Supabase** (Postgres + Auth + Realtime + Edge Functions). Espace partagé par **deux utilisateurs** authentifiés.

## Ordre de construction (respecter les phases)

### Phase 1 — Cœur (commence ici)
1. Applique `schema-supabase.sql` au projet Supabase. Génère les types TypeScript et un modèle Swift correspondant.
2. Mets en place **Supabase Auth** (email + mot de passe) pour deux comptes ; RLS déjà définie dans le SQL.
3. Construis l'app SwiftUI : Auth → Tableau de bord, Commandes (CRUD + lignes + paiements), **Agenda** (calendrier par `date_retrait` + vue charge), Stock matières, Recettes, Fournisseurs/réappro, Clients, Réglages.
4. **Synchro temps réel** via Supabase Realtime + cache local (offline-first).
5. **Saisie assistée** : champ « coller un message » → appel `parse-claude` → pré-remplissage d'une commande à valider.
> *Definition of done phase 1* : les deux utilisateurs peuvent gérer commandes, agenda, stock (décrément auto via recettes), réappro et paiements, en synchro sur iPhone + Mac.

### Phase 2 — Formulaire en ligne + Stripe
1. `web-form/` : lit le catalogue (`produit` où `visible_formulaire`) et les **dates disponibles** (`capacite_jour`), collecte la commande.
2. À la validation → Edge Function `creer-paiement` (crée la commande + session **Stripe Checkout** pour l'acompte).
3. Edge Function `webhook-stripe` → à `checkout.session.completed`, enregistre le paiement et passe la commande en **Confirmée** (elle apparaît sur l'agenda en temps réel).
> *Definition of done phase 2* : un client commande et paie l'acompte seul ; la commande arrive confirmée sur les agendas.

### Phase 3 — Auto-import email
Edge Function `ingest-email` (cron) → relève l'adresse dédiée → `parse-claude` → insère dans `commande_entrante` (statut `a_valider`) → visible dans la **boîte de réception** de l'app.

### Phase 4 — Auto-import Messenger (Page pro)
Edge Function `webhook-messenger` (app Meta + `pages_messaging`) → `parse-claude` → `commande_entrante`.
> ⚠️ La **vérification business Meta** est longue : signale-la comme prérequis externe, ne bloque pas les autres phases dessus.

## Décisions déjà verrouillées (ne pas redemander)

- Stack : SwiftUI multiplateforme + Supabase (pas de CloudKit — besoin de partage à deux).
- **Deux utilisateurs**, espace partagé, RLS « staff authentifié = accès complet ».
- Stock **avancé** : recettes (nomenclature) → décrément automatique.
- **Pas** de devis/factures PDF en v1 — seulement suivi des paiements.
- Montants **TTC sans TVA** (micro en franchise en base) — aucun calcul de taxe.
- Paiement en ligne via **Stripe Checkout** (clés côté serveur uniquement).
- Import des canaux **texte** (messenger/email/manuel) : toujours via **boîte de réception** (validation humaine). Le **formulaire** étant structuré + payé, il crée directement la commande.

## Choix par défaut pour les questions ouvertes (applique-les, signale-les comme paramétrables)

- **Acompte** : `30 %` (table `config.acompte_pourcent`).
- **Délai minimum** avant l'événement sur le formulaire : `7 jours` (`config.delai_mini_jours`).
- **Capacité** : par **jours bloqués** + un **plafond d'unités/jour** optionnel (`capacite_jour`). Le formulaire ne propose que les dates non bloquées et sous plafond.
- **Confirmation auto** après paiement de l'acompte : **oui** (remboursement Stripe possible en cas de conflit).
- **Déclinaisons** de produits : variantes simples (chaîne de texte / liste) en v1, pas de recette distincte.
- **Nom de l'appli / projet** : `HappyKreations` (dépôt GitHub + projet Supabase).
- **Export** : bouton d'export CSV des commandes dans Réglages.

## Conventions

- **Langue** : interface et libellés en **français**. Identifiants techniques (tables, champs, fonctions) en français sans accents, comme dans le SQL fourni.
- **Sécurité** : aucune clé secrète (Stripe, service_role, Anthropic, Meta) dans l'app ni la page web publique — uniquement dans les **secrets des Edge Functions**. Voir `architecture-et-deploiement.md`.
- **Confirmations Stripe** : toujours via **webhook signé**, jamais via le seul retour navigateur.
- **Git** : branches par phase, commits atomiques, README de chaque dossier.

## Première action attendue

Applique `schema-supabase.sql`, génère les types, échafaude le monorepo selon `architecture-et-deploiement.md`, puis démarre la **phase 1**.
