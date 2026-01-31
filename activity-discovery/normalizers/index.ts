/**
 * Normalizers for converting provider-specific data to UnifiedActivity format
 *
 * Each normalizer module exports a normalize function that:
 * - Takes raw provider-specific activity data
 * - Returns UnifiedActivity[] conforming to the schema
 * - Enforces UTC timestamps
 * - Maps provider-specific types to ActivityType
 */

export type { UnifiedActivity, ActivityType } from '../schemas/index.js';

// Types
export * from './types.js';

// Mapping tables
export * from './mappings.js';

// Utility functions
export * from './utils.js';
