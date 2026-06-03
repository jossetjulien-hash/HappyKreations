-- =====================================================================
-- RESET — HappyKreations
-- Supprime TOUT le schéma applicatif, DONNÉES INCLUSES. IRRÉVERSIBLE.
--
-- À exécuter TOI-MÊME dans : Supabase → SQL Editor.
-- Lance ce script, PUIS ré-applique schema-supabase.sql pour repartir propre.
--
-- N'affecte PAS le schéma 'auth'. Pour supprimer aussi les comptes de test,
-- va dans Supabase → Authentication → Users et supprime-les à la main.
-- =====================================================================

-- Triggers
drop trigger if exists tg_recompute_total   on commande_ligne;
drop trigger if exists tg_commande_updated   on commande;
drop trigger if exists tg_sortie_stock       on commande;

-- Fonctions
drop function if exists fn_recompute_total()          cascade;
drop function if exists fn_touch_updated_at()         cascade;
drop function if exists fn_sortie_stock_production()  cascade;

-- Vues
drop view if exists v_matiere_disponible      cascade;
drop view if exists v_matiere_reserve         cascade;
drop view if exists v_commande_besoin_matiere cascade;

-- Tables (CASCADE supprime FK, index et policies associées)
drop table if exists mouvement_stock     cascade;
drop table if exists reappro_ligne        cascade;
drop table if exists bon_reappro          cascade;
drop table if exists matiere_fournisseur  cascade;
drop table if exists fournisseur          cascade;
drop table if exists paiement             cascade;
drop table if exists commande_ligne       cascade;
drop table if exists commande_entrante    cascade;
drop table if exists commande             cascade;
drop table if exists recette_ligne        cascade;
drop table if exists matiere              cascade;
drop table if exists produit              cascade;
drop table if exists client               cascade;
drop table if exists capacite_jour        cascade;
drop table if exists config               cascade;
drop table if exists app_user             cascade;

-- Types énumérés
drop type if exists statut_entrante    cascade;
drop type if exists statut_reappro     cascade;
drop type if exists type_mouvement     cascade;
drop type if exists statut_paiement    cascade;
drop type if exists moyen_paiement     cascade;
drop type if exists statut_commande    cascade;
drop type if exists canal_commande     cascade;
drop type if exists categorie_produit  cascade;
