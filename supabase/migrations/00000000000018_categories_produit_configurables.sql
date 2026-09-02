-- Catégories de produits configurables
--
-- Remplace l'enum figé `categorie_produit` ('coffret','cornet') par une
-- vraie table éditable depuis l'app (même principe que zone_livraison) :
-- l'artisan ajoute / renomme / supprime ses catégories sans toucher au code.
--
-- Chaque catégorie porte aussi :
--   - un emoji  → repli visuel sur le formulaire web quand pas de photo
--   - une icône → SF Symbol dans l'app iOS/macOS
--   - une unité → « pièces », « cornets », « coffrets »… utilisée dans les
--                 messages de quantité min/max du formulaire
--
-- La table produit est vide au moment de cette migration (table rase), donc
-- aucune donnée à reprendre.

-- 1. Retirer l'ancienne colonne + le type enum
alter table public.produit drop column if exists categorie;
drop type if exists public.categorie_produit;

-- 2. Nouvelle table configurable
create table public.categorie_produit (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  emoji text,
  icone text not null default 'shippingbox',
  unite text not null default 'pièces',
  ordre int not null default 0,
  actif boolean not null default true,
  created_at timestamptz default now()
);

alter table public.categorie_produit enable row level security;

create policy "anon_lecture_categories" on public.categorie_produit
  for select to anon using (actif = true);
create policy "auth_crud_categories" on public.categorie_produit
  for all to authenticated using (true) with check (true);

-- 3. Lien produit → catégorie
alter table public.produit
  add column categorie_id uuid references public.categorie_produit(id) on delete set null;

comment on table  public.categorie_produit is 'Catégories de produits configurables depuis l''app (remplace l''ancien enum figé)';
comment on column public.categorie_produit.unite is 'Unité affichée dans le formulaire web (pièces, cornets, coffrets…)';
comment on column public.categorie_produit.emoji is 'Emoji de repli affiché sur le formulaire quand le produit n''a pas de photo';
comment on column public.categorie_produit.icone is 'SF Symbol utilisé dans l''app iOS/macOS';

-- 4. Catégories de départ (modifiables/supprimables depuis l'app)
insert into public.categorie_produit (nom, emoji, icone, unite, ordre) values
  ('Chocolats',              '🍫', 'square.grid.3x3.fill', 'pièces',   1),
  ('Meringues',              '🌀', 'cone.fill',            'cornets',  2),
  ('Coffrets & boîtes',      '🎁', 'shippingbox.fill',     'coffrets', 3),
  ('Mariage & personnalisé', '💍', 'heart.fill',           'pièces',   4);

-- 5. Catalogue de départ
insert into public.produit
  (nom, categorie_id, prix_vente, declinaisons, visible_formulaire, actif,
   qte_min, qte_max, max_parfums_par_commande)
select v.nom, c.id, v.prix, v.declinaisons, true, true,
       v.qte_min, v.qte_max, v.max_parfums
from (values
  ('Chocolat à l''unité',                  'Chocolats',              1.00,  array['Noir','Lait','Blanc'],                              30,   null::int, 2),
  ('Carte de chocolat',                    'Chocolats',              1.30,  array['Noir','Lait','Blanc'],                              30,   null::int, 2),
  ('Cornet de meringuettes',               'Meringues',              3.50,  array['Nature','Citron','Passion','Fruits Rouges','Fleur d''Oranger','Coco'], 10, null::int, 2),
  ('Boîte choco/meringues',                'Coffrets & boîtes',      6.50,  array['Nature','Citron','Passion','Fruits Rouges','Fleur d''Oranger','Coco'], 10, null::int, 2),
  ('Coffret de 50 chocolats',              'Coffrets & boîtes',     60.00,  array['Noir','Lait','Blanc'],                              null, null::int, 2),
  ('Cadre de bienvenue',                   'Mariage & personnalisé',50.00,  array[]::text[],                                           null, null::int, 1),
  ('Panneau de bienvenue gravé sur bois',  'Mariage & personnalisé',80.00,  array[]::text[],                                           null, null::int, 1),
  ('Demande de témoin — homme',            'Mariage & personnalisé',25.00,  array[]::text[],                                           null, null::int, 1),
  ('Demande de la témoin — personnalisée', 'Mariage & personnalisé',25.00,  array[]::text[],                                           null, null::int, 1),
  ('Plante grasse personnalisée',          'Mariage & personnalisé', 5.50,  array[]::text[],                                           null, null::int, 1),
  ('Roll up personnalisé 800×2000',        'Mariage & personnalisé',160.00, array[]::text[],                                           null, null::int, 1)
) as v(nom, categorie, prix, declinaisons, qte_min, qte_max, max_parfums)
join public.categorie_produit c on c.nom = v.categorie;
