// Source of truth for prices and paid content. Lives on the server only.
// The browser never sends a price; it only sends a courseId.
export const COURSES = {
  "design-101": {
    id: "design-101",
    title: "أساسيات تصميم الهوية البصرية",
    price_cents: 49900, // 499.00 EGP
    currency: "EGP",
    lessons: [
      { title: "مقدمة في الهوية البصرية", content: "محتوى الدرس الأول يُكتب هنا." },
      { title: "الألوان والخطوط", content: "محتوى الدرس الثاني يُكتب هنا." },
    ],
  },
  "web-201": {
    id: "web-201",
    title: "بناء تطبيق ويب كامل بملف واحد",
    price_cents: 79900,
    currency: "EGP",
    lessons: [
      { title: "هيكلة الملف", content: "محتوى الدرس الأول يُكتب هنا." },
      { title: "قاعدة البيانات والحفظ", content: "محتوى الدرس الثاني يُكتب هنا." },
    ],
  },
};
