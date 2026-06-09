-- Quantités min/max commandables par produit (NULL = pas de contrainte).
-- Appliqué côté formulaire web (UI + validation) et re-validé côté Edge
-- Function `creer-paiement` (filet de sécurité serveur).

alter table public.produit
  add column qte_min int,
  add column qte_max int;

alter table public.produit
  add constraint produit_qte_min_check check (qte_min is null or qte_min > 0),
  add constraint produit_qte_max_check check (qte_max is null or qte_max >= coalesce(qte_min, 1));

comment on column public.produit.qte_min is 'Quantité minimum commandable (NULL = pas de min)';
comment on column public.produit.qte_max is 'Quantité maximum commandable (NULL = pas de max)';
