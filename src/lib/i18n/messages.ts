import type { Locale } from "./index";

// Phase 1 keeps the dictionary small. Add keys here, never inline strings in components.
export const messages = {
  ar: {
    brand: "LearnSphere",
    nav: {
      home: "الرئيسية",
      courses: "الدورات",
      pricing: "الأسعار",
      faq: "الأسئلة الشائعة",
      contact: "تواصل معنا",
      login: "تسجيل الدخول",
      register: "إنشاء حساب",
    },
    hero: {
      title: "منصة تعليمية احترافية لكل مؤسسة ومدرّس",
      subtitle: "أنشئ مساحة عمل مستقلة، ونظّم دوراتك وطلابك ومدفوعاتك في مكان واحد.",
      primaryCta: "ابدأ مجاناً",
      secondaryCta: "استكشف الدورات",
    },
    footer: {
      rights: "جميع الحقوق محفوظة",
    },
  },
  en: {
    brand: "LearnSphere",
    nav: {
      home: "Home",
      courses: "Courses",
      pricing: "Pricing",
      faq: "FAQ",
      contact: "Contact",
      login: "Log in",
      register: "Sign up",
    },
    hero: {
      title: "A premium learning platform for every institution and instructor",
      subtitle: "Create an independent workspace and manage courses, students and payments in one place.",
      primaryCta: "Start free",
      secondaryCta: "Explore courses",
    },
    footer: {
      rights: "All rights reserved",
    },
  },
} as const satisfies Record<Locale, unknown>;

export type Messages = (typeof messages)[Locale];

export function getMessages(locale: Locale): Messages {
  return messages[locale];
}
