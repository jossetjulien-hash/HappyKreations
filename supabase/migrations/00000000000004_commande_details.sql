-- Champs structurés sur la commande, en remplacement progressif du champ
-- `notes` fourre-tout : allergies (multi-sélection), message à graver, couleur.

alter table commande add column if not exists allergies       text[] not null default '{}';
alter table commande add column if not exists message_gravure text;
alter table commande add column if not exists couleur         text;
