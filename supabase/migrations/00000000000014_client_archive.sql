-- Archivage des clients : soft delete pour les inactifs (pas affichés
-- dans la liste « Actifs » mais leurs commandes restent accessibles).
-- La suppression hard reste possible si le client n'a aucune commande.

alter table public.client
  add column archived boolean not null default false;

create index if not exists client_archived_idx on public.client(archived);

comment on column public.client.archived is 'Client archivé : masqué des listes par défaut, mais ses commandes restent accessibles';
