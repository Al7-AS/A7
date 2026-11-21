import { Pool, type PoolClient } from "pg";
import { bindTenantContext, type TenantContext } from "@/lib/tenancy/context";

// Server-only module. Importing it from a client component is a build error by design.
if (typeof window !== "undefined") {
  throw new Error("db/client must never be imported in the browser");
}

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error("DATABASE_URL is not set. See .env.example.");
}

// The app connects as a NON-superuser role. Superusers bypass RLS.
declare global {
  // eslint-disable-next-line no-var
  var __lsPool: Pool | undefined;
}

export const pool: Pool =
  globalThis.__lsPool ??
  new Pool({ connectionString, max: 10, idleTimeoutMillis: 30_000 });

if (process.env.NODE_ENV !== "production") globalThis.__lsPool = pool;

/** Runs `fn` in a transaction with the caller's tenant context bound for RLS. */
export async function withTenant<T>(
  ctx: TenantContext,
  fn: (client: PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await bindTenantContext(client, ctx);
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }
}
