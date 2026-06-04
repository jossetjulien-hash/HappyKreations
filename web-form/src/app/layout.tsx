import "./globals.css";
import type { Metadata } from "next";
import { Fraunces, Caveat, Nunito_Sans } from "next/font/google";

const fraunces = Fraunces({
  subsets: ["latin"],
  weight: ["300", "400", "500"],
  style: ["normal", "italic"],
  variable: "--font-fraunces",
  display: "swap",
});
const caveat = Caveat({
  subsets: ["latin"],
  weight: ["500", "600", "700"],
  variable: "--font-caveat",
  display: "swap",
});
const nunito = Nunito_Sans({
  subsets: ["latin"],
  weight: ["300", "400", "600", "700"],
  variable: "--font-nunito",
  display: "swap",
});

const SITE_URL = "https://commande.happykreations.fr";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: "HappyKreations — Créations faites main",
    template: "%s · HappyKreations",
  },
  description: "Coffrets de chocolats & cornets de meringues, façonnés à la main pour vos mariages, baptêmes et événements.",
  alternates: { canonical: "/" },
  openGraph: {
    title: "HappyKreations",
    description: "Créations faites main pour vos événements",
    images: ["/og-image.png"],
    type: "website",
    locale: "fr_FR",
    siteName: "HappyKreations",
    url: SITE_URL,
  },
  twitter: {
    card: "summary_large_image",
    title: "HappyKreations",
    description: "Créations faites main pour vos événements",
    images: ["/og-image.png"],
  },
  icons: {
    icon: "/icon.png",
    apple: "/apple-icon.png",
  },
  robots: { index: true, follow: true },
};

const jsonLd = {
  "@context": "https://schema.org",
  "@type": "LocalBusiness",
  name: "HappyKreations",
  description: "Coffrets de chocolats et cornets de meringues faits main pour mariages, baptêmes et événements.",
  url: SITE_URL,
  image: `${SITE_URL}/icon.png`,
  logo: `${SITE_URL}/icon.png`,
  priceRange: "€€",
  paymentAccepted: "Credit Card, Stripe",
  currenciesAccepted: "EUR",
  servesCuisine: "French, Artisan",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr" className={`${fraunces.variable} ${caveat.variable} ${nunito.variable}`}>
      <head>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
