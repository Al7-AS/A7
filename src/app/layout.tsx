import type { Metadata } from "next";
import { Inter, Cairo } from "next/font/google";
import "./globals.css";
import { DEFAULT_LOCALE, dirFor } from "@/lib/i18n";

const inter = Inter({ subsets: ["latin"], variable: "--font-inter", display: "swap" });
const cairo = Cairo({ subsets: ["arabic", "latin"], variable: "--font-cairo", display: "swap" });

export const metadata: Metadata = {
  title: {
    default: "LearnSphere",
    template: "%s | LearnSphere",
  },
  description: "منصة تعليمية احترافية متعددة المدرّسين | Premium multi-instructor learning platform",
};

// Phase 1: a single default locale. Phase 2 moves this under app/[locale]/
// so the direction and language follow the URL, and the user's choice persists.
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html
      lang={DEFAULT_LOCALE}
      dir={dirFor(DEFAULT_LOCALE)}
      className={`${inter.variable} ${cairo.variable}`}
      suppressHydrationWarning
    >
      <body>{children}</body>
    </html>
  );
}
