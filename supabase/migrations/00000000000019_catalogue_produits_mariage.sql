-- Ajoute les produits du catalogue Big Cartel absents de l'app.
--
-- Garde anti-doublon sur le nom (comparaison insensible à la casse et aux
-- espaces) : les produits déjà saisis à la main dans l'app ne sont pas
-- dupliqués, et leurs prix / parfums / quantités restent intacts.
--
-- visible_formulaire = false : rien n'est publié sur le formulaire public
-- tant que l'artisan ne bascule pas le produit lui-même depuis l'app.

insert into public.produit
  (nom, categorie_id, prix_vente, declinaisons, visible_formulaire, actif,
   qte_min, qte_max, max_parfums_par_commande)
select v.nom, c.id, v.prix, v.decli, false, true, v.qte_min, null, v.maxp
from (values
  ('Carte de chocolat',                    'Chocolats',              1.30,  array[]::text[], 30,        1),
  ('Boîte choco/meringues',                'Coffrets & boîtes',      6.50,
     array['Nature','Fleurs d’oranger','Fruits rouge','Ananas','Passion','Caramel beurre salé'], null::int, 2),
  ('Cadre de bienvenue',                   'Mariage & personnalisé', 50.00, array[]::text[], null::int, 1),
  ('Panneau de bienvenue gravé sur bois',  'Mariage & personnalisé', 80.00, array[]::text[], null::int, 1),
  ('Demande de témoin — homme',            'Mariage & personnalisé', 25.00, array[]::text[], null::int, 1),
  ('Demande de la témoin — personnalisée', 'Mariage & personnalisé', 25.00, array[]::text[], null::int, 1),
  ('Plante grasse personnalisée',          'Mariage & personnalisé',  5.50, array[]::text[], null::int, 1),
  ('Roll up personnalisé 800×2000',        'Mariage & personnalisé',160.00, array[]::text[], null::int, 1)
) as v(nom, cat, prix, decli, qte_min, maxp)
join public.categorie_produit c on c.nom = v.cat
where not exists (
  select 1 from public.produit p where lower(trim(p.nom)) = lower(v.nom)
);
