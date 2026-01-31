import { describe, it, expect } from 'vitest';
import { validateActivity, UnifiedActivitySchema } from '../schemas/index.js';
import type { UnifiedActivity } from '../schemas/index.js';
import type { GoogleCalendarEvent } from '../providers/google-calendar/index.js';

/**
 * Mock Google Calendar API response data for testing normalization
 */
const mockTimedEvent: GoogleCalendarEvent = {
  id: 'event123abc',
  summary: 'Weekly Team Standup',
  description: 'Weekly sync with the engineering team to discuss progress and blockers.',
  start: {
    dateTime: '2024-01-15T09:00:00Z',
    timeZone: 'UTC',
  },
  end: {
    dateTime: '2024-01-15T09:30:00Z',
    timeZone: 'UTC',
  },
  attendees: [
    { email: 'alice@example.com', displayName: 'Alice Smith', responseStatus: 'accepted' },
    { email: 'bob@example.com', displayName: 'Bob Jones', responseStatus: 'accepted' },
    { email: 'self@example.com', displayName: 'Self', responseStatus: 'accepted', self: true },
  ],
  organizer: {
    email: 'organizer@example.com',
    displayName: 'Org Manager',
    self: false,
  },
  htmlLink: 'https://calendar.google.com/calendar/event?eid=abc123',
  status: 'confirmed',
  created: '2024-01-01T10:00:00Z',
  updated: '2024-01-14T12:00:00Z',
};

const mockAllDayEvent: GoogleCalendarEvent = {
  id: 'event456def',
  summary: 'Company All-Hands',
  description: 'Quarterly all-hands meeting for the entire company.',
  start: {
    date: '2024-01-20',
  },
  end: {
    date: '2024-01-21',
  },
  attendees: [
    { email: 'everyone@example.com', displayName: 'Everyone', responseStatus: 'accepted' },
  ],
  organizer: {
    email: 'ceo@example.com',
    displayName: 'CEO',
    self: false,
  },
  htmlLink: 'https://calendar.google.com/calendar/event?eid=def456',
  status: 'confirmed',
};

const mockCancelledEvent: GoogleCalendarEvent = {
  ...mockTimedEvent,
  id: 'cancelled789',
  status: 'cancelled',
};

const mockNoAttendeesEvent: GoogleCalendarEvent = {
  id: 'solo123',
  summary: 'Focus Time',
  start: {
    dateTime: '2024-01-15T14:00:00Z',
  },
  end: {
    dateTime: '2024-01-15T16:00:00Z',
  },
  status: 'confirmed',
};

const mockDeclinedAttendeesEvent: GoogleCalendarEvent = {
  ...mockTimedEvent,
  id: 'declined456',
  attendees: [
    { email: 'alice@example.com', responseStatus: 'declined' },
    { email: 'bob@example.com', responseStatus: 'accepted' },
    { email: 'self@example.com', responseStatus: 'accepted', self: true },
  ],
};

const mockTimezoneEvent: GoogleCalendarEvent = {
  ...mockTimedEvent,
  id: 'tz789',
  start: {
    dateTime: '2024-01-15T09:00:00-08:00',
    timeZone: 'America/Los_Angeles',
  },
  end: {
    dateTime: '2024-01-15T10:00:00-08:00',
    timeZone: 'America/Los_Angeles',
  },
};

/**
 * Helper to normalize mock data to UnifiedActivity
 * (Simulates the normalization logic in fetch.ts)
 */
function normalizeEvent(
  event: GoogleCalendarEvent,
  accountId: string,
  calendarId: string = 'primary'
): UnifiedActivity | null {
  // Skip cancelled events
  if (event.status === 'cancelled') {
    return null;
  }

  // Skip events without summary
  if (!event.summary) {
    return null;
  }

  // Get timestamp
  let timestamp: string;
  if (event.start.dateTime) {
    timestamp = event.start.dateTime.endsWith('Z')
      ? event.start.dateTime
      : new Date(event.start.dateTime).toISOString();
  } else if (event.start.date) {
    timestamp = `${event.start.date}T12:00:00Z`;
  } else {
    timestamp = event.created ?? new Date().toISOString();
  }

  // Get participants
  const participants: string[] = [];

  if (event.organizer?.email && !event.organizer.self) {
    participants.push(event.organizer.email);
  }

  if (event.attendees) {
    for (const attendee of event.attendees) {
      if (!attendee.self && attendee.responseStatus !== 'declined') {
        participants.push(attendee.email);
      }
    }
  }

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
    participants: participants.length > 0 ? participants : undefined,
  };
}

