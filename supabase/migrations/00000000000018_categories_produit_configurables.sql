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
-- Les produits déjà saisis sont rattachés par nom, avec un repli sur
-- l'ancien enum pour tout produit non reconnu : aucune donnée perdue.

-- 0. Libérer le nom : l'ancien enum devient _legacy le temps de la bascule
alter type public.categorie_produit rename to categorie_produit_legacy;

-- 1. Table de catégories configurables
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

comment on table  public.categorie_produit is 'Catégories de produits configurables depuis l''app (remplace l''ancien enum figé)';
comment on column public.categorie_produit.unite is 'Unité affichée dans le formulaire web (pièces, cornets, coffrets…)';
comment on column public.categorie_produit.emoji is 'Emoji de repli affiché sur le formulaire quand le produit n''a pas de photo';
comment on column public.categorie_produit.icone is 'SF Symbol utilisé dans l''app iOS/macOS';

insert into public.categorie_produit (nom, emoji, icone, unite, ordre) values
  ('Chocolats',              '🍫', 'square.grid.3x3.fill', 'pièces',   1),
  ('Meringues',              '🌀', 'cone.fill',            'cornets',  2),
  ('Coffrets & boîtes',      '🎁', 'shippingbox.fill',     'coffrets', 3),
  ('Mariage & personnalisé', '💍', 'heart.fill',           'pièces',   4);

-- 2. Lien produit → catégorie
alter table public.produit
  add column categorie_id uuid references public.categorie_produit(id) on delete set null;

-- 3. Nettoyer les espaces parasites en fin de nom
update public.produit set nom = trim(nom) where nom <> trim(nom);

-- 4. Rattacher les produits existants (par nom)
update public.produit p set categorie_id = c.id
from public.categorie_produit c
where c.nom = 'Chocolats' and p.nom = 'Chocolat à l’unité';

update public.produit p set categorie_id = c.id
from public.categorie_produit c
where c.nom = 'Coffrets & boîtes' and p.nom = 'Coffret de 50 chocolats';

update public.produit p set categorie_id = c.id
from public.categorie_produit c
where c.nom = 'Meringues' and p.nom in ('Cornet de 10 meringuettes', 'Sachet de 6 meringuettes');

-- Repli : tout produit encore sans catégorie suit l'ancien enum
update public.produit p set categorie_id = c.id
from public.categorie_produit c
where p.categorie_id is null
  and c.nom = case when p.categorie::text = 'cornet' then 'Meringues' else 'Coffrets & boîtes' end;

-- 5. Retirer l'ancien enum
alter table public.produit drop column categorie;
drop type public.categorie_produit_legacy;
