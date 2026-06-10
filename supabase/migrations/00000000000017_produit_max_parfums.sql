-- Nombre maximum de parfums (déclinaisons) combinables dans une même
-- commande de ce produit. Défaut 1 (pas de multi-parfum, comportement
-- inchangé). Mettre 2 pour les meringues : moitié vanille + moitié
-- chocolat, etc.

alter table public.produit
  add column max_parfums_par_commande int not null default 1
    check (max_parfums_par_commande >= 1);

comment on column public.produit.max_parfums_par_commande is 'Nombre maximum de parfums (déclinaisons) qu''un client peut combiner dans une même commande. Défaut 1.';
