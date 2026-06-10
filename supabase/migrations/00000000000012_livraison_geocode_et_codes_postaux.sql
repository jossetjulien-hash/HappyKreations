-- Adresse de livraison géocodée (BAN ou Apple Geocoder) sur commande.
alter table public.commande
  add column adresse_livraison text,
  add column latitude  numeric(10,7),
  add column longitude numeric(10,7);

comment on column public.commande.adresse_livraison is 'Adresse postale BAN (Base Adresse Nationale française), résolue côté client';
comment on column public.commande.latitude is 'Coordonnée GPS WGS84 (BAN ou Apple Geocoder)';
comment on column public.commande.longitude is 'Coordonnée GPS WGS84 (BAN ou Apple Geocoder)';

-- Codes postaux par zone pour la détection automatique.
alter table public.zone_livraison
  add column codes_postaux text[] not null default '{}';

comment on column public.zone_livraison.codes_postaux is 'Liste de codes postaux couverts par cette zone, pour la détection automatique depuis l''adresse BAN';

-- Pré-remplir les zones par défaut avec leurs codes postaux Réunion.
update public.zone_livraison set codes_postaux = array[
  '97400','97438','97441'
] where nom like 'Nord%';

update public.zone_livraison set codes_postaux = array[
  '97419','97420','97426','97434','97435','97436','97416','97411','97460','97422','97423'
] where nom like 'Ouest%';

update public.zone_livraison set codes_postaux = array[
  '97410','97414','97418','97425','97427','97429','97430','97432','97442','97450','97480'
] where nom like 'Sud%';

update public.zone_livraison set codes_postaux = array[
  '97412','97439','97440','97470','97431','97437'
] where nom like 'Est%';

update public.zone_livraison set codes_postaux = array[
  '97413','97433'
] where nom like 'Cirques%';
