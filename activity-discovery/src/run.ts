#!/usr/bin/env node
/**
 * CLI entrypoint for running activity discovery providers
 *
 * Usage:
 *   npx tsx src/run.ts --provider github --account github-personal --daysBack 30
 *   npx tsx src/run.ts --provider all --daysBack 7
 *   npx tsx src/run.ts --provider gitlab --account gitlab-work --timeMin 2024-01-01 --timeMax 2024-01-31
 */

import type {
  Provider,
  FetchWindow,
  UnifiedActivity,
  ActivityOutput,
} from '../schemas/index.js';
import { aggregateToHeatmap } from './aggregation.js';
import type { GitHubAccountConfig } from '../providers/github/index.js';
import type { GitLabAccountConfig } from '../providers/gitlab/index.js';
import type { AzureDevOpsAccountConfig } from '../providers/azure-devops/index.js';
import type { GoogleCalendarAccountConfig } from '../providers/google-calendar/index.js';
import { fetchGitHubActivities } from '../providers/github/index.js';
import { fetchGitLabActivities } from '../providers/gitlab/index.js';
import { fetchAzureDevOpsActivities } from '../providers/azure-devops/index.js';
import { fetchGoogleCalendarActivities } from '../providers/google-calendar/index.js';

/**
 * Configuration file structure
 */
interface Config {
  providers: {
    github?: { accounts: GitHubAccountConfig[] };
    gitlab?: { accounts: GitLabAccountConfig[] };
    'azure-devops'?: { accounts: AzureDevOpsAccountConfig[] };
    'google-calendar'?: { accounts: GoogleCalendarAccountConfig[] };
  };
  fetchWindow?: {
    daysBack?: number;
    timeMin?: string;
    timeMax?: string;
  };
}

interface CliArgs {
  provider: Provider | 'all';
  account?: string;
  daysBack?: number;
  timeMin?: string;
  timeMax?: string;
  config?: string;
  output?: string;
}

/**
 * Result of fetching from a single account
 */
interface AccountFetchResult {
  provider: Provider;
  accountId: string;
  activities: UnifiedActivity[];
  error?: string;
}

function parseArgs(args: string[]): CliArgs {
  const result: Partial<CliArgs> = {};

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    const nextArg = args[i + 1];

    switch (arg) {
      case '--provider':
        result.provider = nextArg as Provider | 'all';
        i++;
        break;
      case '--account':
        result.account = nextArg;
        i++;
        break;
      case '--daysBack':
        result.daysBack = parseInt(nextArg, 10);
        i++;
        break;
      case '--timeMin':
        result.timeMin = nextArg;
        i++;
        break;
      case '--timeMax':
        result.timeMax = nextArg;
        i++;
        break;
      case '--config':
        result.config = nextArg;
        i++;
        break;
      case '--output':
        result.output = nextArg;
        i++;
        break;
      case '--help':
        printHelp();
        process.exit(0);
    }
  }

  if (!result.provider) {
    console.error('Error: --provider is required');
    printHelp();
    process.exit(1);
  }

  if (!result.daysBack && !result.timeMin) {
    result.daysBack = 30; // Default to 30 days back
  }

  return result as CliArgs;
}

function printHelp(): void {
  console.log(`
Activity Discovery CLI

Usage:
  npx tsx src/run.ts [options]

Options:
  --provider <name>    Provider to run: github, gitlab, azure-devops, google-calendar, or 'all'
  --account <id>       Account ID from config (optional, runs all accounts for provider if omitted)
  --daysBack <n>       Number of days to look back (default: 30)
  --timeMin <date>     Start of time window (ISO8601)
  --timeMax <date>     End of time window (ISO8601)
  --config <path>      Path to config file (default: ./config.json)
  --output <path>      Output file path (default: stdout)
  --help               Show this help message

Examples:
  npx tsx src/run.ts --provider github --daysBack 7
  npx tsx src/run.ts --provider all --account work --daysBack 30
  npx tsx src/run.ts --provider gitlab --timeMin 2024-01-01 --timeMax 2024-01-31
`);
}

