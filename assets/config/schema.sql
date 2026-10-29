-- DD-1.0 / schema_version=1
-- Design contract only. This file does not create a running application.
-- JSON is validated by the application. Do not assume Android SQLite JSON1.
PRAGMA foreign_keys = ON;
PRAGMA user_version = 1;

CREATE TABLE profiles (
  profile_id TEXT PRIMARY KEY,
  singleton INTEGER NOT NULL DEFAULT 1 UNIQUE CHECK (singleton = 1),
  created_utc_ms INTEGER NOT NULL,
  locale TEXT NOT NULL CHECK (locale IN ('zh-Hans', 'en')),
  mode TEXT NOT NULL CHECK (mode IN ('ASSIST', 'CHALLENGE')),
  onboarding_completed INTEGER NOT NULL DEFAULT 0 CHECK (onboarding_completed IN (0, 1)),
  settings_json TEXT NOT NULL,
  settings_version INTEGER NOT NULL DEFAULT 1 CHECK (settings_version >= 1)
);

CREATE TABLE profile_task_state (
  profile_id TEXT NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
  task_id TEXT NOT NULL,
  mode TEXT NOT NULL CHECK (mode IN ('ASSIST', 'CHALLENGE')),
  parameter_profile_version TEXT NOT NULL,
  level INTEGER NOT NULL CHECK (level >= 1),
  updated_utc_ms INTEGER NOT NULL,
  PRIMARY KEY (profile_id, task_id, mode, parameter_profile_version)
);

CREATE TABLE sessions (
  session_id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
  task_id TEXT NOT NULL,
  task_version TEXT NOT NULL,
  content_id TEXT,
  content_version TEXT,
  parameter_profile_version TEXT NOT NULL,
  adaptive_version TEXT NOT NULL,
  metric_version TEXT NOT NULL,
  session_locale TEXT NOT NULL CHECK (session_locale IN ('zh-Hans', 'en')),
  mode TEXT NOT NULL CHECK (mode IN ('ASSIST', 'CHALLENGE')),
  input_source TEXT NOT NULL CHECK (input_source = 'TOUCH'),
  review_status TEXT NOT NULL,
  clock_epoch_id TEXT NOT NULL,
  clock_source TEXT NOT NULL CHECK (clock_source = 'DART_RECEIPT'),
  rng_algorithm TEXT NOT NULL,
  rng_seed INTEGER NOT NULL CHECK (rng_seed BETWEEN 1 AND 4294967295),
  started_utc_ms INTEGER NOT NULL,
  ended_utc_ms INTEGER,
  session_timezone TEXT NOT NULL,
  session_utc_offset_minutes INTEGER NOT NULL,
  status TEXT NOT NULL CHECK (status IN (
    'PREPARING', 'DEMONSTRATING', 'WAIT_ALL_UP', 'COUNTDOWN', 'ACTIVE',
    'BLOCK_FEEDBACK', 'PAUSED', 'PAUSED_ERROR', 'FINISHING',
    'COMPLETED', 'EXITED', 'RECOVERED_INTERRUPTED'
  )),
  required_block_slots INTEGER NOT NULL DEFAULT 2 CHECK (required_block_slots >= 1),
  planned_target_count_initial INTEGER NOT NULL CHECK (planned_target_count_initial >= 1),
  planned_target_count INTEGER NOT NULL CHECK (planned_target_count >= 1),
  auto_upgrade_allowed INTEGER NOT NULL DEFAULT 1 CHECK (auto_upgrade_allowed IN (0, 1)),
  snapshot_json TEXT NOT NULL,
  snapshot_sha256 TEXT NOT NULL CHECK (length(snapshot_sha256) = 64),
  environment_json TEXT NOT NULL,
  active_duration_us INTEGER NOT NULL DEFAULT 0 CHECK (active_duration_us >= 0),
  interrupted_active_us INTEGER NOT NULL DEFAULT 0 CHECK (interrupted_active_us >= 0),
  elapsed_duration_us INTEGER NOT NULL DEFAULT 0 CHECK (elapsed_duration_us >= 0),
  terminal_reason TEXT,
  CHECK ((content_id IS NULL) = (content_version IS NULL)),
  CHECK (status NOT IN ('COMPLETED', 'EXITED', 'RECOVERED_INTERRUPTED') OR ended_utc_ms IS NOT NULL)
);
CREATE INDEX ix_sessions_profile_started ON sessions(profile_id, started_utc_ms DESC, session_id ASC);
CREATE UNIQUE INDEX ux_single_open_session ON sessions(profile_id)
  WHERE status NOT IN ('COMPLETED', 'EXITED', 'RECOVERED_INTERRUPTED');

