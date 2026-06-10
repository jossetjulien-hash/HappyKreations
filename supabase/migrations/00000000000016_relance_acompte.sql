-- Relance automatique d'acompte pour les commandes en attente.
-- Cron quotidien + bouton manuel dans l'app.

alter table public.commande
  add column relance_acompte_envoye_at timestamptz,
  add column email_relance_ouvert_at   timestamptz;

comment on column public.commande.relance_acompte_envoye_at is 'Timestamp de l''email de relance d''acompte (NULL = pas encore envoyée)';
comment on column public.commande.email_relance_ouvert_at   is 'Timestamp de l''ouverture de l''email de relance (track via Resend webhook)';

-- Config par défaut
insert into public.config (cle, valeur) values
  ('relance_acompte_actif', 'true'),
  ('relance_acompte_delai_heures', '48')
on conflict (cle) do nothing;

-- Étend le trigger d'événements pour tracker la relance + son ouverture
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
  if old.relance_acompte_envoye_at is null and new.relance_acompte_envoye_at is not null then
    insert into public.commande_evenement(commande_id, type, titre, icone)
    values (new.id, 'auto', 'Relance d''acompte envoyée', 'paperplane');
  end if;
  if old.email_relance_ouvert_at is null and new.email_relance_ouvert_at is not null then
    insert into public.commande_evenement(commande_id, type, titre, icone)
    values (new.id, 'auto', 'Email de relance ouvert par le client', 'envelope.open');
  end if;
  return new;
end;
$$;

-- Cron quotidien 9h heure Réunion (5h UTC)
select cron.schedule(
  'relance-acompte-quotidien',
  '0 5 * * *',
  $$
  select net.http_post(
    url := 'https://mhbakgmqyegwyuzofzbf.supabase.co/functions/v1/relance-acompte',
    headers := jsonb_build_object('content-type', 'application/json'),
    body := '{}'::jsonb
  ) as request_id;
  $$
);
