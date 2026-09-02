-- Notifications push distantes (APNs)
--
-- Les notifications locales (LocalNotificationService) ne partent que si
-- l'app tourne ou garde une session Realtime vivante en arrière-plan. Les
-- push distantes arrivent même app fermée et appareil en veille.
--
-- Chaîne complète :
--   app iOS → jeton APNs → table `appareil`
--   commande/paiement → trigger → Edge Function `envoyer-push` → APNs

create table public.appareil (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  device_token text not null unique,
  plateforme text not null default 'ios' check (plateforme in ('ios', 'macos')),
  -- 'development' (build Xcode) ou 'production' (TestFlight / App Store).
  -- Détermine le serveur APNs à contacter ; les jetons ne sont pas
  -- interchangeables entre les deux.
  environnement text not null default 'production'
    check (environnement in ('development', 'production')),
  modele text,
  actif boolean not null default true,
  derniere_maj timestamptz not null default now(),
  created_at timestamptz default now()
);

create index appareil_actif_idx on public.appareil(actif) where actif;

alter table public.appareil enable row level security;

create policy "auth_lecture_ses_appareils" on public.appareil
  for select to authenticated using (auth.uid() = user_id);
create policy "auth_insert_ses_appareils" on public.appareil
  for insert to authenticated with check (auth.uid() = user_id);
create policy "auth_update_ses_appareils" on public.appareil
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "auth_delete_ses_appareils" on public.appareil
  for delete to authenticated using (auth.uid() = user_id);

comment on table  public.appareil is 'Jetons APNs des appareils pour les notifications push distantes';
comment on column public.appareil.environnement is 'development = build Xcode local, production = TestFlight/App Store. Change le serveur APNs cible.';

-- Déclencheurs : nouvelle commande formulaire + acompte encaissé.
-- L'appel est asynchrone (pg_net) : une notification perdue ne doit jamais
-- faire échouer une vente.

create or replace function public.tg_push_nouvelle_commande()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  nom_client text;
begin
  if new.canal is distinct from 'formulaire' then return new; end if;

  select c.nom into nom_client from public.client c where c.id = new.client_id;

  perform net.http_post(
    url := 'https://mhbakgmqyegwyuzofzbf.supabase.co/functions/v1/envoyer-push',
    headers := jsonb_build_object('content-type', 'application/json'),
    body := jsonb_build_object(
      'titre', 'Nouvelle commande ✿',
      'corps', coalesce(nom_client, 'Un client') || ' — ' ||
               trim(to_char(new.total, 'FM999G990D90')) || ' €',
      'commande_id', new.id
    )
  );
  return new;
end;
$$;

create trigger push_nouvelle_commande
  after insert on public.commande
  for each row execute function public.tg_push_nouvelle_commande();

create or replace function public.tg_push_paiement_recu()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  nom_client text;
begin
  if new.statut is distinct from 'reussi' then return new; end if;

  select c.nom into nom_client
  from public.commande cmd
  left join public.client c on c.id = cmd.client_id
  where cmd.id = new.commande_id;

  perform net.http_post(
    url := 'https://mhbakgmqyegwyuzofzbf.supabase.co/functions/v1/envoyer-push',
    headers := jsonb_build_object('content-type', 'application/json'),
    body := jsonb_build_object(
      'titre', 'Paiement reçu 💶',
      'corps', trim(to_char(new.montant, 'FM999G990D90')) || ' € de ' ||
               coalesce(nom_client, 'un client'),
      'commande_id', new.commande_id
    )
  );
  return new;
end;
$$;

create trigger push_paiement_recu
  after insert on public.paiement
  for each row execute function public.tg_push_paiement_recu();
