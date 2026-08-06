import { createHash } from 'node:crypto';
import { writeFile } from 'node:fs/promises';

export const TRACE_SCHEMA = 'persona_decision_trace_v3';
export const PLAYER_OBSERVATION_SCHEMA = 'player_observation_v1';

const PLAYER_BOUNDARIES = new Set([
  'keyboard_pointer', 'controller', 'touch', 'player_command',
]);
const FORBIDDEN_VERBS = new Set([
  'complete', 'debug', 'fixture', 'set_level', 'set_position', 'set_stat',
  'snap', 'teleport', 'trigger',
]);
const WORLD_CHANGE_VERBS = new Set(['rally', 'interact', 'move', 'push', 'use']);
const OBSERVATION_ONLY_VERBS = new Set([
	'camera_pan', 'camera_recenter', 'camera_rotate', 'camera_zoom',
  'focus', 'pause', 'recenter', 'select_party', 'select_single',
  'toggle_instructions', 'toggle_run', 'wait', 'zoom_out',
]);
const OBSERVATION_KEYS = new Set(['schema', 'source', 'tick', 'capture_serial', 'state']);
const OBSERVATION_STATE_KEYS = new Set([
  'hud', 'viewport', 'affordances', 'visible_affordance_verbs',
  'visible_affordance_consequences', 'cues', 'viewport_bins',
]);
const HUD_PRESENTATION_KEYS = new Set([
  'portraits', 'portrait', 'token', 'bars', 'hp', 'stamina', 'atp',
  'hp_percent', 'stamina_percent', 'atp_percent', 'current', 'maximum',
  'percent', 'status', 'statuses', 'selection', 'selected', 'available',
  'downed', 'conscious', 'visible', 'kind', 'text', 'value', 'label',
  'screen', 'active', 'sta', 'alert', 'hold_label', 'hold_locked',
  'run_label', 'routing_label', 'message', 'hands', 'hold', 'locked',
]);
const AFFORDANCE_PRESENTATION_KEYS = new Set([
  'token', 'kind', 'verb', 'consequence', 'screen',
]);
// Keep this byte-for-byte in semantic parity with PersonaDecisionTrace.gd.
const CUE_PRESENTATION_KEYS = new Set([
  'kind', 'text', 'token', 'source_token', 'target_token', 'subjects',
  'phase', 'state', 'progress', 'accepted', 'reason', 'visible', 'direction',
  'destination', 'screen', 'duration', 'binding', 'result',
  'presentation_serial', 'label', 'destination_label',
  'route_status', 'route_status_serial', 'route_status_subjects',
  'route_status_remaining_seconds',
]);
const MOVEMENT_ROUTE_STATUS_KEYS = [
  'route_status', 'route_status_serial', 'route_status_subjects',
  'route_status_remaining_seconds',
];
const VIEWPORT_PRESENTATION_KEYS = new Set(['origin', 'size']);
const FORBIDDEN_OBSERVATION_KEYS = new Set([
  'name', 'node', 'node_path', 'position', 'world_position',
  'global_position', 'transform', 'level', 'cell', 'grid', 'detection',
  'detection_range', 'fsm', 'private', 'internal', 'solution', 'anchor',
  'complete', 'completion', 'preflight', 'validator', 'event_log',
  'action_receipts', 'content_fingerprint', 'gameplay_build_fingerprint',
  'gameplay_build_fingerprint_schema', 'seed',
]);
const INPUT_RECEIPT_PROOF = Symbol('shipped-input-receipt');
const PLAYER_INPUT_LEDGER_MARK_PROOF = Symbol('player-input-ledger-mark');
const PLAYER_INPUT_LEDGER_SLICE_PROOF = Symbol('player-input-ledger-slice');
const PLAYER_INPUT_SEQUENCE_BEFORE_PROOF = Symbol('player-input-sequence-before');
const PLAYER_INPUT_SEQUENCE_AFTER_PROOF = Symbol('player-input-sequence-after');
const OBSERVATION_ACTION_CAPABILITY_PROOF = new WeakMap();
const POST_CHOICE_ASSERTION_ORACLE_PROOF = new WeakMap();
const PRODUCTION_EVENT_MARK_PROOF = Symbol('production-event-mark');
const PRODUCTION_EVENT_SLICE_PROOF = Symbol('production-event-slice');
const FLOAT_QUANTUM = 0.000001;

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function quantizeNumber(value) {
  if (!Number.isFinite(value)) return null;
  if (Number.isInteger(value)) return value;
  return Math.round(value / FLOAT_QUANTUM) * FLOAT_QUANTUM;
}

export function jsonSafe(value) {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return value;
  if (typeof value === 'number') return quantizeNumber(value);
  if (Array.isArray(value)) return value.map((item) => jsonSafe(item));
  if (isPlainObject(value)) {
    return Object.fromEntries(Object.keys(value).sort()
      .map((key) => [key, jsonSafe(value[key])]));
  }
  return String(value);
}

export function canonicalJson(value) {
  return JSON.stringify(jsonSafe(value));
}

