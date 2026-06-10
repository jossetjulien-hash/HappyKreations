-- Zones de livraison configurables (depuis l'app, dans Réglages →
-- Zones de livraison). Les zones actives sont exposées au formulaire web
-- via une policy RLS publique.

create table public.zone_livraison (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  tarif numeric(10,2) not null check (tarif >= 0),
  description text,
  ordre int not null default 0,
  actif boolean not null default true,
  created_at timestamptz default now()
);

alter table public.zone_livraison enable row level security;

create policy "anon_lecture_zones_actives" on public.zone_livraison
  for select to anon using (actif = true);

create policy "auth_crud_zones" on public.zone_livraison
  for all to authenticated using (true) with check (true);

-- Pré-remplir des zones par défaut (modifiables/supprimables depuis l'app).
insert into public.zone_livraison (nom, tarif, ordre) values
  ('Retrait sur place (gratuit)', 0, 0),
  ('Nord — Saint-Denis, Sainte-Marie, Sainte-Suzanne', 5, 1),
  ('Ouest — Le Port, La Possession, Saint-Paul, Saint-Leu', 8, 2),
  ('Sud — Saint-Louis, Saint-Pierre, Le Tampon, Saint-Joseph', 10, 3),
  ('Est — Saint-Benoît, Bras-Panon, Saint-André', 12, 4),
  ('Cirques — Cilaos, Salazie, Mafate', 25, 5);

-- Colonnes sur commande : mode de remise + zone choisie + montant figé.
alter table public.commande
  add column mode_remise text not null default 'retrait'
    check (mode_remise in ('retrait', 'livraison')),
  add column zone_livraison_id uuid references public.zone_livraison(id) on delete set null,
  add column frais_livraison numeric(10,2) not null default 0 check (frais_livraison >= 0);

comment on column public.commande.mode_remise is 'retrait sur place ou livraison';
comment on column public.commande.frais_livraison is 'Tarif appliqué (copié de la zone au moment de la commande, fige le prix)';
