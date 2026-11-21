import type { PoolClient } from "pg";

export interface TenantContext {
  userId: string;
  tenantId: string | null;
  isSuperAdmin: boolean;
}

/**
 * Every request that touches tenant data runs inside a transaction that first
 * binds the verified identity to Postgres. RLS policies (see 0001_init.sql)
 * read these settings, so isolation holds even if a query forgets a WHERE clause.
 *
 * Only call this with a context derived from a verified server-side session.
 * Never build a TenantContext from request body or query parameters.
 */
export async function bindTenantContext(client: PoolClient, ctx: TenantContext): Promise<void> {
  await client.query("SELECT set_config('app.current_user_id', $1, true)", [ctx.userId]);
  await client.query("SELECT set_config('app.current_tenant_id', $1, true)", [ctx.tenantId ?? ""]);
  await client.query("SELECT set_config('app.is_super_admin', $1, true)", [ctx.isSuperAdmin ? "true" : "false"]);
}
