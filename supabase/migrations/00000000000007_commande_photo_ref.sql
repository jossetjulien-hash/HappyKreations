-- Photo de référence par commande (« comme ce style »).
-- - Colonne `commande.photo_ref_url` : URL publique vers le fichier dans Storage.
-- - Bucket Storage `commandes-refs` : public en lecture (URLs directes),
--   écriture par staff authentifié + écriture anonyme (depuis le formulaire web).
--   On ne permet pas le LIST pour éviter l'énumération des photos clients
--   (cf. advisor public_bucket_allows_listing).

alter table commande add column if not exists photo_ref_url text;

insert into storage.buckets (id, name, public)
values ('commandes-refs', 'commandes-refs', true)
on conflict (id) do update set public = excluded.public;

-- Insertion : staff (commandes saisies dans l'app) OU anonyme (formulaire web).
drop policy if exists commandes_refs_insert on storage.objects;
create policy commandes_refs_insert on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'commandes-refs');

-- Update / delete : staff uniquement (jamais le client public).
drop policy if exists commandes_refs_staff_update on storage.objects;
create policy commandes_refs_staff_update on storage.objects
  for update to authenticated
  using (bucket_id = 'commandes-refs')
  with check (bucket_id = 'commandes-refs');

drop policy if exists commandes_refs_staff_delete on storage.objects;
create policy commandes_refs_staff_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'commandes-refs');
