-- Photo « après production » : preuve visuelle du résultat fini, sert aussi
-- à alimenter la galerie publique « Inspirations » sur la home.

-- 1. Colonne sur la commande
alter table commande add column if not exists photo_resultat_url text;

-- 2. Bucket Storage dédié (séparé de commandes-refs pour distinguer
--    nettement « photo référence du client » et « photo résultat artisan »).
insert into storage.buckets (id, name, public)
values ('commandes-resultats', 'commandes-resultats', true)
on conflict (id) do update set public = excluded.public;

-- Insert/update/delete : staff authentifié uniquement.
drop policy if exists resultats_staff_insert on storage.objects;
create policy resultats_staff_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'commandes-resultats');

drop policy if exists resultats_staff_update on storage.objects;
create policy resultats_staff_update on storage.objects
  for update to authenticated
  using (bucket_id = 'commandes-resultats')
  with check (bucket_id = 'commandes-resultats');

drop policy if exists resultats_staff_delete on storage.objects;
create policy resultats_staff_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'commandes-resultats');

-- Pas de policy SELECT large : les fichiers sont servis par URL publique
-- (bucket public = true), ce qui suffit. Évite l'énumération.

-- 3. Vue publique « v_inspirations » consommée par le site web (clé anon).
--    Expose UNIQUEMENT photo + type d'événement + date — aucune donnée
--    personnelle client.
create or replace view v_inspirations as
  select id,
         photo_resultat_url,
         type_evenement,
         date_retrait
    from commande
   where photo_resultat_url is not null
     and statut <> 'annulee';

grant select on v_inspirations to anon;