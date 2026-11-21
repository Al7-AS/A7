import Link from "next/link";
import { getMessages } from "@/lib/i18n/messages";
import { DEFAULT_LOCALE } from "@/lib/i18n";

// Phase 1 placeholder homepage. Real sections (featured courses, pricing,
// testimonials, FAQ) are built in Phase 2 and read from the database.
export default function HomePage() {
  const t = getMessages(DEFAULT_LOCALE);
  return (
    <main className="mx-auto flex min-h-screen max-w-5xl flex-col justify-center gap-8 px-6 py-24">
      <span className="text-sm font-semibold text-electric">{t.brand}</span>
      <h1 className="text-4xl font-bold leading-tight sm:text-5xl">{t.hero.title}</h1>
      <p className="max-w-2xl text-lg text-ink-500">{t.hero.subtitle}</p>
      <div className="flex flex-wrap gap-3">
        <Link href="/register" className="btn-primary">
          {t.hero.primaryCta}
        </Link>
        <Link href="/courses" className="btn-secondary">
          {t.hero.secondaryCta}
        </Link>
      </div>
    </main>
  );
}