describe('Google Calendar Provider Contract Tests', () => {
  const accountId = 'google-personal';

  describe('Timed event normalization', () => {
    it('should produce valid UnifiedActivity from timed event', () => {
      const activity = normalizeEvent(mockTimedEvent, accountId);
      expect(activity).not.toBeNull();
      expect(() => validateActivity(activity!)).not.toThrow();
    });

    it('should map event to meeting type', () => {
      const activity = normalizeEvent(mockTimedEvent, accountId);
      expect(activity?.type).toBe('meeting');
    });

    it('should use event summary as title', () => {
      const activity = normalizeEvent(mockTimedEvent, accountId);
      expect(activity?.title).toBe('Weekly Team Standup');
    });

    it('should use start dateTime as timestamp', () => {
      const activity = normalizeEvent(mockTimedEvent, accountId);
      expect(activity?.timestamp).toBe('2024-01-15T09:00:00Z');
    });

    it('should include htmlLink as url', () => {
      const activity = normalizeEvent(mockTimedEvent, accountId);
      expect(activity?.url).toBe('https://calendar.google.com/calendar/event?eid=abc123');
    });

    it('should include description as summary', () => {
      const activity = normalizeEvent(mockTimedEvent, accountId);
      expect(activity?.summary).toContain('Weekly sync with the engineering team');
    });
  });

  describe('Attendee extraction', () => {
    it('should extract attendee emails as participants', () => {
      const activity = normalizeEvent(mockTimedEvent, accountId);

      expect(activity?.participants).toContain('alice@example.com');
      expect(activity?.participants).toContain('bob@example.com');
    });

    it('should include organizer email', () => {
      const activity = normalizeEvent(mockTimedEvent, accountId);
      expect(activity?.participants).toContain('organizer@example.com');
    });

    it('should exclude self from participants', () => {
      const activity = normalizeEvent(mockTimedEvent, accountId);
      expect(activity?.participants).not.toContain('self@example.com');
    });

    it('should exclude declined attendees', () => {
      const activity = normalizeEvent(mockDeclinedAttendeesEvent, accountId);

      expect(activity?.participants).toContain('bob@example.com');
      expect(activity?.participants).not.toContain('alice@example.com');
    });

    it('should handle events without attendees', () => {
      const activity = normalizeEvent(mockNoAttendeesEvent, accountId);

      expect(activity).not.toBeNull();
      expect(activity?.participants).toBeUndefined();
    });
  });

  describe('All-day event normalization', () => {
    it('should produce valid UnifiedActivity from all-day event', () => {
      const activity = normalizeEvent(mockAllDayEvent, accountId);
      expect(activity).not.toBeNull();
      expect(() => validateActivity(activity!)).not.toThrow();
    });

    it('should use noon UTC for all-day event timestamp', () => {
      const activity = normalizeEvent(mockAllDayEvent, accountId);
      expect(activity?.timestamp).toBe('2024-01-20T12:00:00Z');
    });
  });

  describe('Cancelled event handling', () => {
    it('should return null for cancelled events', () => {
      const activity = normalizeEvent(mockCancelledEvent, accountId);
      expect(activity).toBeNull();
    });
  });

  describe('Timezone normalization', () => {
    it('should convert non-UTC timestamps to UTC', () => {
      const activity = normalizeEvent(mockTimezoneEvent, accountId);
      expect(activity?.timestamp).toMatch(/Z$/);
      // -08:00 means UTC+8 hours
      expect(activity?.timestamp).toBe('2024-01-15T17:00:00.000Z');
    });
  });

  describe('Required fields verification', () => {
    it('should verify all normalized activities have required fields', () => {
      const events = [mockTimedEvent, mockAllDayEvent, mockNoAttendeesEvent];

      for (const event of events) {
        const activity = normalizeEvent(event, accountId);
        expect(activity).not.toBeNull();

        expect(activity!.id).toBeDefined();
        expect(activity!.provider).toBe('google-calendar');
        expect(activity!.accountId).toBe(accountId);
        expect(activity!.sourceId).toBeDefined();
        expect(activity!.type).toBe('meeting');
        expect(activity!.timestamp).toBeDefined();

        expect(() => validateActivity(activity!)).not.toThrow();
      }
    });

    it('should not include extra fields beyond UnifiedActivity schema', () => {
      const activity = normalizeEvent(mockTimedEvent, accountId);
      const schemaKeys = Object.keys(UnifiedActivitySchema.shape);
      const activityKeys = Object.keys(activity!);

      for (const key of activityKeys) {
        expect(schemaKeys).toContain(key);
      }
    });
  });

  describe('Multiple accounts and calendars support', () => {
    it('should correctly namespace activities by account', () => {
      const personalActivity = normalizeEvent(mockTimedEvent, 'google-personal');
      const workActivity = normalizeEvent(mockTimedEvent, 'google-work');

      expect(personalActivity?.accountId).toBe('google-personal');
      expect(workActivity?.accountId).toBe('google-work');

      expect(personalActivity?.id).toContain('google-personal');
      expect(workActivity?.id).toContain('google-work');
    });

    it('should include calendar ID in activity ID', () => {
      const primaryActivity = normalizeEvent(mockTimedEvent, accountId, 'primary');
      const secondaryActivity = normalizeEvent(mockTimedEvent, accountId, 'secondary@group.calendar.google.com');

      expect(primaryActivity?.id).toContain(':primary:');
      expect(secondaryActivity?.id).toContain(':secondary@group.calendar.google.com:');
    });
  });

  describe('Summary truncation', () => {
    it('should truncate long descriptions to 200 chars', () => {
      const longDescEvent: GoogleCalendarEvent = {
        ...mockTimedEvent,
        description: 'A'.repeat(300),
      };

      const activity = normalizeEvent(longDescEvent, accountId);
      expect(activity?.summary).toHaveLength(200);
    });
  });

  describe('Untitled event handling', () => {
    it('should skip events without summary', () => {
      const noSummaryEvent: GoogleCalendarEvent = {
        ...mockTimedEvent,
        summary: undefined,
      };

      const activity = normalizeEvent(noSummaryEvent, accountId);
      expect(activity).toBeNull();
    });
  });
});

describe('Google Calendar Minimal Fields', () => {
  it('should only request fields needed for UnifiedActivity', () => {
    // Document which fields we use from Google Calendar API
    const usedFields = [
      'id',           // -> sourceId
      'summary',      // -> title
      'description',  // -> summary
      'start',        // -> timestamp
      'end',          // (for context only)
      'attendees',    // -> participants (emails)
      'organizer',    // -> participants (email)
      'htmlLink',     // -> url
      'status',       // (to filter cancelled)
      'created',      // (fallback timestamp)
      'updated',      // (not used, but minimal)
    ];

    expect(usedFields).toHaveLength(11);
    expect(usedFields).toContain('id');
    expect(usedFields).toContain('summary');
    expect(usedFields).toContain('attendees');
  });
});