function buildFetchWindow(args: CliArgs): FetchWindow {
  if (args.timeMin || args.timeMax) {
    return {
      timeMin: args.timeMin,
      timeMax: args.timeMax ?? new Date().toISOString(),
    };
  }

  const daysBack = args.daysBack ?? 30;
  const now = new Date();
  const timeMin = new Date(now.getTime() - daysBack * 24 * 60 * 60 * 1000);

  return {
    daysBack,
    timeMin: timeMin.toISOString(),
    timeMax: now.toISOString(),
  };
}

/**
 * Load configuration from file
 */
async function loadConfig(configPath: string): Promise<Config> {
  const fs = await import('fs/promises');

  try {
    const content = await fs.readFile(configPath, 'utf-8');
    return JSON.parse(content) as Config;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
      throw new Error(`Config file not found: ${configPath}`);
    }
    throw new Error(`Failed to parse config file: ${(error as Error).message}`);
  }
}

/**
 * Fetch activities from a GitHub account
 */
async function fetchFromGitHub(
  account: GitHubAccountConfig,
  window: FetchWindow
): Promise<AccountFetchResult> {
  try {
    const activities = await fetchGitHubActivities({ account, window });
    return { provider: 'github', accountId: account.id, activities };
  } catch (error) {
    const errorMessage = (error as Error).message;
    console.error(`[github:${account.id}] Error: ${errorMessage}`);
    return { provider: 'github', accountId: account.id, activities: [], error: errorMessage };
  }
}

/**
 * Fetch activities from a GitLab account
 */
async function fetchFromGitLab(
  account: GitLabAccountConfig,
  window: FetchWindow
): Promise<AccountFetchResult> {
  try {
    const activities = await fetchGitLabActivities({ account, window });
    return { provider: 'gitlab', accountId: account.id, activities };
  } catch (error) {
    const errorMessage = (error as Error).message;
    console.error(`[gitlab:${account.id}] Error: ${errorMessage}`);
    return { provider: 'gitlab', accountId: account.id, activities: [], error: errorMessage };
  }
}

/**
 * Fetch activities from an Azure DevOps account
 */
async function fetchFromAzureDevOps(
  account: AzureDevOpsAccountConfig,
  window: FetchWindow
): Promise<AccountFetchResult> {
  try {
    const activities = await fetchAzureDevOpsActivities({ account, window });
    return { provider: 'azure-devops', accountId: account.id, activities };
  } catch (error) {
    const errorMessage = (error as Error).message;
    console.error(`[azure-devops:${account.id}] Error: ${errorMessage}`);
    return { provider: 'azure-devops', accountId: account.id, activities: [], error: errorMessage };
  }
}

/**
 * Fetch activities from a Google Calendar account
 */
async function fetchFromGoogleCalendar(
  account: GoogleCalendarAccountConfig,
  window: FetchWindow
): Promise<AccountFetchResult> {
  try {
    const activities = await fetchGoogleCalendarActivities({ account, window });
    return { provider: 'google-calendar', accountId: account.id, activities };
  } catch (error) {
    const errorMessage = (error as Error).message;
    console.error(`[google-calendar:${account.id}] Error: ${errorMessage}`);
    return { provider: 'google-calendar', accountId: account.id, activities: [], error: errorMessage };
  }
}

/**
 * Get accounts for a provider, optionally filtered by account ID
 */
function getAccountsForProvider<T extends { id: string }>(
  accounts: T[] | undefined,
  accountFilter?: string
): T[] {
  if (!accounts) {
    return [];
  }

  if (accountFilter) {
    return accounts.filter((a) => a.id === accountFilter || a.id.includes(accountFilter));
  }

  return accounts;
}

/**
 * Fetch activities from all configured providers
 */