CREATE TABLE blocks (
  block_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
  ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
  slot_index INTEGER NOT NULL CHECK (slot_index >= 0),
  commit_id TEXT UNIQUE,
  level INTEGER NOT NULL CHECK (level >= 1),
  status TEXT NOT NULL CHECK (status IN (
    'PLANNED', 'ACTIVE', 'COMPLETED', 'PARTIAL_MANUAL', 'INTERRUPTED', 'INVALID'
  )),
  planned_trial_count INTEGER NOT NULL CHECK (planned_trial_count >= 1),
  valid_trial_count INTEGER NOT NULL DEFAULT 0 CHECK (valid_trial_count >= 0),
  started_offset_us INTEGER,
  ended_offset_us INTEGER,
  ended_utc_ms INTEGER,
  parameters_json TEXT NOT NULL,
  targets_json TEXT NOT NULL,
  comparison_key TEXT,
  active_duration_us INTEGER NOT NULL DEFAULT 0 CHECK (active_duration_us >= 0),
  UNIQUE (block_id, session_id),
  UNIQUE (session_id, ordinal),
  CHECK (valid_trial_count <= planned_trial_count),
  CHECK (status != 'COMPLETED' OR valid_trial_count = planned_trial_count),
  CHECK (status != 'COMPLETED' OR (commit_id IS NOT NULL AND ended_utc_ms IS NOT NULL)),
  CHECK (ended_offset_us IS NULL OR started_offset_us IS NULL OR ended_offset_us >= started_offset_us)
);
CREATE UNIQUE INDEX ux_completed_block_slot ON blocks(session_id, slot_index)
  WHERE status = 'COMPLETED';

CREATE TABLE trials (
  trial_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  block_id TEXT NOT NULL,
  logical_index INTEGER NOT NULL CHECK (logical_index >= 0),
  status TEXT NOT NULL CHECK (status IN (
    'PLANNED', 'ACTIVE', 'COMPLETED', 'CANCELLED_MANUAL', 'CANCELLED_RECONFIGURE', 'INTERRUPTED'
  )),
  target_json TEXT NOT NULL,
  rule_id TEXT,
  switch_flag INTEGER CHECK (switch_flag IS NULL OR switch_flag IN (0, 1)),
  assisted INTEGER NOT NULL DEFAULT 0 CHECK (assisted IN (0, 1)),
  help_count INTEGER NOT NULL DEFAULT 0 CHECK (help_count >= 0),
  policy_hint_count INTEGER NOT NULL DEFAULT 0 CHECK (policy_hint_count >= 0),
  interrupted_retry_count INTEGER NOT NULL DEFAULT 0 CHECK (interrupted_retry_count >= 0),
  UNIQUE (trial_id, block_id, session_id),
  UNIQUE (block_id, logical_index),
  FOREIGN KEY (block_id, session_id) REFERENCES blocks(block_id, session_id) ON DELETE CASCADE
);

CREATE TABLE attempts (
  attempt_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  block_id TEXT NOT NULL,
  trial_id TEXT NOT NULL,
  ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
  validity TEXT NOT NULL CHECK (validity IN ('OPEN', 'VALID', 'INTERRUPTED', 'INVALID')),
  started_offset_us INTEGER NOT NULL CHECK (started_offset_us >= 0),
  ended_offset_us INTEGER,
  cue_anchor_us INTEGER,
  cue_confidence TEXT,
  response_end_us INTEGER,
  active_duration_us INTEGER NOT NULL DEFAULT 0 CHECK (active_duration_us >= 0),
  outcome TEXT,
  reason_code TEXT,
  result_version TEXT NOT NULL,
  result_json TEXT,
  UNIQUE (attempt_id, trial_id, block_id, session_id),
  UNIQUE (trial_id, ordinal),
  FOREIGN KEY (trial_id, block_id, session_id)
    REFERENCES trials(trial_id, block_id, session_id) ON DELETE CASCADE,
  CHECK (ended_offset_us IS NULL OR ended_offset_us >= started_offset_us),
  CHECK (validity != 'VALID' OR (ended_offset_us IS NOT NULL AND outcome IS NOT NULL AND result_json IS NOT NULL))
);
CREATE UNIQUE INDEX ux_one_valid_attempt ON attempts(trial_id) WHERE validity = 'VALID';
CREATE UNIQUE INDEX ux_one_open_attempt ON attempts(session_id) WHERE validity = 'OPEN';

