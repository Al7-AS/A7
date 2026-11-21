// Paymob Accept API (Egypt). Server-only: uses PAYMOB_API_KEY and PAYMOB_HMAC_SECRET.
import crypto from "node:crypto";

const API = "https://accept.paymob.com/api";

async function post(path, body) {
  const res = await fetch(`${API}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`Paymob ${path} failed (${res.status}): ${JSON.stringify(data)}`);
  return data;
}

/** Step 1: exchange the API key for a short-lived auth token. */
export async function authToken() {
  const data = await post("/auth/tokens", { api_key: process.env.PAYMOB_API_KEY });
  return data.token;
}

/** Step 2: register the order. merchantOrderId links it back to our DB row. */
export async function registerOrder(token, { amountCents, currency, merchantOrderId }) {
  const data = await post("/ecommerce/orders", {
    auth_token: token,
    delivery_needed: false,
    amount_cents: amountCents,
    currency,
    merchant_order_id: merchantOrderId,
    items: [],
  });
  return data.id;
}

/** Step 3: create a payment key bound to the order and the buyer's billing data. */
export async function paymentKey(token, { orderId, amountCents, currency, billing }) {
  const data = await post("/acceptance/payment_keys", {
    auth_token: token,
    amount_cents: amountCents,
    expiration: 3600,
    order_id: orderId,
    currency,
    integration_id: Number(process.env.PAYMOB_INTEGRATION_ID),
    billing_data: {
      first_name: billing.firstName,
      last_name: billing.lastName,
      email: billing.email,
      phone_number: billing.phone,
      // Paymob requires these keys; "NA" is the accepted placeholder.
      apartment: "NA",
      floor: "NA",
      street: "NA",
      building: "NA",
      shipping_method: "NA",
      postal_code: "NA",
      city: "NA",
      country: "EG",
      state: "NA",
    },
  });
  return data.token;
}

export function iframeUrl(paymentToken) {
  return `${API}/acceptance/iframes/${process.env.PAYMOB_IFRAME_ID}?payment_token=${paymentToken}`;
}

/**
 * Verifies the HMAC-SHA512 signature on a Paymob transaction callback.
 * Field order is fixed by Paymob; do not reorder. Check against the current
 * Paymob docs when you first set this up.
 */
const HMAC_FIELDS = [
  "amount_cents", "created_at", "currency", "error_occured", "has_parent_transaction",
  "id", "integration_id", "is_3d_secure", "is_auth", "is_capture", "is_refunded",
  "is_standalone_payment", "is_voided", "order.id", "owner", "pending",
  "source_data.pan", "source_data.sub_type", "source_data.type", "success",
];

function readPath(obj, path) {
  return path.split(".").reduce((o, k) => (o == null ? undefined : o[k]), obj);
}

export function verifyHmac(obj, receivedHmac) {
  const secret = process.env.PAYMOB_HMAC_SECRET;
  if (!secret || !receivedHmac) return false;
  const concatenated = HMAC_FIELDS.map((f) => {
    const v = readPath(obj, f);
    return v === undefined || v === null ? "" : String(v);
  }).join("");
  const expected = crypto.createHmac("sha512", secret).update(concatenated).digest("hex");
  const a = Buffer.from(expected);
  const b = Buffer.from(String(receivedHmac));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
