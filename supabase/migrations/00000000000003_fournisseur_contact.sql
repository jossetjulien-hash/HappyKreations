-- Fournisseurs : champs structurés type "fiche contact" iOS.
-- L'ancien champ `contact` (texte libre) est conservé pour compat,
-- et migré au mieux : si ressemble à un email → email, sinon → telephone.

alter table fournisseur add column if not exists telephone text;
alter table fournisseur add column if not exists email     text;
alter table fournisseur add column if not exists adresse   text;

update fournisseur
   set email = contact
 where email is null
   and telephone is null
   and contact is not null
   and contact like '%@%';

update fournisseur
   set telephone = contact
 where email is null
   and telephone is null
   and contact is not null;
