-- Historique d'événements par commande : mémos manuels (saisis par
-- l'utilisateur) + événements automatiques générés par les triggers
-- (création, changement de statut, paiement reçu, email envoyé, etc.).

create type type_evenement_commande as enum ('auto', 'memo');

create table public.commande_evenement (
  id uuid primary key default gen_random_uuid(),
  commande_id uuid not null references public.commande(id) on delete cascade,
  type type_evenement_commande not null default 'memo',
  titre text not null,
  description text,
  icone text,
  auteur uuid references auth.users(id) on delete set null,
  created_at timestamptz default now()
);

create index commande_evt_commande_idx on public.commande_evenement(commande_id, created_at desc);

alter table public.commande_evenement enable row level security;
create policy "auth_lecture_evt" on public.commande_evenement for select to authenticated using (true);
create policy "auth_insert_evt" on public.commande_evenement for insert to authenticated with check (true);
create policy "auth_update_evt" on public.commande_evenement for update to authenticated using (true) with check (true);
create policy "auth_delete_evt" on public.commande_evenement for delete to authenticated using (true);

create or replace function public.tg_evt_commande_inserted()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.commande_evenement(commande_id, type, titre, description, icone)
  values (new.id, 'auto', 'Commande créée',
          'Canal : ' || coalesce(new.canal::text, 'manuel'), 'plus.circle');
  return new;
end;
$$;
create trigger evt_commande_inserted after insert on public.commande
  for each row execute function public.tg_evt_commande_inserted();

create or replace function public.tg_evt_commande_updated()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.statut is distinct from old.statut then
    insert into public.commande_evenement(commande_id, type, titre, icone)
    values (new.id, 'auto', 'Statut → ' || new.statut::text, 'arrow.right.circle');
  end if;
  if old.numero_facture is null and new.numero_facture is not null then
    insert into public.commande_evenement(commande_id, type, titre, description, icone)
    values (new.id, 'auto', 'Facture émise', 'N° ' || new.numero_facture, 'doc.text');
  end if;
  if old.photo_resultat_url is null and new.photo_resultat_url is not null then
    insert into public.commande_evenement(commande_id, type, titre, icone)
    values (new.id, 'auto', 'Photo de production ajoutée', 'photo');
  end if;
  if old.rappel_envoye_at is null and new.rappel_envoye_at is not null then
    insert into public.commande_evenement(commande_id, type, titre, icone)
    values (new.id, 'auto', 'Email rappel J-3 envoyé', 'bell');
  end if;
  if old.email_confirmation_ouvert_at is null and new.email_confirmation_ouvert_at is not null then
    insert into public.commande_evenement(commande_id, type, titre, icone)
    values (new.id, 'auto', 'Email de confirmation ouvert par le client', 'envelope.open');
  end if;
  if old.email_rappel_ouvert_at is null and new.email_rappel_ouvert_at is not null then
    insert into public.commande_evenement(commande_id, type, titre, icone)
    values (new.id, 'auto', 'Email rappel ouvert par le client', 'envelope.open');
  end if;
  return new;
end;
$$;
create trigger evt_commande_updated after update on public.commande
  for each row execute function public.tg_evt_commande_updated();

create or replace function public.tg_evt_paiement_inserted()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.commande_evenement(commande_id, type, titre, description, icone)
  values (new.commande_id, 'auto', 'Paiement ' || new.statut::text,
          format('%s — %s €', new.moyen::text,
                 trim(to_char(new.montant, 'FM999G990D90'))), 'creditcard');
  return new;
end;
$$;
create trigger evt_paiement_inserted after insert on public.paiement
  for each row execute function public.tg_evt_paiement_inserted();

comment on table public.commande_evenement is 'Timeline d''événements (auto + mémos manuels) pour chaque commande';
