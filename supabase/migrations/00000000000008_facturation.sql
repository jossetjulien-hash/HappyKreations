-- Numérotation séquentielle des factures (obligation comptable) +
-- champs identité entreprise pour les factures.
--
-- - `commande.numero_facture` : format F2026-001, unique. Auto-attribué quand
--   le statut passe à `confirmee` (acompte reçu) via trigger.
-- - Nouvelles clés `config` : adresse_atelier, siret_atelier, email_atelier,
--   telephone_atelier — éditables dans Réglages, utilisées dans la facture.

alter table commande add column if not exists numero_facture text unique;

create or replace function fn_attribuer_numero_facture()
returns trigger
language plpgsql as $$
declare
  annee int;
  prochain int;
begin
  if new.statut = 'confirmee' and new.numero_facture is null then
    annee := extract(year from coalesce(new.created_at, now()))::int;
    -- Verrou conseil pour éviter une collision de numéro entre transactions
    -- concurrentes (rare mais possible).
    perform pg_advisory_xact_lock(annee);
    select coalesce(max(cast(substring(numero_facture from '\d+$') as int)), 0) + 1
      into prochain
      from commande
     where numero_facture like ('F' || annee || '-%');
    new.numero_facture := 'F' || annee || '-' || lpad(prochain::text, 3, '0');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_numero_facture_insert on commande;
create trigger trg_numero_facture_insert
before insert on commande
for each row
execute function fn_attribuer_numero_facture();

drop trigger if exists trg_numero_facture_update on commande;
create trigger trg_numero_facture_update
before update of statut on commande
for each row
execute function fn_attribuer_numero_facture();

-- Identité entreprise (utilisée dans la facture). Pas de valeurs par défaut
-- volontairement — c'est à l'utilisateur de les renseigner dans Réglages.
insert into config (cle, valeur) values
  ('adresse_atelier',   ''),
  ('siret_atelier',     ''),
  ('email_atelier',     ''),
  ('telephone_atelier', '')
on conflict (cle) do nothing;

-- Ouverture en lecture anonyme des nouvelles clés publiques (atelier).
-- L'ancienne policy `anon_config` n'autorisait que ('acompte_pourcent',
-- 'delai_mini_jours','nom_atelier'). On l'étend.
drop policy if exists anon_config on config;
create policy anon_config on config
  for select to anon
  using (cle in (
    'acompte_pourcent', 'delai_mini_jours', 'nom_atelier',
    'adresse_atelier',  'siret_atelier',    'email_atelier', 'telephone_atelier'
  ));
