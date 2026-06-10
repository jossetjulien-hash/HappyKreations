export interface Produit {
  id: string;
  nom: string;
  categorie: "coffret" | "cornet";
  prix_vente: number;
  declinaisons: string[];
  visible_formulaire: boolean;
  actif: boolean;
  photo_url: string | null;
  qte_min: number | null;
  qte_max: number | null;
}

export interface ZoneLivraison {
  id: string;
  nom: string;
  tarif: number;
  description: string | null;
  ordre: number;
  actif: boolean;
}

export interface CapaciteJour {
  date: string;
  plafond_unites: number | null;
  bloque: boolean;
}

export interface ConfigItem {
  cle: string;
  valeur: string;
}

export interface LigneCommande {
  produit_id: string;
  quantite: number;
  declinaison?: string;
}

export interface ClientInfo {
  nom: string;
  telephone?: string;
  email?: string;
  messenger?: string;
}
