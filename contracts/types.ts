/** Platform-neutral extension contract, v1. Types only; no service is connected. */
export type Id = string;
export type LocalDate = string; // YYYY-MM-DD
export type LocalTime = string; // HH:mm, 24h
export type Instant = string; // ISO 8601 UTC
export type TimeZone = string; // IANA name, e.g. Asia/Shanghai
export type Platform = 'android' | 'windows' | 'macos';
export interface EntityMeta {
  id: Id;
  schemaVersion: 1;
  revision: string; // Opaque server-issued revision; not a client timestamp.
  createdAt: Instant;
  updatedAt: Instant;
  updatedByDeviceId: Id;
  deletedAt?: Instant; // Tombstone, replicated until all active devices acknowledge it.
}
export type Recurrence =
 | { kind: 'none' }
 | { kind: 'daily'; intervalDays: number; anchorDate: LocalDate }
 | { kind: 'weekly'; weekdays: number[]; anchorDate: LocalDate }; // Mon=1 ... Sun=7
export interface TaskTemplate extends EntityMeta {
  title: string;
  notes: string;
  mode: 'persistent' | 'recurring';
  startDate: LocalDate;
  estimatedCalendarDays?: number;
  recurrence: Recurrence;
  timeZone: TimeZone;
  initialDueDate?: LocalDate;
}
/** Completion and overdue state belong to an occurrence, never to the whole recurring template. */
export interface TaskOccurrence extends EntityMeta {
  templateId: Id;
  occurrenceKey: string; // deterministic templateId + recurrence date, shared by every device
  localDate: LocalDate;
  dueDate?: LocalDate;
  originalDueDate?: LocalDate;
  completedAt?: Instant;
  deadlineRevisionCount: number;
  deadlineHistoryIds: Id[];
}
export interface DeadlineChange extends EntityMeta {
  occurrenceId: Id;
  previousDueDate?: LocalDate;
  newDueDate: LocalDate;
  overdueDaysAtChange: number;
  ordinal: number;
  reason?: string;
}
export interface TimeBlock extends EntityMeta {
  occurrenceId: Id;
  startLocal: { date: LocalDate; time: LocalTime };
  endLocal: { date: LocalDate; time: LocalTime };
  timeZone: TimeZone;
  timeZonePolicy: 'follow_device_local_time' | 'fixed_zone';
}
export interface RingProfile {
  toneId: Id; // Symbolic ID; each platform resolves to a local sound asset.
  customToneAssetId?: Id;
  vibrate: boolean;
  volume: number; // 0..1, subject to platform permissions/capabilities
  durationSeconds: number;
  snooze: { intervalMinutes: number; maxCount: number; autoRepeatIfUnanswered: boolean };
}
export interface EventReminder extends EntityMeta {
  timeBlockId: Id;
  anchor: 'start' | 'end';
  offsetMinutes: number; // Negative = before. Zero = at. Positive = after.
  enabled: boolean;
  ringProfileId: Id;
  targetingPolicyId: Id;
}
export type AlarmRule =
 | { kind: 'once'; date: LocalDate; time: LocalTime }
 | { kind: 'weekly'; weekdays: number[]; time: LocalTime }
 | { kind: 'every_n_days'; anchorDate: LocalDate; intervalDays: number; time: LocalTime }
 | { kind: 'within_window'; weekdays: number[]; start: LocalTime; end: LocalTime; endDayOffset: 0 | 1; intervalMinutes: number }
 | { kind: 'shift'; shiftPlanId: Id };
