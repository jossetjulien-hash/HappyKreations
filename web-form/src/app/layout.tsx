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

export const metadata: Metadata = {
  title: "HappyKreations — Créations faites main",
  description: "Coffrets de chocolats & cornets de meringues, façonnés à la main pour vos mariages, baptêmes et événements.",
  openGraph: {
    title: "HappyKreations",
    description: "Créations faites main pour vos événements",
    images: ["/og-image.png"],
    type: "website",
    locale: "fr_FR",
  },
  icons: {
    icon: "/icon.png",
    apple: "/apple-icon.png",
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr" className={`${fraunces.variable} ${caveat.variable} ${nunito.variable}`}>
      <body>{children}</body>
    </html>
  );
}
