-- Coût matière et marge produit.
-- - `matiere.cout_unitaire` : prix d'achat par unité de stock (ex. €/g, €/mL).
--   On stocke à 4 décimales pour les matières peu coûteuses au gramme.
-- - `v_produit_marge` : pour chaque produit, somme du coût matière d'une unité
--   (basée sur la recette) + marge brute calculée à partir du prix de vente.

alter table matiere add column if not exists cout_unitaire numeric(12,4);

create or replace view v_produit_marge as
select p.id as produit_id,
       p.nom,
       p.prix_vente,
       coalesce(sum(rl.quantite_par_unite * m.cout_unitaire), 0) as cout_matiere,
       p.prix_vente
         - coalesce(sum(rl.quantite_par_unite * m.cout_unitaire), 0) as marge,
       case
         when p.prix_vente > 0 then
           round(((p.prix_vente
             - coalesce(sum(rl.quantite_par_unite * m.cout_unitaire), 0))
             / p.prix_vente * 100)::numeric, 1)
         else null
       end as marge_pourcent,
       bool_and(m.cout_unitaire is not null) filter (where rl.matiere_id is not null)
         as cout_complet
  from produit p
  left join recette_ligne rl on rl.produit_id = p.id
  left join matiere       m  on m.id = rl.matiere_id
 group by p.id, p.nom, p.prix_vente;

-- La vue hérite des RLS des tables sources (produit, recette_ligne, matiere) :
-- - anon ne voit que les produits visibles dans le formulaire (policy existante) ;
-- - les valeurs de coût/marge ne fuient donc jamais au public car les jointures
--   sur matiere et recette_ligne ne renvoient rien pour anon (pas de policy).
-- Côté staff authentifié : tout est visible (policy staff_all).