CREATE TABLE events (
  session_id TEXT NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
  seq INTEGER NOT NULL CHECK (seq >= 1),
  offset_us INTEGER CHECK (offset_us IS NULL OR offset_us >= 0),
  clock_epoch_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  block_id TEXT,
  trial_id TEXT,
  attempt_id TEXT,
  source_event_seq INTEGER,
  payload_version INTEGER NOT NULL DEFAULT 1 CHECK (payload_version >= 1),
  payload_json TEXT NOT NULL,
  PRIMARY KEY (session_id, seq),
  FOREIGN KEY (block_id, session_id) REFERENCES blocks(block_id, session_id) ON DELETE CASCADE,
  FOREIGN KEY (trial_id, block_id, session_id)
    REFERENCES trials(trial_id, block_id, session_id) ON DELETE CASCADE,
  FOREIGN KEY (attempt_id, trial_id, block_id, session_id)
    REFERENCES attempts(attempt_id, trial_id, block_id, session_id) ON DELETE CASCADE,
  FOREIGN KEY (session_id, source_event_seq) REFERENCES events(session_id, seq),
  CHECK (trial_id IS NULL OR block_id IS NOT NULL),
  CHECK (attempt_id IS NULL OR (trial_id IS NOT NULL AND block_id IS NOT NULL)),
  CHECK (source_event_seq IS NULL OR source_event_seq < seq)
);
CREATE INDEX ix_events_attempt ON events(attempt_id, seq);

CREATE TABLE adaptive_decisions (
  decision_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
  block_id TEXT,
  decision_key TEXT NOT NULL,
  adaptive_version TEXT NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('AUTO', 'USER')),
  action TEXT NOT NULL CHECK (action IN ('UP', 'DOWN', 'HOLD', 'ASSIST')),
  reason_code TEXT NOT NULL,
  level_before INTEGER NOT NULL CHECK (level_before >= 1),
  level_after INTEGER NOT NULL CHECK (level_after >= 1),
  parameters_before_json TEXT NOT NULL,
  parameters_after_json TEXT NOT NULL,
  evidence_json TEXT NOT NULL,
  decided_offset_us INTEGER NOT NULL CHECK (decided_offset_us >= 0),
  UNIQUE (session_id, decision_key),
  FOREIGN KEY (block_id, session_id) REFERENCES blocks(block_id, session_id) ON DELETE CASCADE
);

CREATE TABLE summaries (
  summary_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
  block_id TEXT,
  scope TEXT NOT NULL CHECK (scope IN ('SESSION', 'BLOCK')),
  scope_key TEXT NOT NULL,
  metric_version TEXT NOT NULL,
  comparison_key TEXT,
  calculated_utc_ms INTEGER NOT NULL,
  result_json TEXT NOT NULL,
  source_last_seq INTEGER NOT NULL CHECK (source_last_seq >= 1),
  UNIQUE (session_id, scope_key, metric_version),
  FOREIGN KEY (block_id, session_id) REFERENCES blocks(block_id, session_id) ON DELETE CASCADE,
  CHECK ((scope = 'SESSION' AND block_id IS NULL AND scope_key = 'SESSION') OR
         (scope = 'BLOCK' AND block_id IS NOT NULL AND scope_key = block_id))
);
CREATE INDEX ix_summaries_comparison ON summaries(comparison_key, calculated_utc_ms);

CREATE TABLE tutorial_progress (
  profile_id TEXT NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
  lesson_id TEXT NOT NULL,
  lesson_version TEXT NOT NULL,
  completed INTEGER NOT NULL CHECK (completed IN (0, 1)),
  updated_utc_ms INTEGER NOT NULL,
  PRIMARY KEY (profile_id, lesson_id, lesson_version)
);

CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY CHECK (version >= 1),
  applied_utc_ms INTEGER NOT NULL,
  migration_checksum TEXT NOT NULL CHECK (length(migration_checksum) = 64)
);

-- Application invariants not expressible with these CHECK constraints:
-- 1. profiles has exactly one row after initialization.
-- 2. task/mode/config level never exceeds its configuration maximum.
-- 3. completed trial has exactly one VALID attempt.
-- 4. slot_index < sessions.required_block_slots.
-- 5. completed session has one COMPLETED block in each required slot.
-- 6. config/environment/target/result JSON and hashes pass versioned decoders.
-- 7. all non-recovery events have offset_us and the session clock_epoch_id.
-- 8. recovery events use the new clock_epoch_id with offset_us=NULL.
-- 9. sums and planned counts are checked in the same finalization transaction.
-- 10. session terminal status is immutable except versioned summary recalculation.
