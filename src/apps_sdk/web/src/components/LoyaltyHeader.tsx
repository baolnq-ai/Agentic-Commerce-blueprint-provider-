import { ShoppingBag } from "lucide-react";
import type { MerchantUser } from "@/types";

type NavbarTelemetry = {
  page: string;
  mode: string;
  model: string;
  runtime: string;
  source: string;
  activity: string;
};

interface LoyaltyHeaderProps {
  user: MerchantUser;
  cartItemCount?: number;
  onCartClick?: () => void;
  telemetry?: NavbarTelemetry | null;
}

/**
 * LoyaltyHeader Component
 *
 * Clean, minimalist header with store branding and user info.
 * Uses a single accent color and text hierarchy for visual clarity.
 */
export function LoyaltyHeader({
  user,
  cartItemCount = 0,
  onCartClick,
  telemetry = null,
}: LoyaltyHeaderProps) {
  return (
    <header className="border-b border-default/50 bg-surface px-4 py-3 pr-12 transition-colors">
      <div className="flex items-center justify-between gap-2">
        {/* Store Branding */}
        <span className="text-base font-semibold tracking-tight text-text">
          NVShop
        </span>

        {/* User Info + Cart */}
        <div className="flex min-w-0 items-center gap-3">
          {/* Combined user info - clean text hierarchy */}
          <div className="flex min-w-0 items-center gap-2 text-sm">
            <span className="text-text">{user.name}</span>
            <span className="text-text-tertiary">·</span>
            <span className="font-medium text-accent">{user.tier}</span>
            <span className="text-text-tertiary">·</span>
            <span className="truncate text-text-secondary max-[420px]:hidden">
              {user.loyaltyPoints.toLocaleString()} pts
            </span>
          </div>

          {/* Cart Icon - only accent element */}
          {onCartClick && (
            <button
              onClick={onCartClick}
              className="relative flex h-9 w-9 items-center justify-center rounded-full bg-accent/10 transition-colors hover:bg-accent/20 dark:bg-accent/20 dark:hover:bg-accent/30"
              aria-label={`Shopping cart with ${cartItemCount} items`}
            >
              <ShoppingBag className="h-5 w-5 text-accent" strokeWidth={2} />
              {cartItemCount > 0 && (
                <span className="absolute -right-1 -top-1 flex h-5 w-5 items-center justify-center rounded-full bg-accent text-xs font-bold text-white shadow-sm">
                  {cartItemCount > 9 ? "9+" : cartItemCount}
                </span>
              )}
            </button>
          )}
        </div>
      </div>

      {telemetry && (
        <div className="mt-2 rounded-lg border border-default bg-surface-elevated/70 px-2 py-1.5 text-[10px] text-text-secondary">
          <div className="flex items-center gap-2">
            <span className="rounded-md border border-accent/45 bg-accent/10 px-1.5 py-0.5 text-[9px] font-semibold uppercase tracking-wide text-accent">
              mode {telemetry.mode}
            </span>
            <span className="truncate">{telemetry.page} · {telemetry.runtime} · {telemetry.source}</span>
          </div>

          <div className="mt-1 flex items-center gap-2" title={telemetry.model}>
            <span className="shrink-0 uppercase tracking-wide text-text-tertiary">model</span>
            <span className="truncate">{telemetry.model}</span>
          </div>

          <div className="mt-1 flex items-center gap-2" title={telemetry.activity}>
            <span className="shrink-0 uppercase tracking-wide text-text-tertiary">activity</span>
            <span className="truncate">{telemetry.activity}</span>
          </div>
        </div>
      )}
    </header>
  );
}
