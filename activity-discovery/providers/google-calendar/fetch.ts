/**
 * Google Calendar provider fetch implementation
 *
 * Uses Google Calendar REST API to fetch event data with minimal fields.
 * Supports multiple accounts and multiple calendars per account.
 */

import type { UnifiedActivity, FetchWindow } from '../../schemas/index.js';
import type {
  GoogleCalendarAccountConfig,
  GoogleCalendarFetchOptions,
  GoogleCalendarEvent,
  GoogleCalendarEventsResponse,
  GoogleOAuthCredentials,
  GoogleTokenResponse,
} from './types.js';

const GOOGLE_TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
const GOOGLE_CALENDAR_API = 'https://www.googleapis.com/calendar/v3';

/**
 * Get access token from refresh token
 */
async function getAccessToken(credentials: GoogleOAuthCredentials): Promise<string> {
  const params = new URLSearchParams({
    client_id: credentials.clientId,
    client_secret: credentials.clientSecret,
    refresh_token: credentials.refreshToken,
    grant_type: 'refresh_token',
  });

  const response = await fetch(GOOGLE_TOKEN_ENDPOINT, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: params.toString(),
  });

  if (!response.ok) {
    throw new Error(`Google OAuth error: ${response.status} ${response.statusText}`);
  }

  const data = (await response.json()) as GoogleTokenResponse;
  return data.access_token;
}

/**
 * Execute a Calendar API request
 */
async function fetchCalendarAPI<T>(
  accessToken: string,
  endpoint: string,
  params: Record<string, string> = {}
): Promise<T> {
  const url = new URL(`${GOOGLE_CALENDAR_API}${endpoint}`);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }

  const response = await fetch(url.toString(), {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
  });

  if (!response.ok) {
    throw new Error(`Google Calendar API error: ${response.status} ${response.statusText}`);
  }

  return response.json() as Promise<T>;
}

/**
 * Build time window for Google Calendar API
 */
function buildTimeParams(window: FetchWindow): { timeMin: string; timeMax: string } {
  if (window.timeMin && window.timeMax) {
    return {
      timeMin: window.timeMin,
      timeMax: window.timeMax,
    };
  }

  const now = new Date();
  const daysBack = window.daysBack ?? 30;
  const timeMin = new Date(now.getTime() - daysBack * 24 * 60 * 60 * 1000);

  return {
    timeMin: timeMin.toISOString(),
    timeMax: now.toISOString(),
  };
}

/**
 * Get event timestamp (start time)
 * Handles both all-day events (date) and timed events (dateTime)
 */
function getEventTimestamp(event: GoogleCalendarEvent): string {
  const start = event.start;

  // Timed event
  if (start.dateTime) {
    // Ensure UTC format
    return start.dateTime.endsWith('Z')
      ? start.dateTime
      : new Date(start.dateTime).toISOString();
  }

  // All-day event - use noon UTC on that day
  if (start.date) {
    return `${start.date}T12:00:00Z`;
  }

  // Fallback to created time
  return event.created ?? new Date().toISOString();
}

/**
 * Extract participant emails from attendees
 */
function getParticipants(event: GoogleCalendarEvent): string[] | undefined {
  const participants: string[] = [];

  // Add organizer
  if (event.organizer?.email && !event.organizer.self) {
    participants.push(event.organizer.email);
  }

  // Add attendees
  if (event.attendees) {
    for (const attendee of event.attendees) {
      // Skip self and declined attendees
      if (!attendee.self && attendee.responseStatus !== 'declined') {
        participants.push(attendee.email);
      }
    }
  }

  return participants.length > 0 ? participants : undefined;
}

/**
 * Normalize Google Calendar Event to UnifiedActivity
 */
function normalizeEvent(
  event: GoogleCalendarEvent,
  accountId: string,
  calendarId: string
): UnifiedActivity | null {
  // Skip cancelled events
  if (event.status === 'cancelled') {
    return null;
  }

  // Skip events without a summary (untitled events)
  if (!event.summary) {
    return null;
  }

  const timestamp = getEventTimestamp(event);
  const participants = getParticipants(event);

  return {
    id: `google-calendar:${accountId}:${calendarId}:${event.id}`,
    provider: 'google-calendar',
    accountId,
    sourceId: event.id,
    type: 'meeting',
    timestamp,
    title: event.summary,
    summary: event.description?.slice(0, 200) || undefined,
    url: event.htmlLink,
    participants,
  };
}

/**
 * Fetch events from a single calendar
 */
async function fetchCalendarEvents(
  accessToken: string,
  calendarId: string,
  timeMin: string,
  timeMax: string
): Promise<GoogleCalendarEvent[]> {
  const events: GoogleCalendarEvent[] = [];
  let pageToken: string | undefined;

  do {
    const params: Record<string, string> = {
      timeMin,
      timeMax,
      singleEvents: 'true', // Expand recurring events
      orderBy: 'startTime',
      maxResults: '250',
      // Minimal fields only
      fields: 'items(id,summary,description,start,end,attendees,organizer,htmlLink,status,created,updated),nextPageToken',
    };

    if (pageToken) {
      params.pageToken = pageToken;
    }

    const response = await fetchCalendarAPI<GoogleCalendarEventsResponse>(
      accessToken,
      `/calendars/${encodeURIComponent(calendarId)}/events`,
      params
    );

    events.push(...response.items);
    pageToken = response.nextPageToken;

    // Safety limit
    if (events.length > 1000) {
      console.warn('Google Calendar: Reached event limit, stopping pagination');
      break;
    }
  } while (pageToken);

  return events;
}

/**
 * Fetch activities for a single Google Calendar account
 */
export async function fetchGoogleCalendarActivities(
  options: GoogleCalendarFetchOptions
): Promise<UnifiedActivity[]> {
  const { account, window } = options;
  const { timeMin, timeMax } = buildTimeParams(window);
  const activities: UnifiedActivity[] = [];

  // Get access token
  const accessToken = await getAccessToken(account.credentials);

  // Fetch events from each calendar
  for (const calendarId of account.calendarIds) {
    try {
      const events = await fetchCalendarEvents(accessToken, calendarId, timeMin, timeMax);

      for (const event of events) {
        const activity = normalizeEvent(event, account.id, calendarId);
        if (activity) {
          activities.push(activity);
        }
      }
    } catch (error) {
      console.error(`Google Calendar: Failed to fetch events from calendar ${calendarId}:`, error);
    }
  }

  // Sort by timestamp descending
  activities.sort((a, b) => b.timestamp.localeCompare(a.timestamp));

  return activities;
}

/**
 * Fetch activities for multiple Google Calendar accounts
 */
export async function fetchGoogleCalendarActivitiesForAccounts(
  accounts: GoogleCalendarAccountConfig[],
  window: FetchWindow
): Promise<Map<string, UnifiedActivity[]>> {
  const results = new Map<string, UnifiedActivity[]>();

  for (const account of accounts) {
    try {
      const activities = await fetchGoogleCalendarActivities({ account, window });
      results.set(account.id, activities);
    } catch (error) {
      console.error(`Google Calendar: Failed to fetch activities for account ${account.id}:`, error);
      results.set(account.id, []);
    }
  }

  return results;
}
