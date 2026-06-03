-- =====================================================================
-- Schéma Supabase — Appli de gestion (chocolats & meringues)
-- À exécuter dans le SQL Editor de Supabase, ou via une migration.
-- Postgres + RLS. Auth gérée par Supabase (auth.users).
-- =====================================================================

-- ---------- Types énumérés -------------------------------------------
create type categorie_produit as enum ('coffret', 'cornet');
create type canal_commande    as enum ('formulaire', 'messenger', 'email', 'manuel');
create type statut_commande    as enum ('brouillon','a_confirmer','confirmee','en_production','prete','livree','soldee','annulee');
create type moyen_paiement     as enum ('stripe','especes','virement','autre');
create type statut_paiement    as enum ('en_attente','reussi','rembourse','echoue');
create type type_mouvement     as enum ('entree','sortie','ajustement');
create type statut_reappro     as enum ('brouillon','envoye','recu');
create type statut_entrante    as enum ('a_valider','importee','ignoree');

-- ---------- Utilisateurs (profil lié à auth.users) -------------------
create table app_user (
  id         uuid primary key references auth.users(id) on delete cascade,
  nom        text not null default '',
  role       text not null default 'staff',
  created_at timestamptz not null default now()
);

-- ---------- Clients ---------------------------------------------------
create table client (
  id         uuid primary key default gen_random_uuid(),
  nom        text not null,
  telephone  text,
  email      text,
  messenger  text,
  notes      text,
  created_at timestamptz not null default now()
);

-- ---------- Produits finis -------------------------------------------
create table produit (
  id                 uuid primary key default gen_random_uuid(),
  nom                text not null,
  categorie          categorie_produit not null,
  prix_vente         numeric(10,2) not null default 0,
  declinaisons       text[] not null default '{}',
  visible_formulaire boolean not null default false,
  actif              boolean not null default true,
  created_at         timestamptz not null default now()
);

-- ---------- Matières premières (stock) -------------------------------
create table matiere (
  id            uuid primary key default gen_random_uuid(),
  nom           text not null,
  unite         text not null default 'g',           -- g, kg, ml, piece...
  stock_actuel  numeric(12,3) not null default 0,
  seuil_alerte  numeric(12,3) not null default 0,
  created_at    timestamptz not null default now()
);

-- ---------- Recettes / nomenclature (produit -> matières) ------------
create table recette_ligne (
  id                 uuid primary key default gen_random_uuid(),
  produit_id         uuid not null references produit(id) on delete cascade,
  matiere_id         uuid not null references matiere(id) on delete restrict,
  quantite_par_unite numeric(12,3) not null,
  unique (produit_id, matiere_id)
);

