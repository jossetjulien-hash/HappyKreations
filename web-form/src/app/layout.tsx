import "./globals.css";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "HappyKreations — Commander",
  description: "Coffrets de chocolats et cornets de meringues pour vos événements",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr">
      <body>{children}</body>
    </html>
  );
}
