-- Photos produits : colonne photo_url + bucket Storage public en lecture,
-- écriture réservée aux utilisateurs authentifiés (staff).

alter table produit add column if not exists photo_url text;

insert into storage.buckets (id, name, public)
values ('produits', 'produits', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists produits_public_read on storage.objects;
create policy produits_public_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'produits');

drop policy if exists produits_staff_insert on storage.objects;
create policy produits_staff_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'produits');

drop policy if exists produits_staff_update on storage.objects;
create policy produits_staff_update on storage.objects
  for update to authenticated
  using (bucket_id = 'produits')
  with check (bucket_id = 'produits');

drop policy if exists produits_staff_delete on storage.objects;
create policy produits_staff_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'produits');
