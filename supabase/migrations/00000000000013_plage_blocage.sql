-- Plages pendant lesquelles aucune commande ne peut être retirée
-- (vacances, fermeture exceptionnelle…). Affichées au client sur le
-- formulaire avec un message personnalisable.

create table public.plage_blocage (
  id uuid primary key default gen_random_uuid(),
  date_debut date not null,
  date_fin date not null,
  libelle text not null,
  message_client text,
  actif boolean not null default true,
  created_at timestamptz default now(),
  check (date_fin >= date_debut)
);

alter table public.plage_blocage enable row level security;

-- Lecture publique des plages actives (pour le formulaire web).
create policy "anon_lecture_plages_actives" on public.plage_blocage
  for select to anon using (actif = true);

create policy "auth_crud_plages" on public.plage_blocage
  for all to authenticated using (true) with check (true);

comment on table  public.plage_blocage is 'Périodes pendant lesquelles aucune commande ne peut être retirée (vacances, fermeture exceptionnelle…)';
comment on column public.plage_blocage.libelle is 'Libellé interne, ex. « Congés d''été »';
comment on column public.plage_blocage.message_client is 'Message affiché aux clients sur le formulaire pendant cette période';
