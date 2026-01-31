/**
 * Google Calendar provider configuration and API types
 */

import type { FetchWindow } from '../../schemas/index.js';

/**
 * Google OAuth credentials
 */
export interface GoogleOAuthCredentials {
  clientId: string;
  clientSecret: string;
  refreshToken: string;
}

/**
 * Google Calendar account configuration
 */
export interface GoogleCalendarAccountConfig {
  /** Unique identifier for this account */
  id: string;
  /** OAuth credentials for this account */
  credentials: GoogleOAuthCredentials;
  /** Calendar IDs to fetch events from (e.g., 'primary', 'secondary@group.calendar.google.com') */
  calendarIds: string[];
  /** Optional description for this account */
  description?: string;
}

/**
 * Google Calendar provider configuration
 */
export interface GoogleCalendarProviderConfig {
  accounts: GoogleCalendarAccountConfig[];
}

/**
 * Options for fetching Google Calendar activities
 */
export interface GoogleCalendarFetchOptions {
  /** Account configuration to use */
  account: GoogleCalendarAccountConfig;
  /** Time window for fetching activities */
  window: FetchWindow;
}

/**
 * Google Calendar Event Attendee (minimal fields)
 * https://developers.google.com/calendar/api/v3/reference/events
 */
export interface GoogleCalendarAttendee {
  email: string;
  displayName?: string;
  responseStatus?: 'needsAction' | 'declined' | 'tentative' | 'accepted';
  self?: boolean;
  organizer?: boolean;
}

/**
 * Google Calendar Event DateTime
 */
export interface GoogleCalendarDateTime {
  /** For all-day events */
  date?: string;
  /** For timed events (RFC3339 timestamp) */
  dateTime?: string;
  /** Time zone (optional, used with dateTime) */
  timeZone?: string;
}

/**
 * Google Calendar Event (minimal fields needed for UnifiedActivity)
 */
export interface GoogleCalendarEvent {
  id: string;
  summary?: string;
  description?: string;
  start: GoogleCalendarDateTime;
  end: GoogleCalendarDateTime;
  attendees?: GoogleCalendarAttendee[];
  organizer?: {
    email: string;
    displayName?: string;
    self?: boolean;
  };
  htmlLink?: string;
  status?: 'confirmed' | 'tentative' | 'cancelled';
  created?: string;
  updated?: string;
}

/**
 * Google Calendar Events List Response
 */
export interface GoogleCalendarEventsResponse {
  kind: 'calendar#events';
  summary: string;
  items: GoogleCalendarEvent[];
  nextPageToken?: string;
}

/**
 * Google OAuth Token Response
 */
export interface GoogleTokenResponse {
  access_token: string;
  expires_in: number;
  token_type: string;
  scope: string;
}