async function fetchAllProviders(
  config: Config,
  window: FetchWindow,
  accountFilter?: string
): Promise<AccountFetchResult[]> {
  const results: AccountFetchResult[] = [];

  // GitHub
  const githubAccounts = getAccountsForProvider(config.providers.github?.accounts, accountFilter);
  for (const account of githubAccounts) {
    results.push(await fetchFromGitHub(account, window));
  }

  // GitLab
  const gitlabAccounts = getAccountsForProvider(config.providers.gitlab?.accounts, accountFilter);
  for (const account of gitlabAccounts) {
    results.push(await fetchFromGitLab(account, window));
  }

  // Azure DevOps
  const azureAccounts = getAccountsForProvider(config.providers['azure-devops']?.accounts, accountFilter);
  for (const account of azureAccounts) {
    results.push(await fetchFromAzureDevOps(account, window));
  }

  // Google Calendar
  const googleAccounts = getAccountsForProvider(config.providers['google-calendar']?.accounts, accountFilter);
  for (const account of googleAccounts) {
    results.push(await fetchFromGoogleCalendar(account, window));
  }

  return results;
}

/**
 * Fetch activities from a specific provider
 */
async function fetchProvider(
  provider: Provider,
  config: Config,
  window: FetchWindow,
  accountFilter?: string
): Promise<AccountFetchResult[]> {
  const results: AccountFetchResult[] = [];

  switch (provider) {
    case 'github': {
      const accounts = getAccountsForProvider(config.providers.github?.accounts, accountFilter);
      for (const account of accounts) {
        results.push(await fetchFromGitHub(account, window));
      }
      break;
    }
    case 'gitlab': {
      const accounts = getAccountsForProvider(config.providers.gitlab?.accounts, accountFilter);
      for (const account of accounts) {
        results.push(await fetchFromGitLab(account, window));
      }
      break;
    }
    case 'azure-devops': {
      const accounts = getAccountsForProvider(config.providers['azure-devops']?.accounts, accountFilter);
      for (const account of accounts) {
        results.push(await fetchFromAzureDevOps(account, window));
      }
      break;
    }
    case 'google-calendar': {
      const accounts = getAccountsForProvider(config.providers['google-calendar']?.accounts, accountFilter);
      for (const account of accounts) {
        results.push(await fetchFromGoogleCalendar(account, window));
      }
      break;
    }
  }

  return results;
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const fetchWindow = buildFetchWindow(args);
  const configPath = args.config ?? './config.json';

  console.error(`Activity Discovery CLI`);
  console.error(`Provider: ${args.provider}`);
  console.error(`Account filter: ${args.account ?? 'all'}`);
  console.error(`Config: ${configPath}`);
  console.error(`Window: ${fetchWindow.timeMin} to ${fetchWindow.timeMax}`);
  console.error('');

  // Load config
  const config = await loadConfig(configPath);

  // Fetch activities
  let results: AccountFetchResult[];
  if (args.provider === 'all') {
    results = await fetchAllProviders(config, fetchWindow, args.account);
  } else {
    results = await fetchProvider(args.provider, config, fetchWindow, args.account);
  }

  // Merge all activities
  const allActivities: UnifiedActivity[] = [];
  const errors: Array<{ provider: Provider; accountId: string; error: string }> = [];

  for (const result of results) {
    allActivities.push(...result.activities);
    if (result.error) {
      errors.push({ provider: result.provider, accountId: result.accountId, error: result.error });
    }
  }

  // Sort by timestamp descending
  allActivities.sort((a, b) => b.timestamp.localeCompare(a.timestamp));

  // Generate heatmap
  const heatmap = aggregateToHeatmap(allActivities);

  // Build output
  const output: ActivityOutput & { errors?: typeof errors } = {
    activities: allActivities,
    heatmap,
  };

  if (errors.length > 0) {
    output.errors = errors;
  }

  // Summary
  console.error(`Fetched ${allActivities.length} activities from ${results.length} accounts`);
  if (errors.length > 0) {
    console.error(`Errors: ${errors.length} accounts failed`);
  }
  console.error('');

  const json = JSON.stringify(output, null, 2);

  if (args.output) {
    const fs = await import('fs/promises');
    await fs.writeFile(args.output, json);
    console.error(`Output written to: ${args.output}`);
  } else {
    console.log(json);
  }
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