export interface Alarm extends EntityMeta {
  title: string;
  enabled: boolean;
  rule: AlarmRule;
  timeZone: TimeZone;
  timeZonePolicy: 'follow_device_local_time' | 'fixed_zone';
  ringProfileId: Id;
  targetingPolicyId: Id;
}
export interface ShiftDay {
  label: string;
  alarms: { time: LocalTime; ringProfileId: Id }[]; // Empty array = rest day.
}
export interface ShiftPlan extends EntityMeta {
  title: string;
  anchorDate: LocalDate; // day 1
  timeZone: TimeZone;
  days: ShiftDay[];
  exceptions: Record<LocalDate, ShiftDay>; // Overrides the date, does not shift cycle phase.
}
export interface Device extends EntityMeta {
  platform: Platform;
  displayName: string;
  capabilities: { exactAlarms: boolean; backgroundExecution: boolean; notifications: boolean; customSound: boolean };
  lastSeenAt?: Instant;
}
export interface TargetingPolicy extends EntityMeta {
  perDevice: Record<Id, 'ring' | 'notify' | 'silent'>;
  primaryRingDeviceId?: Id;
  offlineFallback: 'primary_only' | 'all_selected_devices';
}
export interface ThemeTokens {
  background: string;
  surface: string;
  text: string;
  textSecondary: string;
  accent: string;
  onAccent: string;
  divider: string;
  overdueLevels: readonly [string,string,string,string,string,string,string];
  revisionPalette: string[];
  fontFamily: string;
  radius: { small: number; medium: number; large: number };
  spacing: { small: number; medium: number; large: number };
}
export interface ThemeDefinition {
  id: Id;
  version: number;
  name: string;
  modes: { light: ThemeTokens; dark: ThemeTokens };
  material?: {
    kind: 'solid' | 'glass';
    panelOpacity: number;
    navigationOpacity: number;
    blurRadius: number;
    saturation: number;
    respectReducedTransparency: boolean;
  };
}
export interface ThemeProvider {
  list(): Promise<ThemeDefinition[]>;
  load(id: Id): Promise<ThemeDefinition>;
  setPreference(preference: { themeId: Id; mode: 'light' | 'dark' | 'system'; scope: 'device' | 'account' }): Promise<void>;
}
export type SyncedEntity = TaskTemplate | TaskOccurrence | DeadlineChange | TimeBlock | EventReminder | Alarm | ShiftPlan | Device | TargetingPolicy;
export interface ChangeMutation {
  mutationId: Id; // Retry-safe, stable ID; unique on originating device.
  entityType: string;
  entityId: Id;
  baseRevision: string | null;
  operation: 'upsert' | 'delete';
  payload?: SyncedEntity;
  originatingDeviceId: Id;
}
export interface SyncConflict {
  entityType: string;
  entityId: Id;
  baseRevision: string | null;
  local: ChangeMutation;
  remote: SyncedEntity;
  kind: 'concurrent_edit' | 'edit_vs_delete' | 'completion_vs_edit';
}
export interface SyncTransport {
  pull(request: { cursor?: string; limit: number; deviceId: Id }): Promise<{ changes: SyncedEntity[]; nextCursor: string; hasMore: boolean }>;
  push(request: { mutations: ChangeMutation[]; deviceId: Id }): Promise<{ accepted: { mutationId: Id; revision: string }[]; conflicts: SyncConflict[] }>;
  resolveConflict(request: { conflict: SyncConflict; choice: 'local' | 'remote' | 'merge'; merged?: SyncedEntity; expectedRemoteRevision: string }): Promise<SyncedEntity>;
}
export interface IdentityProvider {
  signIn(): Promise<{ accountId: Id; sessionExpiresAt: Instant }>;
  signOut(): Promise<void>;
  pairDevice(request: { pairingCode: string; device: Device }): Promise<{ accountId: Id; deviceId: Id }>;
}
export interface LocalStore {
  /** Transactionally apply entity mutation and append it to the sync outbox. */
  transact(mutations: ChangeMutation[]): Promise<void>;
  read(entityType: string, entityId: Id): Promise<SyncedEntity | null>;
  pendingMutations(limit: number): Promise<ChangeMutation[]>;
  acknowledge(mutationIds: Id[]): Promise<void>;
}
export interface ScheduledOccurrence {
  occurrenceKey: string;
  deviceId: Id;
  fireAt: Instant;
  mode: 'ring' | 'notify';
  ringProfileId: Id;
  sourceEntityId: Id;
  sourceRevision: string;
}
export interface ReminderScheduler {
  capabilities(): Promise<Device['capabilities']>;
  reconcile(desired: ScheduledOccurrence[]): Promise<{ scheduled: string[]; blocked: { occurrenceKey: string; reason: string }[] }>;
  cancel(occurrenceKeys: string[]): Promise<void>;
  stopCurrent(occurrenceKey: string): Promise<void>;
  snooze(occurrenceKey: string, minutes: number): Promise<void>;
  skipNext(sourceEntityId: Id): Promise<void>;
}
