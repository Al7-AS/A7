/**
 * Payment status is changed ONLY by verified provider webhooks.
 * Client redirects, success pages and query parameters are never proof of payment.
 *
 * This module defines the contract. Provider adapters (Stripe, Paymob) implement
 * `verifyWebhook` with real signature checks; until their keys are configured,
 * they throw, and no payment is recorded as succeeded.
 */

export type PaymentProvider = "stripe" | "paymob";

export interface VerifiedPaymentEvent {
  provider: PaymentProvider;
  providerReference: string;
  status: "succeeded" | "failed" | "refunded";
  amountCents: number;
  currency: string;
}

export interface PaymentAdapter {
  readonly provider: PaymentProvider;
  /** Throws if the signature is invalid or the adapter is not configured. */
  verifyWebhook(rawBody: string, headers: Record<string, string>): Promise<VerifiedPaymentEvent>;
}

export class PaymentNotConfiguredError extends Error {
  constructor(provider: PaymentProvider) {
    super(`${provider} is not configured. Set its environment variables in .env.local.`);
    this.name = "PaymentNotConfiguredError";
  }
}

const adapters: Partial<Record<PaymentProvider, PaymentAdapter>> = {};

export function registerAdapter(adapter: PaymentAdapter): void {
  adapters[adapter.provider] = adapter;
}

export function getAdapter(provider: PaymentProvider): PaymentAdapter {
  const adapter = adapters[provider];
  if (!adapter) throw new PaymentNotConfiguredError(provider);
  return adapter;
}
