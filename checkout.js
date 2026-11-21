import { COURSES } from "../lib/courses.js";
import { sb } from "../lib/supabase.js";
import { authToken, registerOrder, paymentKey, iframeUrl } from "../lib/paymob.js";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_RE = /^\+?[0-9]{10,15}$/;

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "method_not_allowed" });

  const { courseId, firstName, lastName, email, phone } = req.body || {};
  const course = COURSES[courseId];
  if (!course) return res.status(400).json({ error: "unknown_course" });
  if (!firstName || !lastName) return res.status(400).json({ error: "name_required" });
  if (!EMAIL_RE.test(email || "")) return res.status(400).json({ error: "invalid_email" });
  if (!PHONE_RE.test(phone || "")) return res.status(400).json({ error: "invalid_phone" });

  try {
    // 1) Store a pending order first. Its id is our merchant_order_id.
    const [order] = await sb("orders", {
      method: "POST",
      body: {
        course_id: course.id,
        email,
        amount_cents: course.price_cents,
        currency: course.currency,
        status: "pending",
      },
    });

    // 2) Create the Paymob order and payment key. The amount comes from the server.
    const token = await authToken();
    const paymobOrderId = await registerOrder(token, {
      amountCents: course.price_cents,
      currency: course.currency,
      merchantOrderId: order.id,
    });
    await sb(`orders?id=eq.${order.id}`, {
      method: "PATCH",
      body: { paymob_order_id: String(paymobOrderId) },
      prefer: "return=minimal",
    });

    const key = await paymentKey(token, {
      orderId: paymobOrderId,
      amountCents: course.price_cents,
      currency: course.currency,
      billing: { firstName, lastName, email, phone },
    });

    return res.status(200).json({ orderId: order.id, iframeUrl: iframeUrl(key) });
  } catch (err) {
    console.error("checkout failed:", err);
    return res.status(502).json({ error: "payment_provider_error" });
  }
}