-- ---------- Commandes -------------------------------------------------
create table commande (
  id             uuid primary key default gen_random_uuid(),
  client_id      uuid references client(id) on delete set null,
  canal          canal_commande not null default 'manuel',
  type_evenement text,
  date_evenement date,
  date_retrait   date,
  statut         statut_commande not null default 'brouillon',
  total          numeric(10,2) not null default 0,
  acompte        numeric(10,2) not null default 0,
  notes          text,
  created_by     uuid references app_user(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index idx_commande_date_retrait on commande(date_retrait);
create index idx_commande_statut on commande(statut);

create table commande_ligne (
  id            uuid primary key default gen_random_uuid(),
  commande_id   uuid not null references commande(id) on delete cascade,
  produit_id    uuid not null references produit(id) on delete restrict,
  quantite      integer not null default 1,
  prix_unitaire numeric(10,2) not null default 0,
  declinaison   text
);
create index idx_commande_ligne_commande on commande_ligne(commande_id);

-- ---------- Paiements -------------------------------------------------
create table paiement (
  id                   uuid primary key default gen_random_uuid(),
  commande_id          uuid not null references commande(id) on delete cascade,
  date                 timestamptz not null default now(),
  montant              numeric(10,2) not null,
  moyen                moyen_paiement not null default 'stripe',
  stripe_session_id    text,
  stripe_payment_intent text,
  statut               statut_paiement not null default 'reussi',
  created_at           timestamptz not null default now()
);
create index idx_paiement_commande on paiement(commande_id);

-- ---------- Fournisseurs & réappro -----------------------------------
create table fournisseur (
  id      uuid primary key default gen_random_uuid(),
  nom     text not null,
  contact text,
  notes   text
);

create table matiere_fournisseur (
  id             uuid primary key default gen_random_uuid(),
  fournisseur_id uuid not null references fournisseur(id) on delete cascade,
  matiere_id     uuid not null references matiere(id) on delete cascade,
  reference      text,
  prix_achat     numeric(10,2),
  conditionnement text,
  unique (fournisseur_id, matiere_id)
);

create table bon_reappro (
  id             uuid primary key default gen_random_uuid(),
  fournisseur_id uuid not null references fournisseur(id) on delete restrict,
  date           date not null default current_date,
  statut         statut_reappro not null default 'brouillon',
  created_at     timestamptz not null default now()
);

create table reappro_ligne (
  id            uuid primary key default gen_random_uuid(),
  bon_reappro_id uuid not null references bon_reappro(id) on delete cascade,
  matiere_id    uuid not null references matiere(id) on delete restrict,
  quantite      numeric(12,3) not null
);

-- ---------- Mouvements de stock (traçabilité) ------------------------
create table mouvement_stock (
  id          uuid primary key default gen_random_uuid(),
  matiere_id  uuid not null references matiere(id) on delete cascade,
  date        timestamptz not null default now(),
  type        type_mouvement not null,
  quantite    numeric(12,3) not null,
  origine     text,                                  -- 'commande','reappro','ajustement'
  commande_id uuid references commande(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index idx_mouvement_matiere on mouvement_stock(matiere_id);

-- ---------- File d'auto-import (messenger / email) -------------------
create table commande_entrante (
  id              uuid primary key default gen_random_uuid(),
  canal           canal_commande not null,
  message_brut    text not null,
  donnee_extraite jsonb,
  statut          statut_entrante not null default 'a_valider',
  recu_le         timestamptz not null default now(),
  commande_id     uuid references commande(id) on delete set null
);
create index idx_entrante_statut on commande_entrante(statut);

-- ---------- Capacité (garde-fou du formulaire) -----------------------
create table capacite_jour (
  date           date primary key,
  plafond_unites integer,
  bloque         boolean not null default false
);

-- ---------- Config globale -------------------------------------------
create table config (
  cle    text primary key,
  valeur text not null
);
insert into config (cle, valeur) values
  ('acompte_pourcent', '30'),
  ('delai_mini_jours', '7'),
  ('nom_atelier', 'HappyKreations');

-- =====================================================================
-- Vues : besoins, réservations, disponibilité
-- =====================================================================

-- Besoin en matières par commande (lignes x recettes)
create view v_commande_besoin_matiere as
select cl.commande_id,
       rl.matiere_id,
       sum(cl.quantite * rl.quantite_par_unite) as quantite_totale
from commande_ligne cl
join recette_ligne rl on rl.produit_id = cl.produit_id
group by cl.commande_id, rl.matiere_id;

-- Quantité réservée = besoins des commandes encore en statut 'confirmee'
create view v_matiere_reserve as
select b.matiere_id, sum(b.quantite_totale) as reserve
from v_commande_besoin_matiere b
join commande c on c.id = b.commande_id
where c.statut = 'confirmee'
group by b.matiere_id;

-- Disponible = stock_actuel - réservé ; + drapeau sous seuil
create view v_matiere_disponible as
select m.id as matiere_id,
       m.nom,
       m.unite,
       m.stock_actuel,
       coalesce(r.reserve, 0) as reserve,
       m.stock_actuel - coalesce(r.reserve, 0) as disponible,
       (m.stock_actuel - coalesce(r.reserve, 0)) < m.seuil_alerte as sous_seuil
from matiere m
left join v_matiere_reserve r on r.matiere_id = m.id;

-- =====================================================================
-- Triggers : total commande, updated_at, sortie de stock en production
-- =====================================================================

-- Recalcule commande.total à partir des lignes
create or replace function fn_recompute_total() returns trigger
language plpgsql as $$
declare cid uuid;
begin
  cid := coalesce(new.commande_id, old.commande_id);
  update commande
     set total = coalesce((select sum(quantite * prix_unitaire)
                           from commande_ligne where commande_id = cid), 0)
   where id = cid;
  return null;
end $$;

create trigger tg_recompute_total
after insert or update or delete on commande_ligne
for each row execute function fn_recompute_total();

-- updated_at sur commande
create or replace function fn_touch_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

create trigger tg_commande_updated
before update on commande
for each row execute function fn_touch_updated_at();

-- Sortie ferme de stock au passage en production
-- (les réservations sont calculées par la vue tant que statut='confirmee')
create or replace function fn_sortie_stock_production() returns trigger
language plpgsql as $$
begin
  if new.statut = 'en_production' and old.statut is distinct from 'en_production' then
    insert into mouvement_stock (matiere_id, type, quantite, origine, commande_id)
    select b.matiere_id, 'sortie', b.quantite_totale, 'commande', new.id
    from v_commande_besoin_matiere b
    where b.commande_id = new.id;

    update matiere m
       set stock_actuel = m.stock_actuel - b.quantite_totale
      from v_commande_besoin_matiere b
     where b.commande_id = new.id and b.matiere_id = m.id;
  end if;
  return new;
end $$;

create trigger tg_sortie_stock
after update of statut on commande
for each row execute function fn_sortie_stock_production();

-- =====================================================================
-- Row Level Security
-- Modèle : deux utilisateurs de confiance -> tout utilisateur
-- authentifié a accès complet aux tables métier.
-- Le rôle 'anon' (formulaire public) n'a qu'un accès lecture au
-- catalogue et aux capacités. Les écritures du formulaire passent
-- par une Edge Function en service_role (qui contourne la RLS).
-- =====================================================================

-- Active la RLS partout
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public'
  loop execute format('alter table %I enable row level security;', t);
  end loop;
end $$;

-- Accès complet pour le staff authentifié
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public'
  loop
    execute format(
      'create policy staff_all on %I for all to authenticated using (true) with check (true);', t);
  end loop;
end $$;

-- Lecture publique (anon) du catalogue exposé au formulaire
create policy anon_catalogue on produit
  for select to anon using (visible_formulaire and actif);

-- Lecture publique (anon) des capacités/jours (pour proposer les dates libres)
create policy anon_capacite on capacite_jour
  for select to anon using (true);

-- Lecture publique (anon) de la config nécessaire au formulaire
create policy anon_config on config
  for select to anon using (cle in ('acompte_pourcent','delai_mini_jours','nom_atelier'));
