/**
 * Provider-agnostic normalization types and interfaces
 */

import type { UnifiedActivity, ActivityType, Provider, FetchWindow } from '../schemas/index.js';

/**
 * Common interface for all provider normalizers
 */
export interface ProviderNormalizer<TRaw> {
  /** Provider identifier */
  provider: Provider;
  /** Normalize raw provider data to UnifiedActivity */
  normalize(raw: TRaw, accountId: string): UnifiedActivity | null;
  /** Normalize multiple raw items */
  normalizeAll(items: TRaw[], accountId: string): UnifiedActivity[];
}

/**
 * Provider fetch options
 */
export interface ProviderFetchOptions {
  accountId: string;
  window: FetchWindow;
}

/**
 * Provider fetch result
 */
export interface ProviderFetchResult {
  provider: Provider;
  accountId: string;
  activities: UnifiedActivity[];
  errors?: string[];
}

/**
 * Activity type mapping entry
 */
export interface TypeMappingEntry {
  /** Source type/action from provider */
  source: string;
  /** Target UnifiedActivity type */
  target: ActivityType;
  /** Optional description */
  description?: string;
}

/**
 * Provider type mapping table
 */
export interface ProviderTypeMapping {
  provider: Provider;
  mappings: TypeMappingEntry[];
}
