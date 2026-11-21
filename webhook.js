import { sb } from "../lib/supabase.js";
import { verifyHmac } from "../lib/paymob.js";

// Paymob calls this after every transaction. Only a valid signature plus a
// successful transaction can mark an order as paid.
export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).end();

  const obj = req.body?.obj;
  const receivedHmac = req.query?.hmac;

  if (!obj || !verifyHmac(obj, receivedHmac)) {
    console.warn("webhook rejected: bad signature");
    return res.status(401).json({ error: "invalid_signature" });
  }

  const merchantOrderId = obj.order?.merchant_order_id;
  if (!merchantOrderId) return res.status(200).json({ ok: true, ignored: "no_merchant_order" });

  // Load the order and compare the amount. A mismatch never grants access.
  const [order] = await sb(`orders?id=eq.${merchantOrderId}&select=*`);
  if (!order) return res.status(200).json({ ok: true, ignored: "unknown_order" });

  const isPaid = obj.success === true && obj.pending === false && obj.is_voided === false && obj.is_refunded === false;
  if (!isPaid) {
    if (obj.success === false) {
      await sb(`orders?id=eq.${order.id}&status=eq.pending`, {
        method: "PATCH",
        body: { status: "failed", paymob_transaction_id: String(obj.id) },
        prefer: "return=minimal",
      });
    }
    return res.status(200).json({ ok: true });
  }

  if (Number(obj.amount_cents) !== order.amount_cents || obj.currency !== order.currency) {
    console.error("webhook amount mismatch for order", order.id);
    return res.status(200).json({ ok: true, ignored: "amount_mismatch" });
  }

  // Idempotent: only a pending order moves to paid.
  await sb(`orders?id=eq.${order.id}&status=eq.pending`, {
    method: "PATCH",
    body: { status: "paid", paid_at: new Date().toISOString(), paymob_transaction_id: String(obj.id) },
    prefer: "return=minimal",
  });

  return res.status(200).json({ ok: true });
}
