-- Durcissement : le bucket `produits` est public, les photos sont servies via
-- l'URL publique sans avoir besoin d'une policy SELECT sur storage.objects.
-- On retire la policy de lecture large qui permettait de LISTER tous les
-- fichiers (énumération inutile). L'écriture reste réservée au staff.

drop policy if exists produits_public_read on storage.objects;