function godotParserCanonicalJson(value) {
  if (value === null) return 'null';
  if (typeof value === 'string') return JSON.stringify(value);
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) return 'null';
    if (Object.is(value, -0) || value === 0) return '0.0';
    if (Number.isInteger(value)) return `${value}.0`;
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => godotParserCanonicalJson(item)).join(',')}]`;
  }
  const safe = jsonSafe(value);
  return `{${Object.keys(safe).sort().map((key) =>
    `${JSON.stringify(key)}:${godotParserCanonicalJson(safe[key])}`).join(',')}}`;
}

export function canonicalHash(value) {
  return createHash('sha256').update(godotParserCanonicalJson(jsonSafe(value))).digest('hex');
}

export function godotHashCompatibilityVector() {
  const payload = {
    previous_hash: '',
    record_type: 'run',
    run: {
      authored_state: 'authored_spawn',
      content_fingerprint: '73f49ee628bd26aba29baec35157825b9d7450e365306393d611e22d17fac7bd',
      content_fingerprint_schema: 'authored_fragment_resource_bytes_v1',
      gameplay_build_fingerprint: 'fe22f69093b60424e1558ba152e2ef406e09057e6cbf73a9199416e245e53c7c',
      gameplay_build_fingerprint_schema: 'gameplay_build_resource_set_bytes_v1',
      evidence_baseline_id: 'basin_fill_proof:dean_takahashi:web_0_0:authored_input_baseline',
      execution_platform: 'web',
      fragment_id: 'basin_fill_proof',
      persona: 'dean_takahashi',
      repeat_index: 0,
      run_id: 'basin_fill_proof:dean_takahashi:web_0_0',
      seed: 0,
      trace_id: 'basin_fill_proof:dean_takahashi:web_0_0',
    },
    schema: TRACE_SCHEMA,
  };
  return canonicalHash(payload);
}

function unknownKeys(value, allowed, path, issues) {
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) issues.push(`${path}.${key} is not ${PLAYER_OBSERVATION_SCHEMA}`);
  }
}

function validateScreen(value, path, issues, allowEmpty = false) {
  if (!Array.isArray(value)) {
    issues.push(`${path} must be a screen-coordinate array`);
    return;
  }
  if (allowEmpty && value.length === 0) return;
  if (value.length !== 2) {
    issues.push(`${path} must contain exactly two screen coordinates`);
    return;
  }
  if (value.some((coordinate) => !Number.isFinite(coordinate))) {
    issues.push(`${path} coordinates must be finite numbers`);
  }
}

function validateHud(value, path, issues, depth = 0) {
  if (depth > 6) {
    issues.push(`${path} exceeds the HUD presentation depth limit`);
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((item, index) => validateHud(item, `${path}.${index}`, issues, depth + 1));
    return;
  }
  if (isPlainObject(value)) {
    for (const [key, child] of Object.entries(value)) {
      if (!HUD_PRESENTATION_KEYS.has(key)) {
        issues.push(`${path}.${key} is not a HUD presentation field`);
      } else if (key === 'screen') {
        validateScreen(child, `${path}.screen`, issues, true);
      } else {
        validateHud(child, `${path}.${key}`, issues, depth + 1);
      }
    }
    return;
  }
  if (!['string', 'boolean', 'number'].includes(typeof value) && value !== null) {
    issues.push(`${path} is not a safe HUD presentation value`);
  }
  if (typeof value === 'number' && !Number.isFinite(value)) issues.push(`${path} must be finite`);
}

function forbiddenObservationKeys(value, path, issues) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => forbiddenObservationKeys(item, `${path}.${index}`, issues));
    return;
  }
  if (!isPlainObject(value)) return;
  for (const [key, child] of Object.entries(value)) {
    if (FORBIDDEN_OBSERVATION_KEYS.has(key)) {
      issues.push(`${path}.${key} is forbidden internal or world data`);
    }
    forbiddenObservationKeys(child, `${path}.${key}`, issues);
  }
}

function validateCueValues(cue, path, issues) {
  for (const [key, value] of Object.entries(cue)) {
    if (key === 'screen') {
      validateScreen(value, `${path}.screen`, issues);
      continue;
    }
    if (Array.isArray(value)) {
      if (value.some((item) => !['string', 'boolean', 'number'].includes(typeof item)
          || (typeof item === 'number' && !Number.isFinite(item)))) {
        issues.push(`${path}.${key} contains a non-presentation value`);
      }
    } else if (!['string', 'boolean', 'number'].includes(typeof value) && value !== null) {
      issues.push(`${path}.${key} is not a presentation value`);
    } else if (typeof value === 'number' && !Number.isFinite(value)) {
      issues.push(`${path}.${key} must be finite`);
    }
  }
}

function validateMovementRouteStatus(cue, observation, path, issues) {
  const presentKeys = MOVEMENT_ROUTE_STATUS_KEYS.filter((key) => Object.hasOwn(cue, key));
  if (presentKeys.length === 0) return;
  if (presentKeys.length !== MOVEMENT_ROUTE_STATUS_KEYS.length) {
    issues.push(`${path} route-status fields must be present together`);
  }

  const status = cue.route_status;
  const serial = cue.route_status_serial;
  const subjects = cue.route_status_subjects;
  const remaining = cue.route_status_remaining_seconds;
  if (typeof status !== 'string'
      || !['', 'reforming_route', 'cooperative_hold'].includes(status)) {
    issues.push(`${path}.route_status is not a visible movement route status`);
  }
  if (!Number.isInteger(serial) || serial < 0) {
    issues.push(`${path}.route_status_serial must be a non-negative integer`);
  }
  const subjectsValid = Array.isArray(subjects)
    && subjects.every((token) => typeof token === 'string' && token.trim() !== '')
    && new Set(subjects).size === subjects.length;
  if (!subjectsValid) {
    issues.push(`${path}.route_status_subjects must be a unique portrait-token array`);
  }
  const remainingValid = typeof remaining === 'number'
    && Number.isFinite(remaining) && remaining >= 0;
  if (!remainingValid) {
    issues.push(`${path}.route_status_remaining_seconds must be finite and non-negative`);
  }

  if (subjectsValid) {
    const movementSubjects = new Set(Array.isArray(cue.subjects) ? cue.subjects : []);
    const visiblePortraitTokens = new Set((observation?.state?.hud?.portraits ?? [])
      .filter((portrait) => portrait?.visible === true
        && typeof portrait?.token === 'string' && portrait.token.trim() !== '')
      .map((portrait) => portrait.token));
    if (subjects.some((token) => !movementSubjects.has(token))) {
      issues.push(`${path}.route_status_subjects must be a subset of movement subjects`);
    }
    if (subjects.some((token) => !visiblePortraitTokens.has(token))) {
      issues.push(`${path}.route_status_subjects must contain only visible portrait tokens`);
    }
  }

  if (status === '') {
    if (subjectsValid && subjects.length !== 0) {
      issues.push(`${path}.route_status_subjects must be empty without an active route status`);
    }
    if (remainingValid && remaining !== 0) {
      issues.push(`${path}.route_status_remaining_seconds must be zero without an active route status`);
    }
  } else if (['reforming_route', 'cooperative_hold'].includes(status)) {
    if (!Number.isInteger(serial) || serial <= 0) {
      issues.push(`${path}.route_status_serial must be positive for an active route status`);
    }
    if (subjectsValid && subjects.length === 0) {
      issues.push(`${path}.route_status_subjects must be nonempty for an active route status`);
    }
    if (status === 'reforming_route' && remainingValid && remaining !== 0) {
      issues.push(`${path}.route_status_remaining_seconds must be zero while reforming`);
    }
    if (status === 'cooperative_hold' && remainingValid && remaining <= 0) {
      issues.push(`${path}.route_status_remaining_seconds must be positive during a cooperative hold`);
    }
  }
}

export function validatePlayerObservation(observation) {
  const issues = [];
  if (!isPlainObject(observation)) return ['observation must be an object'];
  unknownKeys(observation, OBSERVATION_KEYS, 'observation', issues);
  if (observation.schema !== PLAYER_OBSERVATION_SCHEMA) {
    issues.push(`observation.schema must be ${PLAYER_OBSERVATION_SCHEMA}`);
  }
  if (observation.source !== 'player_observable') {
    issues.push('observation.source must be player_observable');
  }
  if (!Number.isFinite(observation.tick) || observation.tick < 0) {
    issues.push('observation.tick must be a finite non-negative scheduler tick');
  }
  if (!Number.isInteger(observation.capture_serial) || observation.capture_serial < 1) {
    issues.push('observation.capture_serial must be a positive integer');
  }
  if (!isPlainObject(observation.state)) {
    issues.push('observation.state must be an object');
    return issues.sort();
  }
  const state = observation.state;
  unknownKeys(state, OBSERVATION_STATE_KEYS, 'observation.state', issues);
  if (!isPlainObject(state.hud)) issues.push('observation.state.hud must be an object');
  else validateHud(state.hud, 'observation.state.hud', issues);
  if (!isPlainObject(state.viewport)) {
    issues.push('observation.state.viewport must be an object');
  } else {
    unknownKeys(state.viewport, VIEWPORT_PRESENTATION_KEYS, 'observation.state.viewport', issues);
    validateScreen(state.viewport.origin, 'observation.state.viewport.origin', issues);
    validateScreen(state.viewport.size, 'observation.state.viewport.size', issues);
    if (Array.isArray(state.viewport.size) && state.viewport.size.length === 2
        && state.viewport.size.some((coordinate) => Number.isFinite(coordinate) && coordinate < 0)) {
      issues.push('observation.state.viewport.size must be non-negative');
    }
  }
  if (!Array.isArray(state.affordances)) {
    issues.push('observation.state.affordances must be an array');
  } else {
    state.affordances.forEach((affordance, index) => {
      const path = `observation.state.affordances.${index}`;
      if (!isPlainObject(affordance)) {
        issues.push(`${path} must be an object`);
        return;
      }
      unknownKeys(affordance, AFFORDANCE_PRESENTATION_KEYS, path, issues);
      for (const key of ['token', 'kind', 'verb']) {
        if (typeof affordance[key] !== 'string' || affordance[key].trim() === '') {
          issues.push(`${path}.${key} is required`);
        }
      }
      if (typeof affordance.consequence !== 'string') {
        issues.push(`${path}.consequence must be presented text (empty is allowed)`);
      }
      validateScreen(affordance.screen, `${path}.screen`, issues);
    });
  }
  for (const [stateKey, affordanceKey] of [
    ['visible_affordance_verbs', 'verb'],
    ['visible_affordance_consequences', 'consequence'],
  ]) {
    const visibleTexts = state[stateKey];
    if (!Array.isArray(visibleTexts)) {
      issues.push(`observation.state.${stateKey} must be an array`);
      continue;
    }
    if (visibleTexts.some((value) => typeof value !== 'string')) {
      issues.push(`observation.state.${stateKey} must contain only strings`);
      continue;
    }
    const expected = [...new Set((state.affordances ?? [])
      .map((affordance) => String(affordance?.[affordanceKey] ?? '').trim())
      .filter(Boolean))].sort();
    if (canonicalJson(visibleTexts) !== canonicalJson(expected)) {
      issues.push(`observation.state.${stateKey} must be the sorted exact visible ${affordanceKey} list`);
    }
  }
  if (!Array.isArray(state.cues)) {
    issues.push('observation.state.cues must be an array');
  } else {
    state.cues.forEach((cue, index) => {
      const path = `observation.state.cues.${index}`;
      if (!isPlainObject(cue)) {
        issues.push(`${path} must be an object`);
        return;
      }
      unknownKeys(cue, CUE_PRESENTATION_KEYS, path, issues);
      if (typeof cue.kind !== 'string' || cue.kind.trim() === '') issues.push(`${path}.kind is required`);
      validateCueValues(cue, path, issues);
      if (cue.kind === 'movement_result') {
        if (typeof cue.target_token !== 'string' || cue.target_token.trim() === '') {
          issues.push(`${path}.target_token is required`);
        }
        if (!Array.isArray(cue.subjects) || cue.subjects.length === 0) {
          issues.push(`${path}.subjects must be a nonempty portrait-token array`);
        } else if (!sameUniqueStringMembers(cue.subjects, cue.subjects)) {
          issues.push(`${path}.subjects must be unique nonempty tokens`);
        }
        if (!['accepted', 'progress', 'arrival', 'interrupted', 'refused'].includes(cue.phase)) {
          issues.push(`${path}.phase is not a movement-result phase`);
        }
        if (typeof cue.accepted !== 'boolean') issues.push(`${path}.accepted must be explicit`);
        if (typeof cue.reason !== 'string') issues.push(`${path}.reason must be presented text`);
        if (!positiveIntegralNumber(cue.presentation_serial)) {
          issues.push(`${path}.presentation_serial must be positive`);
        }
        validateMovementRouteStatus(cue, observation, path, issues);
      } else if (MOVEMENT_ROUTE_STATUS_KEYS.some((key) => Object.hasOwn(cue, key))) {
        issues.push(`${path} route-status fields require a movement_result cue`);
      }
    });
  }
  if (!isPlainObject(state.viewport_bins)) {
    issues.push('observation.state.viewport_bins must be an object');
  } else {
    for (const [bin, tokens] of Object.entries(state.viewport_bins)) {
      if (!/^[a-z0-9]+(?:_[a-z0-9]+)*$/.test(bin)) {
        issues.push(`observation.state.viewport_bins.${bin} is not a semantic viewport bin`);
        continue;
      }
      if (!Array.isArray(tokens)) {
        issues.push(`observation.state.viewport_bins.${bin} must be an array of presentation tokens`);
      } else if (tokens.some((token) => typeof token !== 'string' || token.trim() === '')) {
        issues.push(`observation.state.viewport_bins.${bin} contains an invalid presentation token`);
      }
    }
  }
  forbiddenObservationKeys(state, 'observation.state', issues);
  return [...new Set(issues)].sort();
}

function sameStringMembers(left, right) {
  return Array.isArray(left) && Array.isArray(right)
    && [...left].map(String).sort().join('\0') === [...right].map(String).sort().join('\0');
}

function sameUniqueStringMembers(left, right) {
  if (!Array.isArray(left) || !Array.isArray(right)) return false;
  const normalized = (values) => values.map(String);
  const leftValues = normalized(left);
  const rightValues = normalized(right);
  if (leftValues.some((value) => value === '') || rightValues.some((value) => value === '')
      || new Set(leftValues).size !== leftValues.length
      || new Set(rightValues).size !== rightValues.length) return false;
  return sameStringMembers(leftValues, rightValues);
}

function inferredWorldChange(verb) {
  if (WORLD_CHANGE_VERBS.has(verb)) return true;
  if (OBSERVATION_ONLY_VERBS.has(verb)) return false;
  return true;
}

function inferredGroupVerb(decision) {
  const verb = String(decision?.verb ?? '').toLowerCase();
  return verb === 'rally'
    || (inferredWorldChange(verb) && (decision?.intended_subjects?.length ?? 0) > 1);
}

export function normalizeObservationSamples(samples) {
  const result = [];
  const seen = new Set();
  for (const sample of samples ?? []) {
    const safe = jsonSafe(sample);
    const encoded = canonicalJson(safe);
    if (seen.has(encoded)) continue;
    seen.add(encoded);
    result.push(safe);
  }
  return result;
}

function visibleCueRecords(observation, kind = null) {
  return (observation?.state?.cues ?? []).filter((cue) =>
    cue?.visible === true && (kind === null || cue.kind === kind));
}

function postObservations(samples, observationAfter) {
  const result = normalizeObservationSamples(samples);
  const after = jsonSafe(observationAfter);
  if (!result.some((observation) => canonicalJson(observation) === canonicalJson(after))) {
    result.push(after);
  }
  return result;
}

function highestVisibleInteractionResultSerial(observation, targetToken) {
  let highest = 0;
  for (const cue of visibleCueRecords(observation, 'interaction_result')) {
    if (cue.source_token !== targetToken || !['success', 'rejected'].includes(cue.result)
        || !positiveIntegralNumber(cue.presentation_serial)) continue;
    highest = Math.max(highest, cue.presentation_serial);
  }
  return highest;
}

function newestExactInteractionResult(before, observations, targetToken) {
  if (!targetToken) return {};
  const beforeSerial = highestVisibleInteractionResultSerial(before, targetToken);
  let newest = null;
  for (const observation of observations) {
    for (const cue of visibleCueRecords(observation, 'interaction_result')) {
      if (cue.source_token !== targetToken) continue;
      const serial = cue.presentation_serial;
      if (!Number.isInteger(serial) || serial <= beforeSerial || serial <= 0) continue;
      if (!['success', 'rejected'].includes(cue.result)) continue;
      if (newest === null || serial > newest.presentation_serial) {
        newest = {
          source_token: targetToken,
          presentation_serial: serial,
          result: String(cue.result),
          visible: true,
        };
      }
    }
  }
  return newest ?? {};
}

function highestVisibleMovementResultSerial(observation, targetToken) {
  let highest = 0;
  for (const cue of visibleCueRecords(observation, 'movement_result')) {
    if ((targetToken && cue.target_token !== targetToken)
        || !positiveIntegralNumber(cue.presentation_serial)) continue;
    highest = Math.max(highest, cue.presentation_serial);
  }
  return highest;
}

function derivedMovementResult(observationBefore, observations, decision) {
  const targetToken = String(decision?.target?.token ?? '');
  if (!targetToken) return {};
  // Presentation serials are global. Collect every new movement result after
  // the input so a second command or a result for another target cannot hide
  // beside the intended lineage.
  const beforeSerial = highestVisibleMovementResultSerial(observationBefore, '');
  const lineages = new Map();
  observations.forEach((observation, observationIndex) => {
    const captureSerial = Number(observation?.capture_serial ?? 0);
    for (const cue of visibleCueRecords(observation, 'movement_result')) {
      if (!positiveIntegralNumber(cue.presentation_serial)
          || cue.presentation_serial <= beforeSerial) continue;
      const serial = cue.presentation_serial;
      const cueTargetToken = String(cue.target_token ?? '');
      const lineage = lineages.get(serial) ?? {
        target_token: cueTargetToken,
        subjects: [],
        presentation_serial: serial,
        phases: [],
        phase_capture_serials: {},
        accepted: Boolean(cue.accepted),
        reason: '',
        visible: true,
        subjects_consistent: true,
        accepted_consistent: true,
        target_consistent: true,
        phase_order_valid: true,
        last_phase_rank: -1,
      };
      if (lineage.target_token !== cueTargetToken) lineage.target_consistent = false;
      const subjects = Array.isArray(cue.subjects) ? cue.subjects.map(String).sort() : [];
      if (lineage.subjects.length === 0) lineage.subjects = subjects;
      else if (canonicalJson(lineage.subjects) !== canonicalJson(subjects)) {
        lineage.subjects_consistent = false;
      }
      if (lineage.accepted !== Boolean(cue.accepted)) lineage.accepted_consistent = false;
      const phase = String(cue.phase ?? '').toLowerCase();
      const phaseRank = {
        accepted: 0, progress: 1, arrival: 2, interrupted: 2, refused: 0,
      }[phase] ?? -1;
      if (phaseRank >= 0) {
        if (lineage.last_phase_rank >= 0
            && (phaseRank < lineage.last_phase_rank
              || phaseRank > lineage.last_phase_rank + 1)) {
          lineage.phase_order_valid = false;
        }
        lineage.last_phase_rank = Math.max(lineage.last_phase_rank, phaseRank);
      }
      if (phase && !lineage.phases.includes(phase)) {
        lineage.phases.push(phase);
        lineage.phase_capture_serials[phase] = captureSerial;
      } else if (['arrival', 'interrupted'].includes(phase)) {
        lineage.phase_capture_serials[phase] = captureSerial;
      }
      const reason = String(cue.reason ?? '').trim();
      if (reason) lineage.reason = reason;
      lineage.last_observation_index = observationIndex;
      lineages.set(serial, lineage);
    }
  });
  if (lineages.size === 0) return {};
  const firstSerial = [...lineages.keys()].sort((left, right) => left - right)[0];
  return jsonSafe({ ...lineages.get(firstSerial), new_serial_count: lineages.size });
}

export function deriveDecisionArtifacts({
  observationBefore, observationAfter, observationSamples, decision, inputReceipt,
}) {
  const observations = postObservations(observationSamples, observationAfter);
  const beforeCueSet = new Set((observationBefore?.state?.cues ?? [])
    .filter((cue) => cue?.kind !== 'party_body').map((cue) => canonicalJson(cue)));
  const feedbackCues = [];
  const feedbackCueSet = new Set();
  for (const observation of observations) {
    for (const cue of visibleCueRecords(observation)) {
      if (cue.kind === 'party_body') continue;
      const encoded = canonicalJson(cue);
      if (beforeCueSet.has(encoded) || feedbackCueSet.has(encoded)) continue;
      feedbackCueSet.add(encoded);
      feedbackCues.push(jsonSafe(cue));
    }
  }

  const finalCueSet = new Set(visibleCueRecords(observations.at(-1))
    .filter((cue) => cue.kind !== 'party_body').map((cue) => canonicalJson(cue)));
  const removedCues = [];
  const removedCueSet = new Set();
  for (const cue of visibleCueRecords(observationBefore)) {
    if (cue.kind === 'party_body') continue;
    const encoded = canonicalJson(cue);
    if (finalCueSet.has(encoded) || removedCueSet.has(encoded)) continue;
    removedCueSet.add(encoded);
    removedCues.push(jsonSafe(cue));
  }

  const beforeBodies = new Map();
  for (const cue of visibleCueRecords(observationBefore, 'party_body')) {
    if (typeof cue.source_token === 'string' && Array.isArray(cue.screen)) {
      beforeBodies.set(cue.source_token, canonicalJson(cue.screen));
    }
  }
  const movedSubjects = new Set();
  for (const observation of observations) {
    for (const cue of visibleCueRecords(observation, 'party_body')) {
      const token = String(cue.source_token ?? '');
      if (token && beforeBodies.has(token)
          && beforeBodies.get(token) !== canonicalJson(cue.screen)) movedSubjects.add(token);
    }
  }
  const moved = [...movedSubjects].sort();
  const beforeState = observationBefore?.state ?? {};
  const changedFields = [...OBSERVATION_STATE_KEYS].filter((field) =>
    observations.some((observation) => canonicalJson(beforeState[field])
      !== canonicalJson(observation?.state?.[field]))).sort();
  const presentationDelta = {
    observed: changedFields.length > 0,
    changed_fields: changedFields,
    added_cue_count: feedbackCues.length,
    removed_cue_count: removedCues.length,
  };
  const feedback = jsonSafe({
    player_observable: presentationDelta.observed,
    cues: feedbackCues,
    removed_cues: removedCues,
    presentation_delta: presentationDelta,
    party_body_movement: {
      observed: moved.length > 0,
      subjects: moved,
      classification: 'screen_space_presentation_only',
    },
  });
  const targetToken = String(decision?.target?.token ?? '');
  const interactionResult = String(decision?.verb ?? '').toLowerCase() === 'interact'
    ? newestExactInteractionResult(observationBefore, observations, targetToken) : {};
  const verb = String(decision?.verb ?? '').toLowerCase();
  const movementResult = ['move', 'rally'].includes(verb)
    ? derivedMovementResult(observationBefore, observations, decision) : {};
  const causalMoved = ['move', 'rally'].includes(verb)
      && Object.keys(movementResult).length > 0
      && movementResult.accepted !== true
    ? [] : moved;
  const visibleChange = presentationDelta.observed;
  const passiveNoDelta = verb === 'wait' && !visibleChange;
  let status = passiveNoDelta ? 'observed' : String(inputReceipt?.status ?? '');
  if (verb === 'interact') {
    if (interactionResult.result === 'success') status = 'accepted';
    else if (interactionResult.result === 'rejected') status = 'refused';
    else status = 'unproven';
  } else if (['move', 'rally'].includes(verb)) {
    status = Object.keys(movementResult).length === 0
      ? 'unproven' : (movementResult.accepted ? 'accepted' : 'refused');
  }
  let worldCausalEvidence = feedbackCues.length > 0 || moved.length > 0;
  if (verb === 'interact') worldCausalEvidence = Object.keys(interactionResult).length > 0;
  else if (['move', 'rally'].includes(verb)) {
    worldCausalEvidence = Object.keys(movementResult).length > 0;
  } else if (['camera_pan', 'camera_recenter', 'camera_rotate', 'camera_zoom'].includes(verb)) {
    // Camera-relative drift proves a presentation input, never a world outcome.
    worldCausalEvidence = false;
  }
  feedback.movement_result = movementResult;
  const outcome = jsonSafe({
    status,
    accepted: status === 'accepted' && !passiveNoDelta,
    visible_change: visibleChange,
    cue_count: feedbackCues.length,
    // Body pixels remain useful presentation description, but an exact refused
    // command cannot causally own camera-relative drift.
    moved_subjects: causalMoved,
    interaction_result: interactionResult,
    movement_result: movementResult,
    passive_no_delta: passiveNoDelta,
    world_causal_evidence: worldCausalEvidence,
  });
  return { feedback, outcome };
}

export function movementCandidateDemonstrated(
  outcome, observationAfter, { persona = '', inputReceipt = {} } = {},
) {
  const result = outcome?.movement_result;
  if (!isPlainObject(result)
      || result.new_serial_count !== 1
      || result.subjects_consistent !== true
      || result.accepted_consistent !== true
      || result.target_consistent !== true
      || result.phase_order_valid !== true) return false;
  const phaseSerials = result.phase_capture_serials ?? {};
  const terminalCapture = Number(observationAfter?.capture_serial ?? 0);
  if (result.accepted === true) {
    return String(result.reason ?? '').trim() === ''
      && canonicalJson(result.phases ?? [])
        === canonicalJson(['accepted', 'progress', 'arrival'])
      && Number(phaseSerials.accepted ?? 0) < Number(phaseSerials.progress ?? 0)
      && Number(phaseSerials.progress ?? 0) < Number(phaseSerials.arrival ?? 0)
      && Number(phaseSerials.arrival ?? 0) === terminalCapture;
  }
  // Dean's policy is the human-visible pointless attempt, so an exact atomic
  // whole-party refusal may demonstrate it. This exception cannot admit an
  // accepted route that later ends interrupted. The short refusal may be an
  // in-action sample: pointer parking deliberately takes a strictly newer
  // terminal capture after preserving that visible answer.
  const refusalCapture = Number(phaseSerials.refused ?? 0);
  return persona === 'dean_takahashi'
    && String(result.reason ?? '').trim() !== ''
    && canonicalJson(result.phases ?? []) === canonicalJson(['refused'])
    && refusalCapture > 0
    && refusalCapture <= terminalCapture
    && inputReceipt?.status === 'refused'
    && inputReceipt?.input_issued === true
    && inputReceipt?.atomic_group === true
    && Number(inputReceipt?.production_event_count ?? -1) === 0;
}

function positiveIntegralNumber(value) {
  return Number.isInteger(value) && value > 0;
}

function visibleAffordanceToken(observation, targetToken) {
  return (observation?.state?.affordances ?? []).some((affordance) =>
    affordance?.token === targetToken);
}

function interactionTargetResultReasons(before, after, samples, decision, receipt, outcome) {
  const reasons = [];
  const targetToken = String(decision?.target?.token ?? '');
  if (!targetToken) return ['interaction_target_token_missing'];
  if (!visibleAffordanceToken(before, targetToken)) {
    reasons.push('interaction_target_not_visible_before');
  }
  const result = outcome?.interaction_result ?? {};
  if (!isPlainObject(result) || Object.keys(result).length === 0) {
    const beforeSerial = highestVisibleInteractionResultSerial(before, targetToken);
    let sawStaleExact = false;
    let sawOtherTarget = false;
    let sawInvalidExact = false;
    for (const observation of postObservations(samples, after)) {
      for (const cue of visibleCueRecords(observation, 'interaction_result')) {
        if (cue.source_token !== targetToken) {
          sawOtherTarget = true;
        } else if (!positiveIntegralNumber(cue.presentation_serial)) {
          sawInvalidExact = true;
        } else if (cue.presentation_serial <= beforeSerial) {
          sawStaleExact = true;
        }
      }
    }
    if (sawInvalidExact) reasons.push('interaction_target_result_serial_invalid');
    else if (sawStaleExact) reasons.push('interaction_target_result_not_new');
    else if (sawOtherTarget) reasons.push('interaction_target_result_source_mismatch');
    else reasons.push('interaction_target_result_missing');
    return reasons;
  }
  if (result.source_token !== targetToken) reasons.push('interaction_target_result_source_mismatch');
  if (result.visible !== true) reasons.push('interaction_target_result_not_visible');
  if (!positiveIntegralNumber(result.presentation_serial)) {
    reasons.push('interaction_target_result_serial_invalid');
  } else if (result.presentation_serial <= highestVisibleInteractionResultSerial(before, targetToken)) {
    reasons.push('interaction_target_result_not_new');
  }
  const expectedResult = receipt.status === 'accepted' ? 'success'
    : (receipt.status === 'refused' ? 'rejected' : '');
  if (!expectedResult || result.result !== expectedResult) {
    reasons.push('interaction_target_result_status_mismatch');
  }
  return reasons;
}

function visibleHudRoster(observation) {
  const subjectIds = [];
  const portraitTokens = [];
  const tokenBySubject = {};
  const reasons = [];
  const portraits = observation?.state?.hud?.portraits;
  if (!Array.isArray(portraits)) {
    return {
      valid: false, subject_ids: subjectIds, portrait_tokens: portraitTokens,
      token_by_subject: tokenBySubject, reasons: ['portraits_missing'],
    };
  }
  const seenSubjects = new Set();
  const seenTokens = new Set();
  portraits.forEach((portrait, index) => {
    if (!isPlainObject(portrait)) return;
    if (typeof portrait.visible !== 'boolean') {
      reasons.push(`portraits.${index}.visible_must_be_explicit`);
    }
    if (portrait.visible !== true) return;
    const subject = normalizeVisibleSubjectId(portrait.label);
    const token = String(portrait.token ?? '').trim();
    if (!subject) reasons.push(`portraits.${index}.visible_label_missing`);
    else if (seenSubjects.has(subject)) reasons.push(`visible_label_duplicate:${subject}`);
    if (!token) reasons.push(`portraits.${index}.visible_token_missing`);
    else if (seenTokens.has(token)) reasons.push(`visible_token_duplicate:${token}`);
    if (subject && token && !seenSubjects.has(subject) && !seenTokens.has(token)) {
      seenSubjects.add(subject);
      seenTokens.add(token);
      subjectIds.push(subject);
      portraitTokens.push(token);
      tokenBySubject[subject] = token;
    }
  });
  subjectIds.sort();
  portraitTokens.sort();
  reasons.sort();
  return {
    valid: reasons.length === 0 && subjectIds.length > 0,
    subject_ids: subjectIds,
    portrait_tokens: portraitTokens,
    token_by_subject: tokenBySubject,
    reasons,
  };
}

function bodyTokensForPortraits(observation, portraitTokens) {
  const result = [];
  for (const cue of visibleCueRecords(observation, 'party_body')) {
    if (!portraitTokens.includes(String(cue.binding ?? ''))) continue;
    const bodyToken = String(cue.source_token ?? '');
    if (bodyToken && !result.includes(bodyToken)) result.push(bodyToken);
  }
  return result.sort();
}

function movementResultReasons(before, after, samples, decision, receipt, feedback, outcome) {
  const reasons = [];
  const targetToken = String(decision?.target?.token ?? '');
  if (!targetToken) return ['movement_target_token_missing'];
  reasons.push(...movementTargetAffordanceReasons(before, decision));
  const roster = visibleHudRoster(before);
  let expectedTokens = [];
  if (String(decision?.verb ?? '').toLowerCase() === 'rally') {
    expectedTokens = [...roster.portrait_tokens];
  } else {
    expectedTokens = (decision?.intended_subjects ?? [])
      .map((subject) => roster.token_by_subject[String(subject)] ?? '').filter(Boolean).sort();
  }
  const result = outcome?.movement_result;
  if (!isPlainObject(result) || Object.keys(result).length === 0) {
    const beforeSerial = highestVisibleMovementResultSerial(before, targetToken);
    let sawStaleExact = false;
    let sawWrongTarget = false;
    let sawInvalidSerial = false;
    for (const observation of postObservations(samples, after)) {
      for (const cue of visibleCueRecords(observation, 'movement_result')) {
        if (cue.target_token !== targetToken) sawWrongTarget = true;
        else if (!positiveIntegralNumber(cue.presentation_serial)) sawInvalidSerial = true;
        else if (cue.presentation_serial <= beforeSerial) sawStaleExact = true;
      }
    }
    if (sawInvalidSerial) reasons.push('movement_result_serial_invalid');
    else if (sawStaleExact) reasons.push('movement_result_not_new');
    else if (sawWrongTarget) reasons.push('movement_result_target_mismatch');
    else reasons.push('movement_result_missing');
    return reasons;
  }
  if (result.new_serial_count !== 1) reasons.push('movement_result_multiple_new_serials');
  if (result.subjects_consistent !== true) {
    reasons.push('movement_result_subjects_changed_within_lineage');
  }
  if (result.accepted_consistent !== true) {
    reasons.push('movement_result_acceptance_changed_within_lineage');
  }
  if (result.target_consistent !== true) {
    reasons.push('movement_result_target_changed_within_lineage');
  }
  if (result.phase_order_valid !== true) {
    reasons.push('movement_result_phase_regression_or_skip');
  }
  if (result.target_token !== targetToken) reasons.push('movement_result_target_mismatch');
  if (!sameUniqueStringMembers(result.subjects, expectedTokens)) {
    reasons.push('movement_result_subject_tokens_do_not_match_intent');
  }
  const receiptAccepted = receipt.status === 'accepted';
  if (Boolean(result.accepted) !== receiptAccepted) reasons.push('movement_result_status_mismatch');
  const phases = result.phases ?? [];
  const phaseSerials = result.phase_capture_serials ?? {};
  if (receiptAccepted) {
    let terminalPhase = '';
    if (canonicalJson(phases) === canonicalJson(['accepted', 'progress', 'arrival'])) {
      terminalPhase = 'arrival';
    } else if (canonicalJson(phases)
        === canonicalJson(['accepted', 'progress', 'interrupted'])) {
      terminalPhase = 'interrupted';
    }
    if (!terminalPhase) {
      reasons.push('movement_result_phase_sequence_invalid');
    } else {
      const acceptedSerial = Number(phaseSerials.accepted ?? 0);
      const progressSerial = Number(phaseSerials.progress ?? 0);
      const terminalSerial = Number(phaseSerials[terminalPhase] ?? 0);
      if (!(acceptedSerial < progressSerial && progressSerial < terminalSerial)) {
        reasons.push('movement_result_phase_order_invalid');
      }
      const sampleSerials = new Set((samples ?? []).map((sample) => Number(
        sample?.capture_serial ?? 0,
      )));
      if (!sampleSerials.has(progressSerial)) {
        reasons.push('accepted_movement_progress_sample_missing');
      }
      if (terminalSerial !== Number(after?.capture_serial ?? 0)) {
        reasons.push(terminalPhase === 'arrival'
          ? 'accepted_movement_terminal_arrival_missing'
          : 'accepted_movement_terminal_interruption_missing');
      }
    }
    const resultReason = String(result.reason ?? '').trim();
    if (terminalPhase === 'arrival' && resultReason !== '') {
      reasons.push('accepted_movement_result_has_refusal_reason');
    } else if (terminalPhase === 'interrupted' && resultReason === '') {
      reasons.push('interrupted_movement_visible_reason_missing');
    }
  } else {
    if (canonicalJson(phases) !== canonicalJson(['refused'])) {
      reasons.push('movement_refusal_phase_invalid');
    }
    if (String(result.reason ?? '').trim() === '') {
      reasons.push('movement_refusal_visible_reason_missing');
    }
    if (receipt.production_event_count !== 0) {
      reasons.push('movement_refusal_production_event_count_not_zero');
    }
  }
  if (canonicalJson(feedback?.movement_result ?? {}) !== canonicalJson(result)) {
    reasons.push('movement_feedback_lineage_mismatch');
  }
  return reasons;
}

export function movementTargetAffordanceReasons(before, decision) {
  const targetToken = String(decision?.target?.token ?? '');
  if (!targetToken) return ['movement_target_token_missing'];
  const targetAffordance = (before?.state?.affordances ?? [])
    .find((affordance) => affordance?.token === targetToken);
  const kind = String(targetAffordance?.kind ?? '');
  const verb = String(decision?.verb ?? '').toLowerCase();
  if (kind === 'move' || (verb === 'rally' && kind === 'interact')) return [];
  return ['movement_target_not_visible_move_affordance_before'];
}

function fullRosterActionReasons(before, decision, receipt, outcome, requireMovementTokens) {
  const reasons = [];
  const roster = visibleHudRoster(before);
  if (!roster.valid) return ['visible_hud_roster_not_unique_complete'];
  if (!sameUniqueStringMembers(decision?.intended_subjects, roster.subject_ids)) {
    reasons.push('decision_subjects_do_not_equal_full_visible_roster');
  }
  if (!sameUniqueStringMembers(receipt?.intended_members, roster.subject_ids)) {
    reasons.push('receipt_members_do_not_equal_full_visible_roster');
  }
  if (!isPlainObject(receipt?.member_results)
      || !sameUniqueStringMembers(Object.keys(receipt.member_results), roster.subject_ids)) {
    reasons.push('receipt_result_keys_do_not_equal_full_visible_roster');
  } else if (['accepted', 'refused'].includes(receipt.status)) {
    for (const subject of roster.subject_ids) {
      if (receipt.member_results[subject] !== receipt.status) {
        reasons.push(`receipt_result_not_atomic_for_full_roster:${subject}`);
      }
    }
  }
  if (requireMovementTokens
      && !sameUniqueStringMembers(outcome?.movement_result?.subjects, roster.portrait_tokens)) {
    reasons.push('movement_feedback_tokens_do_not_equal_full_visible_roster');
  }
  return reasons;
}

function observationSequenceReasons(before, samples, after) {
  const reasons = [];
  if (!positiveIntegralNumber(before?.capture_serial)
      || !positiveIntegralNumber(after?.capture_serial)) {
    return ['observation_capture_serial_missing'];
  }
  let previousSerial = before.capture_serial;
  let previousTick = Number(before.tick ?? 0);
  (samples ?? []).forEach((sample, index) => {
    if (!isPlainObject(sample) || !positiveIntegralNumber(sample.capture_serial)) {
      reasons.push(`observation_sample_capture_serial_missing:${index}`);
      return;
    }
    if (sample.capture_serial === previousSerial) {
      reasons.push(`observation_capture_replayed:${sample.capture_serial}`);
    } else if (sample.capture_serial < previousSerial) {
      reasons.push(`observation_capture_reordered:${sample.capture_serial}`);
    }
    if (Number(sample.tick ?? 0) < previousTick) {
      reasons.push(`observation_tick_regressed:${index}`);
    }
    previousSerial = Math.max(previousSerial, sample.capture_serial);
    previousTick = Math.max(previousTick, Number(sample.tick ?? 0));
  });
  if (after.capture_serial === previousSerial) {
    reasons.push('observation_after_replays_prior_capture');
  } else if (after.capture_serial < previousSerial) {
    reasons.push('observation_sample_occurs_after_terminal_capture');
  }
  if (Number(after.tick ?? 0) < previousTick) {
    reasons.push('observation_tick_regressed_at_terminal_capture');
  }
  return [...new Set(reasons)].sort();
}

export function inputSequenceProgressionReasons(previousDecisions, currentRecord) {
  const currentReceipt = currentRecord?.input_receipt;
  if (!isPlainObject(currentReceipt)
      || currentReceipt.boundary !== 'keyboard_pointer'
      || currentReceipt.input_issued !== true) return [];
  const currentBefore = Number.isInteger(currentReceipt.input_sequence_before)
    ? currentReceipt.input_sequence_before : -1;
  let previousAfter = 0;
  for (let index = (previousDecisions ?? []).length - 1; index >= 0; index -= 1) {
    const receipt = previousDecisions[index]?.input_receipt;
    if (!isPlainObject(receipt)
        || receipt.boundary !== 'keyboard_pointer'
        || receipt.input_issued !== true) continue;
    previousAfter = Number.isInteger(receipt.input_sequence_after)
      ? receipt.input_sequence_after : -1;
    break;
  }
  if (currentBefore < previousAfter) return ['input_event_sequence_reused_across_decisions'];
  if (currentBefore > previousAfter) return ['input_event_sequence_gap_across_decisions'];
  return [];
}

export function observationProgressionReasons(previousDecisions, currentRecord) {
  if (!Array.isArray(previousDecisions) || previousDecisions.length === 0) return [];
  const previousAfter = previousDecisions.at(-1)?.observation_after;
  const currentBefore = currentRecord?.observation_before;
  if (!isPlainObject(previousAfter) || !isPlainObject(currentBefore)) return [];
  const reasons = [];
  if (Number(currentBefore.capture_serial ?? 0)
      <= Number(previousAfter.capture_serial ?? 0)) {
    reasons.push('observation_capture_not_monotonic_across_decisions');
  }
  if (Number(currentBefore.tick ?? 0) < Number(previousAfter.tick ?? 0)) {
    reasons.push('observation_tick_regressed_across_decisions');
  }
  return reasons;
}

function selectionKeyForSubject(subject) {
  switch (normalizeVisibleSubjectId(subject)) {
    case 'aster': return 'Digit1';
    case 'peris': return 'Digit2';
    case 'endo': return 'Digit3';
    default: return '';
  }
}

function visibleSelectedSubjectIds(observation) {
  const portraits = observation?.state?.hud?.portraits;
  if (!Array.isArray(portraits)) return [];
  return [...new Set(portraits
    .filter((portrait) => portrait?.visible === true && portrait?.selected === true)
    .map((portrait) => normalizeVisibleSubjectId(portrait?.label))
    .filter(Boolean))].sort();
}

function selectionPressHasModifiers(event, ctrl) {
  const modifiers = event?.modifiers;
  return isPlainObject(modifiers)
    && modifiers.ctrl === ctrl
    && modifiers.shift === false
    && modifiers.alt === false
    && modifiers.meta === false;
}

function selectSingleGestureIsExact(
  decision, keyPairs, selectionPressEvents, before, after,
) {
  const intended = decision?.intended_subjects;
  if (!Array.isArray(intended) || intended.length !== 1) return false;
  const targetId = normalizeVisibleSubjectId(intended[0]);
  const targetKey = selectionKeyForSubject(targetId);
  if (!targetId || !targetKey
      || canonicalJson(visibleSelectedSubjectIds(after)) !== canonicalJson([targetId])) {
    return false;
  }

  // Direct singleton selection uses one unmodified pair for the target.
  if (selectionPressEvents.length === 1
      && (keyPairs.get(targetKey) ?? 0) === 1
      && selectionPressEvents[0]?.key === targetKey
      && selectionPressHasModifiers(selectionPressEvents[0], false)) {
    return true;
  }

  // A human retaining an already-selected portrait removes every selected
  // sibling with Ctrl+number. The retained portrait's key is intentionally not
  // pressed because that shipped gesture would be a no-op.
  const selectedBefore = visibleSelectedSubjectIds(before);
  if (selectedBefore.length <= 1 || !selectedBefore.includes(targetId)) return false;
  const siblingKeys = selectedBefore.filter((subject) => subject !== targetId)
    .map(selectionKeyForSubject).sort();
  if (siblingKeys.length === 0 || siblingKeys.some((key) => !key)
      || new Set(siblingKeys).size !== siblingKeys.length
      || selectionPressEvents.length !== siblingKeys.length) return false;
  const pressedKeys = [];
  for (const event of selectionPressEvents) {
    const key = String(event?.key ?? '');
    if (!siblingKeys.includes(key) || pressedKeys.includes(key)
        || (keyPairs.get(key) ?? 0) !== 1
        || !selectionPressHasModifiers(event, true)) return false;
    pressedKeys.push(key);
  }
  return canonicalJson(pressedKeys.sort()) === canonicalJson(siblingKeys);
}

function verbGestureReasons(verb, decision, eventKeys, keyPairs, pointerPairs,
  selectionPressEvents, inputEvents, before, after) {
  const reasons = [];
  let allowedKeys = [];
  let allowedButtons = [];
  switch (verb) {
    case 'move':
    case 'interact':
    case 'use':
      allowedKeys = ['Digit1', 'Digit2', 'Digit3'];
      allowedButtons = [2];
      if ((pointerPairs.get(2) ?? 0) !== 1) {
        reasons.push('world_action_right_pointer_pair_must_be_exactly_one');
      }
      break;
    case 'rally':
      allowedButtons = [2];
      if ((pointerPairs.get(2) ?? 0) !== 1) {
        reasons.push('rally_right_pointer_pair_must_be_exactly_one');
      }
      break;
    case 'push':
      allowedKeys = ['Digit1', 'Digit2', 'Digit3'];
      allowedButtons = [1, 2];
      if ((pointerPairs.get(1) ?? 0) < 1 || (pointerPairs.get(2) ?? 0) < 1) {
        reasons.push('push_pointer_plan_commit_pairs_missing');
      }
      break;
    case 'select_party': { // every visible member gets one real number-key pair
      allowedKeys = ['Digit1', 'Digit2', 'Digit3'];
      const expectedKeys = [...new Set((decision?.intended_subjects ?? [])
        .map(selectionKeyForSubject).filter(Boolean))];
      if (expectedKeys.length === 0) reasons.push('select_party_subject_key_mapping_missing');
      for (const key of expectedKeys) {
        if ((keyPairs.get(key) ?? 0) !== 1) {
          reasons.push(`select_party_subject_key_pair_missing:${key}`);
        }
      }
      if (selectionPressEvents.length !== expectedKeys.length) {
        reasons.push('select_party_selection_chord_size_mismatch');
      } else {
        selectionPressEvents.forEach((event, index) => {
          const modifiers = event.modifiers ?? {};
          if (modifiers.ctrl !== (index > 0) || modifiers.shift || modifiers.alt || modifiers.meta) {
            reasons.push('select_party_selection_chord_invalid');
          }
        });
      }
      break;
    }
    case 'select_single': {
      allowedKeys = ['Digit1', 'Digit2', 'Digit3'];
      if (!selectSingleGestureIsExact(
        decision, keyPairs, selectionPressEvents, before, after,
      )) {
        reasons.push('select_single_subject_key_pair_missing');
      }
      break;
    }
    case 'camera_pan': {
      allowedKeys = ['KeyW', 'KeyA', 'KeyS', 'KeyD'];
      const panPairCount = allowedKeys.reduce(
        (total, key) => total + (keyPairs.get(key) ?? 0), 0,
      );
      if (eventKeys.length !== 1 || panPairCount < 1) {
        reasons.push('camera_pan_wasd_key_pairs_missing_or_ambiguous');
      }
      break;
    }
    case 'camera_rotate': {
      allowedKeys = ['KeyQ', 'KeyE'];
      const rotatePairCount = allowedKeys.reduce(
        (total, key) => total + (keyPairs.get(key) ?? 0), 0,
      );
      if (eventKeys.length !== 1 || rotatePairCount !== 1) {
        reasons.push('camera_rotate_qe_key_pair_missing_or_ambiguous');
      }
      break;
    }
    case 'camera_recenter':
    case 'recenter':
      allowedKeys = ['Home'];
      if ((keyPairs.get('Home') ?? 0) !== 1) reasons.push('recenter_home_key_pair_missing');
      break;
    case 'toggle_instructions':
      allowedKeys = ['KeyH'];
      if ((keyPairs.get('KeyH') ?? 0) !== 1) {
        reasons.push('toggle_instructions_h_key_pair_missing');
      }
      break;
    case 'toggle_run':
      allowedKeys = ['Digit1', 'Digit2', 'Digit3', 'KeyR'];
      if ((keyPairs.get('KeyR') ?? 0) !== 1) reasons.push('toggle_run_r_key_pair_missing');
      break;
    case 'camera_zoom':
    case 'zoom_out':
      allowedButtons = [5];
      if ((pointerPairs.get(5) ?? 0) < 1) reasons.push('zoom_out_wheel_down_pair_missing');
      break;
    case 'wait':
    case 'focus':
      allowedKeys = ['KeyF'];
      if ((keyPairs.get('KeyF') ?? 0) !== 1) reasons.push('active_wait_f_key_pair_missing');
      break;
    case 'pause':
      allowedKeys = ['Space'];
      if ((keyPairs.get('Space') ?? 0) !== 1) reasons.push('pause_space_key_pair_missing');
      break;
    default: reasons.push(`active_action_verb_gesture_unrecognized:${verb}`);
  }
  for (const key of eventKeys) {
    if (!allowedKeys.includes(key)) reasons.push(`verb_unrelated_key_event:${verb}:${key}`);
  }
  for (const event of inputEvents) {
    if (event?.kind !== 'key' || !isPlainObject(event.modifiers)) continue;
    const { ctrl, shift, alt, meta } = event.modifiers;
    if (shift || alt || meta || (!String(event.key ?? '').startsWith('Digit') && ctrl)) {
      reasons.push(`verb_key_modifiers_invalid:${verb}:${String(event.key ?? '')}`);
    }
  }
  for (const button of pointerPairs.keys()) {
    if (!allowedButtons.includes(button)) {
      reasons.push(`verb_unrelated_pointer_button:${verb}:${button}`);
    }
  }
  for (const event of inputEvents) {
    if (event?.kind === 'pointer_button' && allowedButtons.includes(event.button)
        && !pointerPairs.has(event.button)) {
      reasons.push(`verb_pointer_button_pair_incomplete:${verb}:${event.button}`);
    }
  }
  return reasons;
}

function receiptInputProofReasons(decision, receipt, before, samples, after) {
  const reasons = [];
  const verb = String(decision?.verb ?? '').toLowerCase();
  const boundary = String(receipt?.boundary ?? '');
  const events = Array.isArray(receipt?.input_events) ? receipt.input_events : [];
  const kinds = Array.isArray(receipt?.production_event_kinds)
    ? receipt.production_event_kinds : [];
  if (!Array.isArray(receipt?.production_event_kinds)
      || !Number.isInteger(receipt?.production_event_count)
      || receipt.production_event_count < 0) reasons.push('production_event_proof_fields_invalid');
  if (verb === 'wait' && boundary === 'player_command') {
    if (receipt.input_issued !== false || receipt.input_event_count !== 0 || events.length !== 0) {
      reasons.push('passive_wait_must_not_issue_input');
    }
    if (receipt.production_event_count !== 0 || kinds.length !== 0) {
      reasons.push('passive_wait_must_not_emit_production_events');
    }
    if (Object.hasOwn(receipt, 'input_sequence_before')
        || Object.hasOwn(receipt, 'input_sequence_after')) {
      reasons.push('passive_wait_must_not_claim_input_sequence');
    }
    return reasons;
  }
  if (verb === 'wait' && boundary !== 'keyboard_pointer') {
    reasons.push('wait_boundary_must_be_passive_or_keyboard_pointer');
  }
  if (boundary !== 'keyboard_pointer') reasons.push('active_action_boundary_must_be_keyboard_pointer');
  if (receipt.input_issued !== true) reasons.push('active_action_driver_input_missing');
  if (!Number.isInteger(receipt.input_event_count) || receipt.input_event_count < 1
      || receipt.input_event_count !== events.length) {
    reasons.push('active_action_input_event_count_invalid');
  }
  const sequenceBefore = receipt.input_sequence_before;
  const sequenceAfter = receipt.input_sequence_after;
  if (!Number.isInteger(sequenceBefore) || sequenceBefore < 0
      || !Number.isInteger(sequenceAfter) || sequenceAfter < 0) {
    reasons.push('active_action_input_sequence_bounds_invalid');
  } else if (sequenceAfter <= sequenceBefore
      || sequenceAfter - sequenceBefore !== receipt.input_event_count) {
    reasons.push('active_action_input_sequence_range_invalid');
  }
  const mechanicalIssues = validateMechanicalInputEvents(events);
  if (mechanicalIssues.length > 0) reasons.push('active_action_input_event_shape_invalid');
  let previousSequence = Number.isInteger(sequenceBefore) ? sequenceBefore : -1;
  const keyDown = new Map();
  const keyPairs = new Map();
  const keyDownModifiers = new Map();
  const pointerDown = new Map();
  const pointerPairs = new Map();
  const eventKeys = [];
  const selectionPressEvents = [];
  events.forEach((event, index) => {
    const expectedSequence = Number(sequenceBefore) + index + 1;
    if (!positiveIntegralNumber(event?.sequence) || event.sequence !== expectedSequence
        || event.sequence <= previousSequence) {
      reasons.push('active_action_input_event_sequence_invalid');
    } else previousSequence = event.sequence;
    if (event?.kind === 'key') {
      const key = String(event.key ?? '').trim();
      const modifiers = event.modifiers ?? {};
      if (!eventKeys.includes(key)) eventKeys.push(key);
      if (event.pressed === true) {
        if (keyDown.get(key) === true) reasons.push(`active_action_key_pressed_twice:${key}`);
        keyDown.set(key, true);
        keyDownModifiers.set(key, canonicalJson(modifiers));
        if (['Digit1', 'Digit2', 'Digit3'].includes(key)) {
          selectionPressEvents.push({ key, modifiers });
        }
      } else if (event.pressed === false) {
        if (keyDown.get(key) !== true) reasons.push(`active_action_key_release_without_press:${key}`);
        else {
          if (keyDownModifiers.get(key) !== canonicalJson(modifiers)) {
            reasons.push(`active_action_key_release_modifiers_mismatch:${key}`);
          }
          keyDown.set(key, false);
          keyPairs.set(key, (keyPairs.get(key) ?? 0) + 1);
        }
      }
    } else if (event?.kind === 'pointer_button') {
      const button = Number(event.button);
      if (event.pressed === true) {
        if (pointerDown.get(button) === true) {
          reasons.push(`active_action_pointer_pressed_twice:${button}`);
        }
        pointerDown.set(button, true);
      } else if (event.pressed === false) {
        if (pointerDown.get(button) !== true) {
          reasons.push(`active_action_pointer_release_without_press:${button}`);
        } else {
          pointerDown.set(button, false);
          pointerPairs.set(button, (pointerPairs.get(button) ?? 0) + 1);
        }
      }
    }
  });
  if (Number.isInteger(sequenceAfter) && previousSequence !== sequenceAfter) {
    reasons.push('active_action_input_sequence_after_mismatch');
  }
  for (const [key, down] of keyDown) {
    if (down) reasons.push(`active_action_key_left_pressed:${key}`);
  }
  for (const [button, down] of pointerDown) {
    if (down) reasons.push(`active_action_pointer_left_pressed:${button}`);
  }
  reasons.push(...verbGestureReasons(
    verb, decision, eventKeys, keyPairs, pointerPairs, selectionPressEvents, events,
    before, after,
  ));
  if (['move', 'rally', 'interact'].includes(verb)
      && receipt.input_target_token !== String(decision?.target?.token ?? '')) {
    reasons.push('world_action_input_target_binding_mismatch');
  }
  if (verb === 'wait' && (receipt.production_event_count !== 0 || kinds.length !== 0)) {
    reasons.push('active_wait_must_not_emit_production_events');
  }
  const firstPost = samples?.[0] ?? after;
  if (receipt.observation_before_capture_serial !== before?.capture_serial) {
    reasons.push('input_before_capture_binding_mismatch');
  }
  if (receipt.first_post_input_capture_serial !== firstPost?.capture_serial
      || Number(firstPost?.capture_serial ?? 0) <= Number(before?.capture_serial ?? 0)) {
    reasons.push('input_post_capture_binding_mismatch');
  }
  return [...new Set(reasons)].sort();
}

export function classifyEvidence(record) {
  const reasons = [];
  const before = isPlainObject(record?.observation_before) ? record.observation_before : {};
  const after = isPlainObject(record?.observation_after) ? record.observation_after : {};
  const samples = Array.isArray(record?.observation_samples) ? record.observation_samples : [];
  const decision = isPlainObject(record?.decision) ? record.decision : {};
  const receipt = isPlainObject(record?.input_receipt) ? record.input_receipt : {};
  const context = isPlainObject(record?.evidence_context) ? record.evidence_context : {};
  reasons.push(...validatePlayerObservation(before)
    .map((issue) => `observation_before_schema:${issue}`));
  reasons.push(...validatePlayerObservation(after)
    .map((issue) => `observation_after_schema:${issue}`));
  samples.forEach((sample, index) => {
    if (!isPlainObject(sample)) {
      reasons.push(`observation_sample_not_an_object:${index}`);
      return;
    }
    reasons.push(...validatePlayerObservation(sample)
      .map((issue) => `observation_sample_schema:${index}:${issue}`));
  });
  if (canonicalJson(samples) !== canonicalJson(normalizeObservationSamples(samples))) {
    reasons.push('observation_samples_not_deduplicated');
  }
  reasons.push(...observationSequenceReasons(before, samples, after));
  const derived = deriveDecisionArtifacts({
    observationBefore: before,
    observationAfter: after,
    observationSamples: samples,
    decision,
    inputReceipt: receipt,
  });
  if (canonicalJson(record?.feedback ?? {}) !== canonicalJson(derived.feedback)) {
    reasons.push('forged_or_stale_derived_feedback');
  }
  if (canonicalJson(record?.outcome ?? {}) !== canonicalJson(derived.outcome)) {
    reasons.push('forged_or_stale_derived_outcome');
  }
  reasons.push(...receiptInputProofReasons(decision, receipt, before, samples, after));
  if (!PLAYER_BOUNDARIES.has(receipt.boundary)) reasons.push('input_boundary_not_shipped');
  if (receipt.player_reproducible !== true) reasons.push('receipt_not_player_reproducible');
  if (!['accepted', 'refused', 'observed'].includes(receipt.status)) reasons.push('receipt_status_missing');
  if (receipt.verb !== decision.verb) reasons.push('receipt_verb_does_not_match_decision');
  if (context.authored_state !== true) reasons.push('not_from_authored_or_player_reached_state');
  if (context.fixture_quarantine === true) reasons.push('fixture_quarantine');
  if (typeof context.evidence_baseline_id !== 'string' || context.evidence_baseline_id.trim() === '') {
    reasons.push('evidence_baseline_missing');
  }
  const verb = String(decision.verb ?? '').toLowerCase();
  if (FORBIDDEN_VERBS.has(verb) || verb.startsWith('qa_')
      || verb.startsWith('debug_') || verb.startsWith('fixture_')) {
    reasons.push('forbidden_internal_or_mutating_verb');
  }
  if (verb === 'interact') {
    reasons.push(...interactionTargetResultReasons(
      before, after, samples, decision, receipt, derived.outcome,
    ));
  } else if (['move', 'rally'].includes(verb)) {
    reasons.push(...movementResultReasons(
      before, after, samples, decision, receipt, derived.feedback, derived.outcome,
    ));
  }
  if (verb === 'rally') {
    reasons.push(...fullRosterActionReasons(
      before, decision, receipt, derived.outcome, true,
    ));
  } else if (verb === 'select_party' && isPlainObject(record?.learning_candidate)
      && Object.keys(record.learning_candidate).length > 0) {
    reasons.push(...fullRosterActionReasons(
      before, decision, receipt, derived.outcome, false,
    ));
  }
  const worldChange = inferredWorldChange(verb);
  if (worldChange && receipt.status === 'observed') {
    reasons.push('world_change_has_no_accepted_or_refused_receipt');
  }
  if (worldChange) {
    if (derived.outcome.world_causal_evidence !== true) {
      reasons.push('derived_visible_world_change_missing');
    }
  } else if (!['wait', 'camera_pan', 'camera_recenter', 'camera_rotate', 'camera_zoom'].includes(verb)
      && ['accepted', 'refused'].includes(receipt.status)
      && derived.outcome.visible_change !== true) {
    reasons.push('presentation_action_visible_delta_missing');
  }
  if (verb === 'wait' && derived.outcome.passive_no_delta === true
      && isPlainObject(record?.learning_candidate)
      && Object.keys(record.learning_candidate).length > 0) {
    reasons.push('passive_wait_without_delta_cannot_support_candidate');
  }
  if (inferredGroupVerb(decision)) {
    if (receipt.atomic_group !== true) reasons.push('group_verb_was_decomposed');
    const expectedEventCount = receipt.status === 'accepted' ? 1 : 0;
    if (['accepted', 'refused'].includes(receipt.status)
        && Number(receipt.production_event_count ?? 0) !== expectedEventCount) {
      reasons.push('group_verb_production_event_count_does_not_match_receipt');
    }
    if (!sameStringMembers(receipt.intended_members, decision.intended_subjects)) {
      reasons.push('group_intended_members_do_not_match_decision');
    }
    if (!isPlainObject(receipt.member_results)) {
      reasons.push('group_member_results_missing');
    } else {
      if (Array.isArray(receipt.intended_members)
          && Object.keys(receipt.member_results).length !== receipt.intended_members.length) {
        reasons.push('group_member_result_count_does_not_match_intent');
      }
      const expectedMemberResult = receipt.status === 'accepted' ? 'accepted'
        : (receipt.status === 'refused' ? 'refused' : '');
      for (const rawSubject of decision.intended_subjects ?? []) {
        const subject = String(rawSubject);
        const memberResult = receipt.member_results[subject];
        if (!['accepted', 'refused'].includes(memberResult)) {
          reasons.push(`group_member_result_missing:${subject}`);
        } else if (expectedMemberResult && memberResult !== expectedMemberResult) {
          reasons.push(`group_member_result_not_atomic:${subject}`);
        }
      }
    }
  }
  const sorted = [...new Set(reasons)].sort();
  const playerReproducible = sorted.length === 0;
  if (['camera_pan', 'camera_recenter', 'camera_rotate', 'camera_zoom'].includes(verb)) {
    sorted.push('presentation_recovery_not_gameplay_learning_candidate');
    sorted.sort();
  }
  return {
    player_reproducible: playerReproducible,
    eligible_for_learning: sorted.length === 0,
    rejection_reasons: sorted,
  };
}

export function validateRunMetadata(run) {
  const issues = [];
  for (const key of ['run_id', 'trace_id', 'persona', 'fragment_id',
    'content_fingerprint_schema', 'content_fingerprint',
    'gameplay_build_fingerprint_schema', 'gameplay_build_fingerprint', 'execution_platform',
    'evidence_baseline_id']) {
    if (typeof run?.[key] !== 'string' || run[key].trim() === '') issues.push(`run.${key} is required`);
  }
  if (!Number.isFinite(run?.seed)) issues.push('run.seed must be numeric');
  if (!Number.isInteger(run?.repeat_index) || run.repeat_index < 0) {
    issues.push('run.repeat_index must be a non-negative integer');
  }
  if (!['native', 'web'].includes(run?.execution_platform)) {
    issues.push('run.execution_platform must be native or web');
  }
  if (!['authored_spawn', 'player_reached'].includes(run?.authored_state)) {
    issues.push('run.authored_state must be authored_spawn or player_reached');
  }
  if (run?.content_fingerprint_schema !== 'authored_fragment_resource_bytes_v1') {
    issues.push('run.content_fingerprint_schema is not a supported version');
  }
  if (!/^[a-f0-9]{64}$/.test(run?.content_fingerprint ?? '')) {
    issues.push('run.content_fingerprint must be a lowercase SHA-256 digest');
  }
  if (run?.gameplay_build_fingerprint_schema !== 'gameplay_build_resource_set_bytes_v1') {
    issues.push('run.gameplay_build_fingerprint_schema is not a supported version');
  }
  if (!/^[a-f0-9]{64}$/.test(run?.gameplay_build_fingerprint ?? '')) {
    issues.push('run.gameplay_build_fingerprint must be a lowercase SHA-256 digest');
  }
  return issues;
}

export function validateDecisionRecord(record) {
  const issues = [];
  for (const key of ['observation_before', 'observation_after', 'rationale', 'decision',
    'input_receipt', 'feedback', 'outcome', 'evidence_context']) {
    if (!isPlainObject(record?.[key])) issues.push(`${key} must be an object`);
  }
  if (!Array.isArray(record?.observation_samples)) issues.push('observation_samples must be an array');
  if (Object.hasOwn(record ?? {}, 'observation')) issues.push('legacy observation is not valid v3 evidence');
  issues.push(...validatePlayerObservation(record?.observation_before)
    .map((issue) => `observation_before:${issue}`));
  issues.push(...validatePlayerObservation(record?.observation_after)
    .map((issue) => `observation_after:${issue}`));
  for (const [index, sample] of (record?.observation_samples ?? []).entries()) {
    if (!isPlainObject(sample)) {
      issues.push(`observation_samples.${index} must be an object`);
    } else {
      issues.push(...validatePlayerObservation(sample)
        .map((issue) => `observation_samples.${index}:${issue}`));
    }
  }
  if (canonicalJson(record?.observation_samples ?? [])
      !== canonicalJson(normalizeObservationSamples(record?.observation_samples ?? []))) {
    issues.push('observation_samples must be canonical-exact de-duplicated observations');
  }
  if (typeof record?.rationale?.text !== 'string' || record.rationale.text.trim() === '') {
    issues.push('rationale.text is required');
  }
  if (typeof record?.decision?.verb !== 'string' || record.decision.verb.trim() === '') {
    issues.push('decision.verb is required');
  }
  if (!Array.isArray(record?.decision?.intended_subjects)) {
    issues.push('decision.intended_subjects must be an array');
  } else if (inferredWorldChange(String(record.decision.verb).toLowerCase())
      && record.decision.intended_subjects.length === 0) {
    issues.push('a world-changing decision needs at least one intended subject');
  }
  if (typeof record?.input_receipt?.receipt_id !== 'string'
      || record.input_receipt.receipt_id === '') issues.push('input_receipt.receipt_id is required');
  if (typeof record?.input_receipt?.verb !== 'string'
      || record.input_receipt.verb === '') issues.push('input_receipt.verb is required');
  if (!['accepted', 'refused', 'observed'].includes(record?.input_receipt?.status)) {
    issues.push('input_receipt.status must be accepted, refused, or observed');
  }
  if (typeof record?.outcome?.status !== 'string' || record.outcome.status === '') {
    issues.push('outcome.status is required');
  }
  const derived = deriveDecisionArtifacts({
    observationBefore: record?.observation_before ?? {},
    observationAfter: record?.observation_after ?? {},
    observationSamples: record?.observation_samples ?? [],
    decision: record?.decision ?? {},
    inputReceipt: record?.input_receipt ?? {},
  });
  if (canonicalJson(record?.feedback ?? {}) !== canonicalJson(derived.feedback)) {
    issues.push('feedback does not match the exact v3 derived feedback');
  }
  if (canonicalJson(record?.outcome ?? {}) !== canonicalJson(derived.outcome)) {
    issues.push('outcome does not match the exact v3 derived outcome');
  }
  return [...new Set(issues)].sort();
}

function decisionRunIdentity(run) {
  return {
    run_id: run.run_id,
    trace_id: run.trace_id,
    persona: run.persona,
    fragment_id: run.fragment_id,
    seed: run.seed,
    repeat_index: run.repeat_index,
    content_fingerprint_schema: run.content_fingerprint_schema,
    content_fingerprint: run.content_fingerprint,
    gameplay_build_fingerprint_schema: run.gameplay_build_fingerprint_schema,
    gameplay_build_fingerprint: run.gameplay_build_fingerprint,
    execution_platform: run.execution_platform,
  };
}

function productionKind(message) {
  return String(message).match(/\[EVENT[^\]]*\]\s+([a-z0-9_]+)\s+/i)?.[1] ?? '';
}

function productionPayload(message) {
  const text = String(message);
  const payloadStart = text.indexOf('{');
  if (payloadStart < 0) return {};
  try {
    const payload = JSON.parse(text.slice(payloadStart));
    return isPlainObject(payload) ? payload : {};
  } catch {
    return {};
  }
}

function expectedEventKinds(verb) {
  switch (verb) {
    case 'rally': return new Set(['rally_members']);
    case 'move': return new Set([
      'move_to_cell', 'move_cross_level', 'move_to_pos',
      'party_move_to_cell', 'party_move_to_pos',
    ]);
    case 'interact': return new Set(['trigger_interactable', 'rally_members']);
    default: return new Set();
  }
}

function actualProductionEvents(verb, consoleEvents) {
  if (consoleEvents?.[PRODUCTION_EVENT_SLICE_PROOF] !== true) {
    throw new Error('production input receipt requires an opaque browser event-ledger slice');
  }
  const expected = expectedEventKinds(verb);
  return consoleEvents.map((message) => ({
    kind: productionKind(message), message: String(message), payload: productionPayload(message),
  })).filter((event) => expected.has(event.kind));
}

class BrowserProductionEventLedger {
  #events = [];
  #ledgerIdentity = Symbol('browser-production-event-ledger');

  constructor(page) {
    page.on('console', (message) => {
      const messageText = message.text();
      if (messageText.includes('[EVENT ')) this.#events.push(messageText);
    });
  }

  mark() {
    const marker = { index: this.#events.length };
    Object.defineProperty(marker, PRODUCTION_EVENT_MARK_PROOF, { value: this.#ledgerIdentity });
    return Object.freeze(marker);
  }

  after(marker) {
    if (marker?.[PRODUCTION_EVENT_MARK_PROOF] !== this.#ledgerIdentity
        || !Number.isInteger(marker.index) || marker.index < 0 || marker.index > this.#events.length) {
      throw new Error('production event marker does not belong to this browser ledger');
    }
    const slice = this.#events.slice(marker.index);
    Object.defineProperty(slice, PRODUCTION_EVENT_SLICE_PROOF, { value: true });
    return Object.freeze(slice);
  }
}

export function captureProductionEvents(page) {
  return new BrowserProductionEventLedger(page);
}

function visibleCausalCueSignatures(observation) {
  const signatures = [];
  for (const cue of observation?.state?.cues ?? []) {
    if (cue?.visible !== true || ['party_body', 'rally'].includes(String(cue?.kind ?? ''))) {
      continue;
    }
    const signature = canonicalJson({
      kind: String(cue?.kind ?? ''),
      source_token: String(cue?.source_token ?? ''),
      phase: String(cue?.phase ?? ''),
      text: String(cue?.text ?? ''),
      label: String(cue?.label ?? ''),
      destination_label: String(cue?.destination_label ?? ''),
    });
    if (!signatures.includes(signature)) signatures.push(signature);
  }
  return signatures.sort();
}

function playerFacingExternalTraversal(message) {
  return productionKind(message) === 'begin_external_traversal'
    && /["']?scope["']?\s*:\s*(?:&)?["']player_facing["']/i.test(String(message));
}

function visibleConsequenceLineage(observations, sourceToken, expectedLabel, expectedDestination) {
  const candidates = new Map();
  const expectedLabelUpper = String(expectedLabel ?? '').trim().toUpperCase();
  const expectedDestinationUpper = String(expectedDestination ?? '').trim().toUpperCase();
  for (const observation of observations) {
    for (const cue of observation?.state?.cues ?? []) {
      if (cue?.kind !== 'consequence' || cue?.visible !== true
          || String(cue?.source_token ?? '') !== sourceToken) continue;
      const label = String(cue?.label ?? '').trim();
      const destinationLabel = String(cue?.destination_label ?? '').trim();
      const shownText = `${cue?.text ?? ''} ${label}`.toUpperCase();
      const shownDestination = `${destinationLabel} ${cue?.text ?? ''}`.toUpperCase();
      if (expectedLabelUpper && !shownText.includes(expectedLabelUpper)) continue;
      if (expectedDestinationUpper && !shownDestination.includes(expectedDestinationUpper)) continue;
      const key = canonicalJson({
        source_token: sourceToken,
        label: label.toUpperCase(),
        destination_label: destinationLabel.toUpperCase(),
      });
      const candidate = candidates.get(key) ?? {
        source_tokens: [sourceToken],
        label,
        destination_label: destinationLabel,
        active_visible: false,
        arrival_visible: false,
      };
      const phase = String(cue?.phase ?? '').toLowerCase();
      if (phase === 'active') candidate.active_visible = true;
      if (phase === 'arrival') candidate.arrival_visible = true;
      candidates.set(key, candidate);
    }
  }
  return [...candidates.values()].find((candidate) =>
    candidate.active_visible && candidate.arrival_visible)
    ?? [...candidates.values()][0]
    ?? {
      source_tokens: [sourceToken],
      label: String(expectedLabel ?? ''),
      destination_label: String(expectedDestination ?? ''),
      active_visible: false,
      arrival_visible: false,
    };
}

// EventLog is a validation oracle only. It never enters persona policy and its
// raw payload (character IDs, traversal IDs, and event IDs) never crosses into
// the trace. The persisted proof contains only event kinds plus the opaque
// portrait-token lineage a player could actually see.
export function validateBackgroundEventPresentation({
  observationBefore,
  observationAfter,
  observationSamples = [],
  consoleEvents,
  expectedRosterTokens = [],
  expectedLabel = '',
  expectedDestination = '',
}) {
  if (consoleEvents?.[PRODUCTION_EVENT_SLICE_PROOF] !== true) {
    throw new Error('background validation requires an opaque browser event-ledger slice');
  }
  const messages = [...consoleEvents].map(String);
  const eventKinds = messages.map(productionKind);
  const observations = [
    observationBefore,
    ...normalizeObservationSamples(observationSamples),
    observationAfter,
  ];
  const result = {
    ok: true,
    event_count: messages.length,
    event_kinds: eventKinds,
    causal_cue_delta_visible: true,
    player_facing_traversal_count: 0,
    subject_lineages: [],
    failures: [],
  };
  if (messages.length === 0 && expectedRosterTokens.length === 0) return result;
  if (eventKinds.some((kind) => kind === '')) {
    result.failures.push('background_event_kind_missing');
  }

  const baseline = new Set(visibleCausalCueSignatures(observationBefore));
  result.causal_cue_delta_visible = observations.slice(1).some((observation) =>
    visibleCausalCueSignatures(observation).some((signature) => !baseline.has(signature)));
  if (!result.causal_cue_delta_visible) {
    result.failures.push('background_state_change_has_no_new_rendered_causal_cue');
  }

  result.player_facing_traversal_count = messages.filter(playerFacingExternalTraversal).length;
  const rosterTokens = [...new Set(expectedRosterTokens.map((token) => String(token).trim())
    .filter(Boolean))].sort();
  if (rosterTokens.length !== expectedRosterTokens.length) {
    result.failures.push('background_expected_roster_tokens_invalid');
  }
  const visibleBefore = new Set((observationBefore?.state?.hud?.portraits ?? [])
    .filter((portrait) => portrait?.visible === true)
    .map((portrait) => String(portrait?.token ?? ''))
    .filter(Boolean));
  for (const sourceToken of rosterTokens) {
    if (!visibleBefore.has(sourceToken)) {
      result.failures.push('background_expected_roster_token_not_visible_before');
    }
    const lineage = visibleConsequenceLineage(
      observations, sourceToken, expectedLabel, expectedDestination,
    );
    result.subject_lineages.push(lineage);
    if (!lineage.active_visible) {
      result.failures.push('background_traversal_active_cue_missing');
    }
    if (!lineage.arrival_visible) {
      result.failures.push('background_traversal_arrival_cue_missing');
    }
  }
  if (rosterTokens.length > 0
      && result.player_facing_traversal_count < rosterTokens.length) {
    result.failures.push('background_player_facing_traversal_receipt_missing');
  }
  result.failures = [...new Set(result.failures)].sort();
  result.ok = result.failures.length === 0;
  return result;
}

function backgroundValidationReceiptFields(backgroundValidation) {
  if (!isPlainObject(backgroundValidation)
      || typeof backgroundValidation.ok !== 'boolean'
      || !Number.isInteger(backgroundValidation.event_count)
      || backgroundValidation.event_count < 0
      || !Array.isArray(backgroundValidation.event_kinds)
      || backgroundValidation.event_kinds.length !== backgroundValidation.event_count
      || !Array.isArray(backgroundValidation.subject_lineages)
      || !Array.isArray(backgroundValidation.failures)) {
    throw new Error('background validation receipt is malformed');
  }
  if (backgroundValidation.ok !== true || backgroundValidation.failures.length !== 0) {
    throw new Error('failed background presentation validation cannot enter a trace receipt');
  }
  const safe = jsonSafe(backgroundValidation);
  const forbiddenKeys = new Set([
    'id', 'character_id', 'subject_id', 'event_id', 'traversal_id', 'message', 'payload',
  ]);
  const pending = [safe];
  while (pending.length > 0) {
    const value = pending.pop();
    if (Array.isArray(value)) {
      pending.push(...value);
    } else if (isPlainObject(value)) {
      for (const [key, child] of Object.entries(value)) {
        if (forbiddenKeys.has(key)) {
          throw new Error(`background validation cannot persist raw ${key}`);
        }
        pending.push(child);
      }
    }
  }
  return {
    validation_background_event_count: safe.event_count,
    validation_background_event_kinds: safe.event_kinds,
    validation_background_visual_lineage: safe,
  };
}

function emptyModifiers() {
  return { ctrl: false, shift: false, alt: false, meta: false };
}

function browserKeyCode(key) {
  const text = String(key ?? '').trim();
  if (/^(?:Digit[0-9]|Key[A-Z]|Home|Space)$/.test(text)) return text;
  if (/^[0-9]$/.test(text)) return `Digit${text}`;
  if (/^[a-z]$/i.test(text)) return `Key${text.toUpperCase()}`;
  if (/^home$/i.test(text)) return 'Home';
  if (/^space$/i.test(text)) return 'Space';
  throw new Error(`unsupported shipped browser key for input receipt: ${text}`);
}

function parsedBrowserKey(key) {
  const parts = String(key ?? '').split('+').map((part) => part.trim()).filter(Boolean);
  const base = parts.pop() ?? '';
  const modifiers = emptyModifiers();
  for (const modifier of parts) {
    switch (modifier.toLowerCase()) {
      case 'control':
      case 'ctrl': modifiers.ctrl = true; break;
      case 'shift': modifiers.shift = true; break;
      case 'alt': modifiers.alt = true; break;
      case 'meta': modifiers.meta = true; break;
      default: throw new Error(`unsupported browser key modifier for input receipt: ${modifier}`);
    }
  }
  return { code: browserKeyCode(base), modifiers };
}

function pointerButtonIndex(button) {
  const normalized = String(button ?? '').toLowerCase();
  if (normalized === 'left' || normalized === '1') return 1;
  if (normalized === 'right' || normalized === '2') return 2;
  if (normalized === 'middle' || normalized === '3') return 3;
  throw new Error(`unsupported browser pointer button for input receipt: ${button}`);
}

function deepFreezeJson(value) {
  const safe = jsonSafe(value);
  const freeze = (item) => {
    if (Array.isArray(item)) item.forEach(freeze);
    else if (isPlainObject(item)) Object.values(item).forEach(freeze);
    return Object.freeze(item);
  };
  return freeze(safe);
}

function observationChoiceRecords(observation) {
  return [
    ...(observation?.state?.affordances ?? []),
    ...(observation?.state?.cues ?? []),
    ...(observation?.state?.hud?.portraits ?? []),
  ];
}

function exactObservationChoice(observation, choice) {
  const encoded = canonicalJson(choice);
  return observationChoiceRecords(observation)
    .some((candidate) => canonicalJson(candidate) === encoded);
}

function requireCapabilityState(capability, context) {
  const state = OBSERVATION_ACTION_CAPABILITY_PROOF.get(capability);
  if (!state) {
    throw new TypeError(`${context} requires an observation-derived action capability`);
  }
  return state;
}

export function authorizeObservationPlayerAction(inputLedger, observation, request) {
  if (!(inputLedger instanceof BrowserPlayerInputLedger)) {
    throw new TypeError('action authorization requires the browser player-input ledger');
  }
  return inputLedger.authorizeObservationAction(observation, request);
}

export function assertObservationActionCapability(
  capability, { choice = null, gesture = '', targetToken = '' } = {}, context = 'player input',
) {
  const state = requireCapabilityState(capability, context);
  if (choice !== null && canonicalJson(choice) !== state.choiceHashes[0]) {
    throw new TypeError(`${context} cannot substitute a different observation choice`);
  }
  if (gesture && gesture !== state.gesture) {
    throw new TypeError(`${context} cannot substitute a different human input gesture`);
  }
  if (targetToken && targetToken !== state.targetToken) {
    throw new TypeError(`${context} cannot substitute a different visible target token`);
  }
  return capability;
}

export function postChoiceAssertionOracle(capability) {
  const state = requireCapabilityState(capability, 'post-choice assertion oracle');
  const oracle = Object.freeze({
    schema: 'post_choice_assertion_oracle_v1',
    observation_capture_serial: state.observationCaptureSerial,
  });
  POST_CHOICE_ASSERTION_ORACLE_PROOF.set(oracle, state);
  return oracle;
}

export function assertPostChoiceAssertionOracle(oracle, context = 'private bridge assertion') {
  if (!POST_CHOICE_ASSERTION_ORACLE_PROOF.has(oracle)) {
    throw new TypeError(`${context} requires a post-choice assertion oracle`);
  }
  return oracle;
}

class BrowserPlayerInputLedger {
  #authorizedObservations = new Set();
  #events = [];
  #ledgerIdentity = Symbol('browser-player-input-ledger');
  #page;

  constructor(page) {
    if (!page?.keyboard || !page?.mouse) {
      throw new Error('player input ledger requires a Playwright page');
    }
    this.#page = page;
  }

  authorizeObservationAction(observation, request = {}) {
    const observationIssues = validatePlayerObservation(observation);
    if (observationIssues.length > 0) {
      throw new TypeError(
        `action authorization requires validated player_observation_v1: ${observationIssues.join('; ')}`,
      );
    }
    const gesture = String(request.gesture ?? '').trim();
    if (!['key_press', 'key_sequence', 'key_hold', 'pointer_click', 'pointer_hold', 'passive_wait']
      .includes(gesture)) {
      throw new TypeError(`unsupported observation-authorized input gesture: ${gesture}`);
    }
    const choices = Array.isArray(request.choices)
      ? request.choices : (request.choice ? [request.choice] : []);
    if ((gesture !== 'passive_wait' && choices.length === 0)
        || choices.some((choice) => !exactObservationChoice(observation, choice))) {
      throw new TypeError(
        'action authorization requires exact visible records from the validated observation',
      );
    }
    const observationIdentity = `${observation.capture_serial}:${canonicalHash(observation)}`;
    if (this.#authorizedObservations.has(observationIdentity)) {
      throw new TypeError(
        'one player observation may authorize only one fixed persona action choice',
      );
    }
    const targetToken = String(request.targetToken ?? choices[0]?.token ?? '').trim();
    if (!targetToken) {
      throw new TypeError('action authorization requires a visible target token');
    }
    const keys = Array.isArray(request.keys)
      ? request.keys.map((key) => String(key))
      : (request.key ? [String(request.key)] : []);
    if (['key_press', 'key_sequence', 'key_hold'].includes(gesture) && keys.length === 0) {
      throw new TypeError(`${gesture} authorization requires its exact shipped key sequence`);
    }
    if (gesture !== 'key_sequence' && keys.length > 1) {
      throw new TypeError(`${gesture} authorization accepts exactly one shipped key`);
    }
    keys.forEach((key) => parsedBrowserKey(key));
    const button = ['pointer_click', 'pointer_hold'].includes(gesture)
      ? String(request.button ?? 'right').toLowerCase() : '';
    if (button) pointerButtonIndex(button);
    const safeChoices = deepFreezeJson(choices);
    const capability = Object.freeze({
      schema: 'observation_action_capability_v1',
      gesture,
      target_token: targetToken,
      observation_capture_serial: observation.capture_serial,
      choice: safeChoices[0] ?? null,
      choices: safeChoices,
      viewport_size: deepFreezeJson(observation.state.viewport.size),
    });
    OBSERVATION_ACTION_CAPABILITY_PROOF.set(capability, {
      ledgerIdentity: this.#ledgerIdentity,
      gesture,
      targetToken,
      keys,
      keyIndex: 0,
      button,
      phase: 'authorized',
      observationCaptureSerial: observation.capture_serial,
      choiceHashes: safeChoices.map((choice) => canonicalJson(choice)),
    });
    this.#authorizedObservations.add(observationIdentity);
    return capability;
  }

  mark() {
    const marker = { index: this.#events.length };
    Object.defineProperty(marker, PLAYER_INPUT_LEDGER_MARK_PROOF, {
      value: this.#ledgerIdentity,
    });
    return Object.freeze(marker);
  }

  after(marker) {
    if (marker?.[PLAYER_INPUT_LEDGER_MARK_PROOF] !== this.#ledgerIdentity
        || !Number.isInteger(marker.index) || marker.index < 0
        || marker.index > this.#events.length) {
      throw new Error('player input marker does not belong to this browser ledger');
    }
    const slice = this.#events.slice(marker.index).map((event) => Object.freeze({ ...event }));
    Object.defineProperty(slice, PLAYER_INPUT_LEDGER_SLICE_PROOF, {
      value: this.#ledgerIdentity,
    });
    Object.defineProperty(slice, PLAYER_INPUT_SEQUENCE_BEFORE_PROOF, {
      value: marker.index,
    });
    Object.defineProperty(slice, PLAYER_INPUT_SEQUENCE_AFTER_PROOF, {
      value: this.#events.length,
    });
    return Object.freeze(slice);
  }

  async press(key, targetToken = '', capability = null) {
    const state = this.#requireInputCapability(capability, targetToken, 'key press');
    if (!['key_press', 'key_sequence'].includes(state.gesture)
        || state.phase !== 'authorized' || state.keys[state.keyIndex] !== key) {
      throw new TypeError('key press does not match the observation-authorized action');
    }
    const parsed = parsedBrowserKey(key);
    await this.#page.keyboard.press(key);
    const { code, modifiers } = parsed;
    this.#append('key', { key: code, pressed: true, modifiers });
    this.#append('key', { key: code, pressed: false, modifiers });
    state.keyIndex += 1;
    if (state.keyIndex === state.keys.length) state.phase = 'complete';
  }

  async keyDown(key, targetToken = '', capability = null) {
    const state = this.#requireInputCapability(capability, targetToken, 'held key press');
    if (state.gesture !== 'key_hold' || state.phase !== 'authorized' || state.keys[0] !== key) {
      throw new TypeError('held key press does not match the observation-authorized action');
    }
    const parsed = parsedBrowserKey(key);
    await this.#page.keyboard.down(key);
    this.#append('key', {
      key: parsed.code, pressed: true, modifiers: parsed.modifiers,
    });
    state.phase = 'held';
  }

  async keyUp(key, targetToken = '', capability = null) {
    const state = this.#requireInputCapability(capability, targetToken, 'held key release');
    if (state.gesture !== 'key_hold' || state.phase !== 'held' || state.keys[0] !== key) {
      throw new TypeError('held key release does not match the observation-authorized action');
    }
    const parsed = parsedBrowserKey(key);
    await this.#page.keyboard.up(key);
    this.#append('key', {
      key: parsed.code, pressed: false, modifiers: parsed.modifiers,
    });
    state.phase = 'complete';
  }

  async pointerMove(x, y, targetToken = '', capability = null) {
    const state = this.#requireInputCapability(capability, targetToken, 'pointer move');
    if (state.gesture !== 'pointer_hold' || state.phase !== 'authorized') {
      throw new TypeError('pointer move does not match the observation-authorized held gesture');
    }
    await this.#page.mouse.move(x, y);
    this.#append('pointer_move', {});
    state.phase = 'positioned';
  }

  async pointerDown(button = 'right', targetToken = '', capability = null) {
    const state = this.#requireInputCapability(capability, targetToken, 'pointer press');
    if (state.gesture !== 'pointer_hold'
        || !['authorized', 'positioned'].includes(state.phase) || state.button !== button) {
      throw new TypeError('pointer press does not match the observation-authorized held gesture');
    }
    await this.#page.mouse.down({ button });
    this.#append('pointer_button', { button: pointerButtonIndex(button), pressed: true });
    state.phase = 'held';
  }

  async pointerUp(button = 'right', targetToken = '', capability = null) {
    const state = this.#requireInputCapability(capability, targetToken, 'pointer release');
    if (state.gesture !== 'pointer_hold' || state.phase !== 'held' || state.button !== button) {
      throw new TypeError('pointer release does not match the observation-authorized held gesture');
    }
    await this.#page.mouse.up({ button });
    this.#append('pointer_button', { button: pointerButtonIndex(button), pressed: false });
    state.phase = 'complete';
  }

  async pointerClick(x, y, button = 'right', targetToken = '', capability = null) {
    const state = this.#requireInputCapability(capability, targetToken, 'pointer click');
    if (state.gesture !== 'pointer_click' || state.phase !== 'authorized'
        || state.button !== button) {
      throw new TypeError('pointer click does not match the observation-authorized action');
    }
    await this.#page.mouse.click(x, y, { button });
    const buttonIndex = pointerButtonIndex(button);
    this.#append('pointer_button', { button: buttonIndex, pressed: true });
    this.#append('pointer_button', { button: buttonIndex, pressed: false });
    state.phase = 'complete';
  }

  #requireInputCapability(capability, targetToken, context) {
    const state = requireCapabilityState(capability, context);
    if (state.ledgerIdentity !== this.#ledgerIdentity) {
      throw new TypeError(`${context} capability belongs to a different input ledger`);
    }
    if (String(targetToken ?? '') !== state.targetToken) {
      throw new TypeError(`${context} cannot substitute a different visible target token`);
    }
    return state;
  }

  #append(kind, detail) {
    this.#events.push(Object.freeze({
      sequence: this.#events.length + 1,
      kind,
      ...jsonSafe(detail),
      issued: true,
    }));
  }
}

export function capturePlayerInput(page) {
  return new BrowserPlayerInputLedger(page);
}

export function normalizeVisibleSubjectId(label) {
  return String(label ?? '').trim()
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
    .replace(/[^A-Za-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .toLowerCase();
}

export function visibleSubjectIds(observation) {
  return (observation?.state?.hud?.portraits ?? [])
    .filter((portrait) => portrait?.visible === true)
    .map((portrait) => normalizeVisibleSubjectId(portrait.label))
    .filter(Boolean)
    .sort();
}

export function observedAffordance(observation, token) {
  return (observation?.state?.affordances ?? [])
    .find((candidate) => candidate.token === token) ?? null;
}

export function chooseAffordanceFromBins(observation, bins, kind = 'move') {
  for (const bin of bins) {
    for (const token of observation?.state?.viewport_bins?.[bin] ?? []) {
      const candidate = observedAffordance(observation, token);
      if (candidate?.kind === kind) return jsonSafe(candidate);
    }
  }
  return null;
}

export function chooseVisibleInteraction(observation, visibleTextPattern = null) {
  const affordances = observation?.state?.affordances ?? [];
  for (const token of observation?.state?.viewport_bins?.interact_visible ?? []) {
    const candidate = affordances.find((entry) => entry.token === token);
    if (!candidate || candidate.kind !== 'interact') continue;
    const visibleText = `${candidate.verb} ${candidate.consequence}`;
    if (visibleTextPattern === null || visibleTextPattern.test(visibleText)) return jsonSafe(candidate);
  }
  return null;
}

function deriveEazyGoal(decisions) {
  for (const record of decisions) {
    if (record.decision?.verb !== 'interact') continue;
    const token = String(record.decision?.target?.token ?? '');
    const affordance = observedAffordance(record.observation_before, token);
    const visibleVerb = String(affordance?.verb ?? '');
    if (!token || !/REST|SHELTER/i.test(visibleVerb)) continue;
    const outcome = record.outcome ?? {};
    const result = outcome.interaction_result ?? {};
    if (outcome.accepted !== true || result.source_token !== token
        || result.result !== 'success' || result.visible !== true
        || !positiveIntegralNumber(result.presentation_serial)) continue;
    for (const observation of postObservations(
      record.observation_samples ?? [], record.observation_after,
    )) {
      for (const cue of observation?.state?.cues ?? []) {
        if (!isPlainObject(cue) || cue.visible !== true
            || !/SECURED THE SHELTER|FULL PARTY SETTLED/i.test(cueSearchText(cue))) continue;
        return {
          reached: true,
          evidence: {
            kind: 'eazy_basin_rest_and_full_party_settled_v1',
            decision_index: Number(record.decision_index ?? -1),
            source_token: token,
            presentation_serial: result.presentation_serial,
            visible_verb: visibleVerb,
            settled_cue: jsonSafe(cue),
          },
        };
      }
    }
  }
  return {
    reached: false,
    evidence: {
      kind: 'eazy_basin_goal_unproven_v1',
      required: 'exact REST/SHELTER success and same-action visible full-party secured/settled cue',
    },
  };
}

function cueSearchText(cue) {
  return ['text', 'state', 'result', 'label', 'destination_label']
    .map((key) => String(cue?.[key] ?? '').trim()).filter(Boolean)
    .map((part) => part.toUpperCase()).join(' ');
}

function visiblePartyTokenSet(observation) {
  const tokens = new Set((observation?.state?.hud?.portraits ?? [])
    .filter((portrait) => portrait?.visible === true)
    .map((portrait) => String(portrait?.token ?? '')).filter(Boolean));
  for (const cue of observation?.state?.cues ?? []) {
    if (!isPlainObject(cue) || cue.kind !== 'party_body' || cue.visible !== true) continue;
    for (const key of ['source_token', 'binding']) {
      const token = String(cue[key] ?? '');
      if (token) tokens.add(token);
    }
  }
  return tokens;
}

function visibleRosterTokensForGoal(observation) {
  const roster = [];
  const portraits = new Set();
  for (const portrait of observation?.state?.hud?.portraits ?? []) {
    if (!isPlainObject(portrait) || portrait.visible !== true) continue;
    const token = String(portrait.token ?? '');
    if (token && !roster.includes(token)) {
      portraits.add(token);
      roster.push(token);
    }
  }
  for (const cue of observation?.state?.cues ?? []) {
    if (!isPlainObject(cue) || cue.kind !== 'party_body' || cue.visible !== true) continue;
    const bodyToken = String(cue.source_token ?? '');
    const binding = String(cue.binding ?? '');
    if (bodyToken && (!binding || !portraits.has(binding)) && !roster.includes(bodyToken)) {
      roster.push(bodyToken);
    }
  }
  return roster.sort();
}

function deriveDeanGoal(decisions) {
  const lineages = new Map();
  const warnings = [];
  let observationIndex = 0;
  for (const record of decisions) {
    const observations = [
      record.observation_before,
      ...(record.observation_samples ?? []),
      record.observation_after,
    ];
    for (const observation of observations) {
      const partyTokens = visiblePartyTokenSet(observation);
      for (const cue of observation?.state?.cues ?? []) {
        if (!isPlainObject(cue)) continue;
        const warningText = cueSearchText(cue);
        if (cue.visible === true && ['hud', 'consequence'].includes(cue.kind)
            && (warningText.includes('BASIN RISING') || warningText.includes('MISSED RISE'))) {
          const roster = visibleRosterTokensForGoal(observation);
          if (roster.length > 0) {
            warnings.push({ observation_index: observationIndex, cue: jsonSafe(cue), roster });
          }
        }
        const sourceToken = String(cue.source_token ?? '');
        const phase = String(cue.phase ?? '').toLowerCase();
        const label = String(cue.label ?? cue.text ?? '').trim();
        const destinationLabel = String(cue.destination_label ?? '').trim();
        if (cue.kind !== 'consequence' || cue.visible !== true || !sourceToken
            || !partyTokens.has(sourceToken) || !label.toUpperCase().includes('SWEPT')
            || !destinationLabel || !['active', 'arrival'].includes(phase)) continue;
        const key = `${sourceToken}|${label.toUpperCase()}|${destinationLabel.toUpperCase()}`;
        const lineage = lineages.get(key) ?? {
          source_token: sourceToken,
          label,
          destination_label: destinationLabel,
          phase_indices: {},
        };
        if (!Object.hasOwn(lineage.phase_indices, phase)) {
          lineage.phase_indices[phase] = observationIndex;
        }
        lineages.set(key, lineage);
      }
      observationIndex += 1;
    }
  }
  const suffixes = [...new Set([...lineages.values()].map((lineage) =>
    `${lineage.label.toUpperCase()}|${lineage.destination_label.toUpperCase()}`))].sort();
  for (const warning of warnings) {
    for (const suffix of suffixes) {
      const perToken = [];
      let fullRosterProven = warning.roster.length > 0;
      for (const token of warning.roster) {
        const lineage = lineages.get(`${token}|${suffix}`);
        if (!lineage) {
          fullRosterProven = false;
          break;
        }
        const activeIndex = Number(lineage.phase_indices.active ?? -1);
        const arrivalIndex = Number(lineage.phase_indices.arrival ?? -1);
        if (activeIndex <= warning.observation_index || arrivalIndex <= activeIndex) {
          fullRosterProven = false;
          break;
        }
        perToken.push({
          source_token: token,
          active_observation_index: activeIndex,
          arrival_observation_index: arrivalIndex,
        });
      }
      if (!fullRosterProven) continue;
      const separator = suffix.indexOf('|');
      return {
        reached: true,
        evidence: {
          kind: 'dean_basin_full_roster_warning_swept_active_arrival_v1',
          warning_observation_index: warning.observation_index,
          warning_cue: jsonSafe(warning.cue),
          roster: [...warning.roster],
          label: separator >= 0 ? suffix.slice(0, separator) : suffix,
          destination_label: separator >= 0 ? suffix.slice(separator + 1) : '',
          per_token_phases: perToken,
        },
      };
    }
  }
  return {
    reached: false,
    evidence: {
      kind: 'dean_basin_goal_unproven_v1',
      required: 'visible Basin-rise warning followed by same-lineage SWEPT active and arrival for the full warning roster',
    },
  };
}

export function deriveBasinPersonaGoal(run, decisions) {
  if (run?.fragment_id !== 'basin_fill_proof') {
    return {
      reached: false,
      evidence: { kind: 'unsupported_fragment', fragment_id: String(run?.fragment_id ?? '') },
    };
  }
  if (run.persona === 'eazy_speezy') return deriveEazyGoal(decisions);
  if (run.persona === 'dean_takahashi') return deriveDeanGoal(decisions);
  return {
    reached: false,
    evidence: { kind: 'unsupported_persona', persona: String(run?.persona ?? '') },
  };
}

export function validateMechanicalInputEvents(inputEvents) {
  const issues = [];
  if (!Array.isArray(inputEvents)) return ['input_events_not_array'];
  let previousSequence = 0;
  if (inputEvents.length === 0) issues.push('input_events_empty');
  inputEvents.forEach((event, index) => {
    const prefix = `input_events.${index}`;
    if (!isPlainObject(event) || event.issued !== true || !Number.isInteger(event.sequence)
        || event.sequence <= previousSequence) {
      issues.push(`${prefix}.sequence_or_issued_invalid`);
      return;
    }
    previousSequence = event.sequence;
    if (event.kind === 'key') {
      unknownKeys(event, new Set([
        'sequence', 'kind', 'issued', 'key', 'pressed', 'modifiers',
      ]), prefix, issues);
      if (!/^(?:Digit[0-9]|Key[A-Z]|Home|Space)$/.test(event.key ?? '')) {
        issues.push(`${prefix}.key_invalid`);
      }
      if (typeof event.pressed !== 'boolean') issues.push(`${prefix}.pressed_invalid`);
      if (!isPlainObject(event.modifiers)) {
        issues.push(`${prefix}.modifiers_invalid`);
      } else {
        unknownKeys(event.modifiers, new Set(['ctrl', 'shift', 'alt', 'meta']),
          `${prefix}.modifiers`, issues);
        for (const modifier of ['ctrl', 'shift', 'alt', 'meta']) {
          if (typeof event.modifiers[modifier] !== 'boolean') {
            issues.push(`${prefix}.modifiers.${modifier}_invalid`);
          }
        }
      }
      return;
    }
    if (event.kind === 'pointer_move') {
      unknownKeys(event, new Set(['sequence', 'kind', 'issued']), prefix, issues);
      return;
    }
    if (event.kind === 'pointer_button') {
      unknownKeys(event, new Set([
        'sequence', 'kind', 'issued', 'button', 'pressed',
      ]), prefix, issues);
      if (!Number.isInteger(event.button) || event.button < 1 || event.button > 5) {
        issues.push(`${prefix}.button_invalid`);
      }
      if (typeof event.pressed !== 'boolean') issues.push(`${prefix}.pressed_invalid`);
      return;
    }
    issues.push(`${prefix}.kind_invalid`);
  });
  return [...new Set(issues)].sort();
}

function mechanicallyIssuedInputEvents(inputEvents) {
  if (!Array.isArray(inputEvents) || !inputEvents[PLAYER_INPUT_LEDGER_SLICE_PROOF]) {
    throw new Error('input receipt requires an opaque BrowserPlayerInputLedger slice');
  }
  const issues = validateMechanicalInputEvents(inputEvents);
  if (issues.length > 0) throw new Error(
    `input receipt requires mechanically issued browser events: ${issues.join('; ')}`,
  );
  const inputSequenceBefore = inputEvents[PLAYER_INPUT_SEQUENCE_BEFORE_PROOF];
  const inputSequenceAfter = inputEvents[PLAYER_INPUT_SEQUENCE_AFTER_PROOF];
  if (!Number.isInteger(inputSequenceBefore) || inputSequenceBefore < 0
      || !Number.isInteger(inputSequenceAfter) || inputSequenceAfter < inputSequenceBefore
      || inputEvents[0]?.sequence !== inputSequenceBefore + 1
      || inputEvents.at(-1)?.sequence !== inputSequenceAfter
      || inputEvents.some((event, index) => event.sequence !== inputSequenceBefore + index + 1)) {
    throw new Error('input receipt mechanical event slice does not bind one exact sequence range');
  }
  return {
    events: jsonSafe(inputEvents),
    inputSequenceBefore,
    inputSequenceAfter,
  };
}

export class PersonaDecisionTrace {
  constructor({
    persona, fragmentId, contentFingerprintSchema, contentFingerprint,
    gameplayBuildFingerprintSchema, gameplayBuildFingerprint,
    seed = 0, runIndex = 0,
  }) {
    if (!Number.isInteger(runIndex) || runIndex < 0) throw new Error('runIndex must be non-negative');
    if (!Number.isInteger(seed)) throw new Error('seed must be an integer');
    const runId = `${fragmentId}:${persona}:web_${runIndex}_${seed}`;
    this.artifactFileName = `${persona}__${fragmentId}__web_${runIndex}_${seed}.jsonl`;
    this.run = jsonSafe({
      run_id: runId, trace_id: runId, persona, fragment_id: fragmentId, seed,
      repeat_index: runIndex,
      content_fingerprint_schema: contentFingerprintSchema,
      content_fingerprint: contentFingerprint,
      gameplay_build_fingerprint_schema: gameplayBuildFingerprintSchema,
      gameplay_build_fingerprint: gameplayBuildFingerprint,
      execution_platform: 'web', authored_state: 'authored_spawn',
      evidence_baseline_id: `${runId}:authored_input_baseline`,
    });
    const issues = validateRunMetadata(this.run);
    if (issues.length > 0) throw new Error(`invalid run metadata: ${issues.join('; ')}`);
    this.records = [];
    this.previousHash = '';
    this.nextDecisionIndex = 0;
    this.finished = false;
    this.appendHashed({ schema: TRACE_SCHEMA, record_type: 'run', run: this.run });
  }

  keyboardPointerReceipt({
    verb, consoleEvents = [], inputEvents, intendedMembers = [], input, targetToken = '',
  }) {
    const mechanical = mechanicallyIssuedInputEvents(inputEvents);
    const events = actualProductionEvents(verb, consoleEvents);
    const groupProduction = verb === 'rally'
      || (inferredWorldChange(String(verb ?? '').toLowerCase()) && intendedMembers.length > 1)
      || events.some((event) => event.kind === 'rally_members');
    const rallyEvents = events.filter((event) => event.kind === 'rally_members');
    const productionMembers = rallyEvents.length === 1 && Array.isArray(rallyEvents[0].payload.members)
      ? rallyEvents[0].payload.members.map(String) : [];
    const exactRoster = rallyEvents.length === 1
      && sameStringMembers(productionMembers, intendedMembers);
    const receipt = {
      receipt_id: `${this.run.run_id}:input:${this.nextDecisionIndex}`,
      boundary: 'keyboard_pointer', verb,
      status: events.length > 0 ? 'accepted' : 'refused',
      player_reproducible: true,
      atomic_group: !groupProduction || events.length === 0
        || (events.length === 1 && exactRoster),
      production_event_count: events.length,
      production_event_kinds: events.map((event) => event.kind),
      input_issued: true,
      input_event_count: mechanical.events.length,
      input_events: mechanical.events,
      input_sequence_before: mechanical.inputSequenceBefore,
      input_sequence_after: mechanical.inputSequenceAfter,
      input_target_token: String(targetToken),
      input,
    };
    if (groupProduction) {
      receipt.intended_members = [...intendedMembers];
      receipt.member_results = Object.fromEntries(intendedMembers.map((member) => [
        member, productionMembers.includes(String(member)) ? 'accepted' : 'refused',
      ]));
    }
    Object.defineProperty(receipt, INPUT_RECEIPT_PROOF, { value: true });
    return receipt;
  }

  observedInputReceipt({
    verb, input, boundary = 'player_command', inputEvents = null,
    intendedMembers = null, memberResults = null, backgroundValidation = null,
  }) {
    const normalizedVerb = String(verb ?? '').toLowerCase();
    let mechanical = null;
    if (boundary === 'player_command') {
      if (normalizedVerb !== 'wait') {
        throw new Error('player_command receipts are restricted to passive wait decisions');
      }
      if (inputEvents != null) {
        throw new Error('passive no-input waits cannot bind browser input events');
      }
    } else {
      if (boundary !== 'keyboard_pointer') {
        throw new Error('active Web receipts require the keyboard_pointer boundary');
      }
      mechanical = mechanicallyIssuedInputEvents(inputEvents);
    }
    const receipt = {
      receipt_id: `${this.run.run_id}:input:${this.nextDecisionIndex}`,
      boundary, verb, status: 'observed', player_reproducible: true,
      atomic_group: false, production_event_count: 0, production_event_kinds: [],
      input_issued: mechanical !== null,
      input_event_count: mechanical?.events.length ?? 0,
      input_events: mechanical?.events ?? [],
      input,
    };
    if (mechanical !== null) {
      receipt.input_sequence_before = mechanical.inputSequenceBefore;
      receipt.input_sequence_after = mechanical.inputSequenceAfter;
    }
    if (intendedMembers !== null || memberResults !== null) {
      if (!Array.isArray(intendedMembers) || !isPlainObject(memberResults)) {
        throw new Error('roster-bound presentation receipts require members and member results');
      }
      receipt.intended_members = intendedMembers.map(String);
      receipt.member_results = jsonSafe(memberResults);
    }
    if (backgroundValidation !== null) {
      Object.assign(receipt, backgroundValidationReceiptFields(backgroundValidation));
    }
    Object.defineProperty(receipt, INPUT_RECEIPT_PROOF, { value: true });
    return receipt;
  }

  record(entry) {
    if (this.finished) throw new Error('cannot append a decision after the summary');
    for (const forbidden of ['feedback', 'outcome', 'evidence']) {
      if (Object.hasOwn(entry, forbidden)) {
        throw new Error(`${forbidden} is derived internally and cannot be supplied by the caller`);
      }
    }
    if (entry.inputReceipt?.[INPUT_RECEIPT_PROOF] !== true) {
      throw new Error('input receipt was not derived from the shipped browser boundary');
    }
    const samples = normalizeObservationSamples(entry.observationSamples ?? []);
    const decision = jsonSafe(entry.decision ?? {});
    const verb = String(decision.verb ?? '').toLowerCase();
    const worldChange = inferredWorldChange(verb);
    decision.world_change = worldChange === null ? true : worldChange;
    decision.group_verb = inferredGroupVerb(decision);
    const receipt = jsonSafe(entry.inputReceipt);
    const posts = postObservations(samples, entry.observationAfter);
    receipt.observation_before_capture_serial = Number(
      entry.observationBefore?.capture_serial ?? -1,
    );
    receipt.first_post_input_capture_serial = Number(posts[0]?.capture_serial ?? -1);
    const derived = deriveDecisionArtifacts({
      observationBefore: entry.observationBefore,
      observationAfter: entry.observationAfter,
      observationSamples: samples,
      decision,
      inputReceipt: receipt,
    });
    const record = {
      schema: TRACE_SCHEMA, record_type: 'decision', run: decisionRunIdentity(this.run),
      decision_index: this.nextDecisionIndex,
      observation_before: jsonSafe(entry.observationBefore),
      observation_after: jsonSafe(entry.observationAfter),
      observation_samples: samples,
      rationale: jsonSafe(entry.rationale), decision, input_receipt: receipt,
      feedback: derived.feedback, outcome: derived.outcome,
      evidence_context: {
        authored_state: true, fixture_quarantine: false,
        evidence_baseline_id: this.run.evidence_baseline_id,
      },
    };
    // Keep every human-equivalent attempt in the trace, but do not let an
    // accepted route that was visibly stopped short reserve or seed a policy
    // node. A later retry may contribute the candidate only after exact arrival.
    const movementCandidate = ['move', 'rally'].includes(verb);
    if (entry.learningCandidate != null
        && (!movementCandidate
          || movementCandidateDemonstrated(derived.outcome, entry.observationAfter, {
            persona: this.run.persona, inputReceipt: receipt,
          }))) {
      record.learning_candidate = jsonSafe(entry.learningCandidate);
    }
    record.evidence = classifyEvidence(record);
    const previousDecisions = this.records.filter((candidate) =>
      candidate.record_type === 'decision');
    const issues = [
      ...validateDecisionRecord(record),
      ...inputSequenceProgressionReasons(previousDecisions, record),
      ...observationProgressionReasons(previousDecisions, record),
    ];
    if (issues.length > 0) throw new Error(`invalid decision record: ${issues.join('; ')}`);
    this.appendHashed(record);
    this.nextDecisionIndex += 1;
    return record;
  }

  finish(metadata = {}) {
    if (this.finished) return;
    const decisions = this.records.filter((record) => record.record_type === 'decision');
    const ineligible = decisions.filter((record) => record.evidence?.eligible_for_learning !== true)
      .map((record) => record.decision_index);
    const goal = deriveBasinPersonaGoal(this.run, decisions);
    const requestedComplete = metadata?.trace_complete === true;
    const summary = jsonSafe({
      ...Object.fromEntries(Object.entries(metadata).filter(([key]) => ![
        'persona_goal_reached', 'goal_evidence', 'evidence_failures',
        'ineligible_decision_indices', 'complete',
      ].includes(key))),
      status: goal.reached ? (this.run.persona === 'eazy_speezy'
        ? 'complete' : 'persona_invariant_observed') : 'persona_goal_not_reached',
      trace_complete: requestedComplete && ineligible.length === 0 && goal.reached,
      persona_goal_reached: goal.reached,
      goal_evidence: goal.evidence,
      evidence_failures: ineligible.length,
      ineligible_decision_indices: ineligible,
      complete: this.run.persona === 'eazy_speezy' && goal.reached,
    });
    this.appendHashed({
      schema: TRACE_SCHEMA, record_type: 'summary', run: decisionRunIdentity(this.run),
      decision_count: this.nextDecisionIndex, summary,
    });
    this.finished = true;
  }

  appendHashed(unhashedRecord) {
    const record = jsonSafe({ ...unhashedRecord, previous_hash: this.previousHash });
    record.record_hash = canonicalHash(record);
    this.records.push(record);
    this.previousHash = record.record_hash;
  }

  verify() {
    const issues = [];
    let previousHash = '';
    let expectedDecisionIndex = 0;
    let sawRun = false;
    let summaryRecord = null;
    const decisions = [];
    for (const [lineIndex, record] of this.records.entries()) {
      const line = lineIndex + 1;
      if (record.schema !== TRACE_SCHEMA) issues.push(`line ${line} has the wrong schema`);
      if (record.previous_hash !== previousHash) issues.push(`line ${line} breaks the hash chain`);
      const payload = { ...record };
      delete payload.record_hash;
      if (record.record_hash !== canonicalHash(payload)) issues.push(`line ${line} has an invalid hash`);
      previousHash = record.record_hash;
      if (record.record_type === 'run') {
        if (sawRun || lineIndex !== 0) issues.push(`line ${line} has a misplaced run header`);
        sawRun = true;
        issues.push(...validateRunMetadata(record.run));
      } else if (record.record_type === 'decision') {
        if (!sawRun || summaryRecord) issues.push(`line ${line} has a decision outside the run`);
        if (canonicalJson(record.run) !== canonicalJson(decisionRunIdentity(this.run))) {
          issues.push(`line ${line} decision identity does not match the run header`);
        }
        if (record.decision_index !== expectedDecisionIndex) {
          issues.push(`line ${line} has a noncontiguous decision index`);
        }
        expectedDecisionIndex += 1;
        issues.push(...validateDecisionRecord(record));
        issues.push(...inputSequenceProgressionReasons(decisions, record)
          .map((issue) => `line ${line}: ${issue}`));
        issues.push(...observationProgressionReasons(decisions, record)
          .map((issue) => `line ${line}: ${issue}`));
        decisions.push(record);
        if (canonicalJson(record.evidence) !== canonicalJson(classifyEvidence(record))) {
          issues.push(`line ${line} has self-declared evidence classification`);
        }
      } else if (record.record_type === 'summary') {
        if (!sawRun || summaryRecord) issues.push(`line ${line} has a misplaced summary`);
        summaryRecord = record;
        if (record.decision_count !== expectedDecisionIndex) {
          issues.push(`line ${line} summary count does not match decisions`);
        }
      } else {
        issues.push(`line ${line} has an unknown record type`);
      }
    }
    if (!sawRun) issues.push('trace has no run header');
    if (!summaryRecord) issues.push('trace has no summary');
    if (summaryRecord) {
      const goal = deriveBasinPersonaGoal(this.run, decisions);
      const ineligible = decisions.filter((record) => classifyEvidence(record).eligible_for_learning !== true)
        .map((record) => record.decision_index);
      if (summaryRecord.summary?.persona_goal_reached !== goal.reached
          || canonicalJson(summaryRecord.summary?.goal_evidence) !== canonicalJson(goal.evidence)) {
        issues.push('summary persona goal is not derived from persisted observations');
      }
      if (typeof summaryRecord.summary?.trace_complete !== 'boolean') {
        issues.push('summary trace_complete must be explicit');
      } else if (summaryRecord.summary.trace_complete
          && (!goal.reached || ineligible.length > 0)) {
        issues.push('summary trace_complete does not fail closed');
      }
      if (!sameStringMembers(summaryRecord.summary?.ineligible_decision_indices, ineligible)) {
        issues.push('summary ineligible decision indices do not match decisions');
      }
    }
    return [...new Set(issues)].sort();
  }

  async save(testInfo) {
    if (!this.finished) throw new Error('finish() must seal the trace before save()');
    const issues = this.verify();
    if (issues.length > 0) throw new Error(`invalid trace: ${issues.join('; ')}`);
    const pathname = testInfo.outputPath(this.artifactFileName);
    await writeFile(pathname, `${this.records.map((record) => canonicalJson(record)).join('\n')}\n`, 'utf8');
    await testInfo.attach(`${this.run.persona} Basin decision trace (${this.run.run_id})`, {
      path: pathname, contentType: 'application/x-ndjson',
    });
    return pathname;
  }
}
