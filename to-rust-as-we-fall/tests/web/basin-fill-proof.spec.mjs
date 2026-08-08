import { expect, test } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import {
  PersonaDecisionTrace,
  assertObservationActionCapability,
  assertPostChoiceAssertionOracle,
  authorizeObservationPlayerAction,
  canonicalHash,
  capturePlayerInput,
  captureProductionEvents,
  classifyEvidence,
  chooseVisibleInteraction as chooseVisibleInteractionFromObservation,
  deriveDecisionArtifacts,
  godotHashCompatibilityVector,
  inputSequenceProgressionReasons,
  movementCandidateDemonstrated,
  movementTargetAffordanceReasons,
  normalizeVisibleSubjectId,
  normalizeObservationSamples,
  observationProgressionReasons,
  observedAffordance as observedAffordanceFromObservation,
  postChoiceAssertionOracle,
  validateMechanicalInputEvents,
  validateBackgroundEventPresentation,
  validateDecisionRecord,
  validatePlayerObservation,
  visibleSubjectIds as visibleSubjectIdsFromObservation,
} from './persona-decision-trace.mjs';
import {
  deterministicInvocationId,
  isRequiredBasinInvocation,
  makeInvocationManifest,
} from './persona-validation-reporter.mjs';

const PARTY = ['aster', 'peris', 'endo'];
const GROUND_BIN_ORDER = [
  'top_center', 'top_left', 'middle_center', 'top_right', 'middle_right',
  'middle_left', 'bottom_center', 'bottom_right', 'bottom_left',
];
const MOVEMENT_TRANSFORM_TOLERANCE = 0.08;
// At the shipped 1152x648 observation canvas, 96 px keeps bodies that visibly
// occupy the shelter pad together while rejecting a member on the next stacked
// route line. The prior 180 px radius accepted Endo at 146 px and let a new
// Rally interrupt the console-assisted crossing before he reached the shelter.
const PARTY_NEAR_CUE_MAX_DISTANCE = 80;
const PERSONA_POLICY_AFFORDANCE = Symbol('persona-policy-affordance');
const UNGUARDED_PERSONA_INPUT_DISPATCH = 'unguarded_persona_input_dispatch';
const WEB_BOOT_BRIDGE_TARGETS = new Set(['fragments']);
const WEB_E2E_FIXTURE_IDS = Object.freeze([
  'generated_player_surface_seed_5',
  'result_pulse_static_green_contract',
]);
const WEB_E2E_FIXTURE_CHUNK = 'result_pulse_web_contract';
const WEB_E2E_FIXTURE_SCENE =
  'res://scenes/fragments/chunks/result_pulse_web_contract_chunk.tscn';
const WEB_POLICY_INPUT_FUNCTIONS = new Set([
  'chooseDeanUnmarkedGround',
  'chooseFarthestVisibleMove',
  'chooseGroundNearVisibleCue',
  'chooseVisibleCue',
  'chooseVisibleInteraction',
  'chooseVisibleLadderRoute',
  'selectFullVisiblePartyFromPortraits',
  'selectVisibleRosterCandidate',
  'visibleSubjectIds',
]);
const WEB_PRIVATE_BRIDGE_POLICY_FIELDS = [
  'active_character', 'anchors', 'assist_armed', 'assist_phase', 'characters',
  'chunk', 'click_targets', 'consequence_feedback', 'ladder_cells', 'ladder_edges',
  'move_refusals', 'player_observation', 'preview_chunk', 'selected_characters',
];
const WEB_NON_INPUT_GAMEPLAY_METHODS = [
  'command_move_to_pos', 'command_move_to_grid', 'command_move_cross_level',
  'command_walk_path', 'command_stop', 'command_start_drag', 'command_stop_drag',
  'command_push', 'command_rest', 'command_rally_members', 'snap_character_to',
  'set_character_level', 'headless_move_character', 'headless_set_character_position',
  'headless_commit_rally', 'headless_select_character', 'headless_advance',
  'set_preview_character_stat', 'adjust_preview_character_stat', 'set_stat',
  'adjust_stat', 'set_world_state', 'trigger_interactable',
  'activate_generated_node', 'on_interaction_arrived', '_trigger', '_commit_rally',
  '_commit_pick',
];
const DEAN_ATTEMPT_EXPECTED = {
  any: [
    { path: 'accepted', op: 'eq', value: true },
    { path: 'status', op: 'eq', value: 'refused' },
  ],
};

const GODOT_TRACE_HASH_VECTOR = '0342088474f6b4dc4033ebae86da70a1040959adbef6424ecf2b91bffb5b4ff0';
const NATIVE_CANDIDATE_HASHES = {
  dean_rally: 'dda7e3f6588ca81c5e783f6fe00fa1ce85bc31c9122e51d9bed11df96cfe1084',
  eazy_rally: 'eaee110e0a570a64d16020abb6910aeabb357211f2b08ff7e18e4edc6bb699cc',
  shelter_rally: '3b5404f2d29718766a8854c4c4d2598eb5fc4c06bd4972e247da3aa76a84a982',
  hide: '17c5e3ab82bf697462465ad58ad15790ce29f92f55f9f21332f85a592fdd4e20',
  select: '8f57007773508246070ef3c78a26d5d7d8d69cbe443befa6d1faa3a3709fbfed',
  wait: 'c0e8a6f801eed07c68b566efb52f942e11da58bb26f1c144afca514db0588c69',
  console: '067533880311edd59c6319bbcde8b3a823c7f0201bc452f31e3bf73b01e8e355',
  shelter: '1db150bcaf3af740a1e21c216b83ecac100276d51f19f7e47f7fd94fdd80f7ba',
};

function topLevelNamedFunctionSources(source) {
  const declarations = [...source.matchAll(
    /^(?:async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(([^)]*)\)\s*\{/gmu,
  )];
  return declarations.map((declaration) => {
    const bodyStart = declaration.index + declaration[0].length;
    const closing = /^\}/gmu;
    closing.lastIndex = bodyStart;
    const end = closing.exec(source)?.index ?? source.length;
    return {
      name: declaration[1],
      parameters: declaration[2].split(',').map((part) => part.trim()).filter(Boolean),
      source: source.slice(declaration.index, end + 1),
    };
  });
}

function webPersonaPolicyInputViolations(source) {
  const violations = new Set();
  const functions = topLevelNamedFunctionSources(source);
  const privateFieldAlternation = WEB_PRIVATE_BRIDGE_POLICY_FIELDS
    .map((field) => field.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&'))
    .join('|');
  const privateFieldRead = new RegExp(
    String.raw`(?:\?\.|\.)\s*(?:${privateFieldAlternation})\b|\[\s*['"](?:${privateFieldAlternation})['"]\s*\]`,
    'imu',
  );
  const privatePull = /\b(?:bridgeState|waitForState|currentPlayerObservation|bridgeTargetPagePoint|clickBridgeTarget)\s*\(|\b(?:globalThis|window)\s*(?:\.\s*__trawfE2E|\[\s*['"]__trawfE2E['"]\s*\])|\bpage\s*\.\s*evaluate\s*\(/imu;
  for (const entry of functions) {
    const looksLikePolicy = WEB_POLICY_INPUT_FUNCTIONS.has(entry.name)
      || /^(?:choose|decide|select|target)[A-Z_]/u.test(entry.name);
    if (!looksLikePolicy) continue;
    if (privatePull.test(entry.source) || privateFieldRead.test(entry.source)) {
      violations.add('private_bridge_policy_read');
    }
    if (WEB_POLICY_INPUT_FUNCTIONS.has(entry.name)
        && !entry.source.includes('requirePlayerObservationPolicyInput(')) {
      violations.add('unguarded_policy_input');
    }
  }
  const bridgeTargetCalls = [...source.matchAll(
    /\bclickBridgeTarget\s*\(\s*[^,\n]+,\s*['"]([^'"]+)['"]/gmu,
  )];
  if (bridgeTargetCalls.some((call) => !WEB_BOOT_BRIDGE_TARGETS.has(call[1]))) {
    violations.add('private_bridge_policy_target');
  }
  return [...violations].sort();
}

function webPlayerBoundaryViolations(source) {
  const violations = new Set();
  if (/(?:^|[^A-Za-z0-9_$])qa_[A-Za-z0-9_$]+\s*\(/imu.test(source)) {
    violations.add('hidden_qa_action');
  }
  const bridgeRoot = String.raw`(?:globalThis|window)\s*(?:\.\s*__trawfE2E|\[\s*['"]__trawfE2E['"]\s*\])`;
  const bridgeProperty = String.raw`(?:\.\s*[A-Za-z_$][A-Za-z0-9_$]*|\[\s*['"][^'"]+['"]\s*\])`;
  const bridgeRootAssignment = new RegExp(`${bridgeRoot}\\s*(?:=|\\+=|-=|\\*=|/=)`, 'imu');
  const bridgeMemberMutation = new RegExp(
    `${bridgeRoot}(?:${bridgeProperty})+\\s*(?:=|\\+=|-=|\\*=|/=|\\()`, 'imu',
  );
  if (bridgeRootAssignment.test(source) || bridgeMemberMutation.test(source)) {
    violations.add('direct_bridge_mutation');
  }
  const methodAlternation = WEB_NON_INPUT_GAMEPLAY_METHODS
    .map((method) => method.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&'))
    .join('|');
  const directCommand = new RegExp(`\\b(?:${methodAlternation})\\s*\\(`, 'imu');
  const dynamicCommand = new RegExp(
    `\\b(?:call|callv|invoke)\\s*\\(\\s*['"](?:${methodAlternation})['"]`, 'imu',
  );
  if (directCommand.test(source) || dynamicCommand.test(source)) {
    violations.add('non_input_gameplay_command');
  }
  for (const violation of webPersonaPolicyInputViolations(source)) violations.add(violation);
  return [...violations].sort();
}

function gdscriptFunctionSource(source, functionName) {
  const startPattern = new RegExp(
    `^(?:static\\s+)?func\\s+${functionName}\\b`,
    'mu',
  );
  const start = startPattern.exec(source)?.index ?? -1;
  if (start < 0) return '';
  const nextFunction = /^(?:static\s+)?func\s+[A-Za-z0-9_]+\b/gmu;
  nextFunction.lastIndex = start + 1;
  const end = nextFunction.exec(source)?.index ?? source.length;
  return source.slice(start, end);
}

function gdscriptContainerConstantSource(source, constantName) {
  const escapedName = constantName.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  const declaration = new RegExp(`^const\\s+${escapedName}\\s*:=`, 'mu').exec(source);
  if (!declaration) return '';
  let cursor = declaration.index + declaration[0].length;
  while (/\s/u.test(source[cursor] ?? '')) cursor += 1;
  if (source[cursor] !== '{' && source[cursor] !== '[') return '';
  const closingFor = { '{': '}', '[': ']' };
  const stack = [];
  let quote = '';
  let escaped = false;
  let comment = false;
  for (let index = cursor; index < source.length; index += 1) {
    const character = source[index];
    if (comment) {
      if (character === '\n') comment = false;
      continue;
    }
    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (character === '\\') {
        escaped = true;
      } else if (character === quote) {
        quote = '';
      }
      continue;
    }
    if (character === '#') {
      comment = true;
      continue;
    }
    if (character === '"' || character === "'") {
      quote = character;
      continue;
    }
    if (character === '{' || character === '[') {
      stack.push(closingFor[character]);
      continue;
    }
    if (character === '}' || character === ']') {
      if (stack.at(-1) !== character) return '';
      stack.pop();
      if (stack.length === 0) return source.slice(declaration.index, index + 1);
    }
  }
  return '';
}

function gdscriptNamedFunctionSources(source) {
  return [...source.matchAll(/^(?:static\s+)?func\s+([A-Za-z0-9_]+)\b/gmu)]
    .map((match) => ({
      name: match[1],
      source: gdscriptFunctionSource(source, match[1]),
    }));
}

function webFixtureQuarantineViolations(fragmentSource, mainMenuSource) {
  const violations = new Set();
  const ordinaryEntries = gdscriptContainerConstantSource(fragmentSource, 'PREVIEW_ENTRIES');
  const ordinaryChunks = gdscriptContainerConstantSource(fragmentSource, 'CHUNK_SCENES');
  const fixtureEntries = gdscriptContainerConstantSource(
    fragmentSource, 'WEB_E2E_PREVIEW_ENTRIES',
  );
  const fixtureChunks = gdscriptContainerConstantSource(
    fragmentSource, 'WEB_E2E_CHUNK_SCENES',
  );
  if (!ordinaryEntries) violations.add('ordinary_preview_registry_unreadable');
  if (!ordinaryChunks) violations.add('ordinary_chunk_registry_unreadable');
  if (!fixtureEntries) violations.add('web_fixture_registry_unreadable');
  if (!fixtureChunks) violations.add('web_fixture_chunk_registry_unreadable');
  if (WEB_E2E_FIXTURE_IDS.some((fixtureId) => ordinaryEntries.includes(fixtureId))) {
    violations.add('fixture_id_in_ordinary_preview_registry');
  }
  if (ordinaryEntries.includes(WEB_E2E_FIXTURE_CHUNK)
      || ordinaryEntries.includes(WEB_E2E_FIXTURE_SCENE)) {
    violations.add('fixture_scene_in_ordinary_preview_registry');
  }
  if (ordinaryChunks.includes(WEB_E2E_FIXTURE_CHUNK)
      || ordinaryChunks.includes(WEB_E2E_FIXTURE_SCENE)) {
    violations.add('fixture_scene_in_ordinary_chunk_registry');
  }
  if (WEB_E2E_FIXTURE_IDS.some((fixtureId) => !fixtureEntries.includes(fixtureId))) {
    violations.add('fixture_id_missing_from_web_registry');
  }
  if (!fixtureChunks.includes(WEB_E2E_FIXTURE_CHUNK)) {
    violations.add('fixture_scene_missing_from_web_chunk_registry');
  }

  const ordinaryResolver = gdscriptFunctionSource(fragmentSource, 'get_preview_entry');
  if (!ordinaryResolver.includes('for entry in PREVIEW_ENTRIES:')
      || /WEB_E2E|get_web_e2e_preview_entry/u.test(ordinaryResolver)) {
    violations.add('ordinary_resolver_reaches_web_fixture_registry');
  }
  const stageResolver = gdscriptFunctionSource(fragmentSource, 'get_preview_stage');
  if (!stageResolver.includes('get_preview_entry(entry_id)')
      || /WEB_E2E|get_web_e2e_preview_entry/u.test(stageResolver)) {
    violations.add('ordinary_stage_resolver_reaches_web_fixture_registry');
  }
  const picker = gdscriptFunctionSource(fragmentSource, '_build_fragment_menu');
  if (!picker.includes('PREVIEW_ENTRIES.size()')
      || !picker.includes('PREVIEW_ENTRIES.duplicate()')
      || /WEB_E2E|get_web_e2e_preview_entry/u.test(picker)) {
    violations.add('ordinary_picker_reaches_web_fixture_registry');
  }
  const handoff = gdscriptFunctionSource(fragmentSource, 'request_preview_handoff');
  if (!handoff.includes('get_preview_entry(entry_id)')
      || /WEB_E2E|get_web_e2e_preview_entry/u.test(handoff)) {
    violations.add('ordinary_handoff_reaches_web_fixture_registry');
  }
  const begin = gdscriptFunctionSource(fragmentSource, '_begin');
  if (!begin.includes('_apply_preview_entry(get_preview_entry(cli_id))')
      || !begin.includes('_apply_preview_entry(get_preview_entry(menu_launch_id))')
      || /WEB_E2E|get_web_e2e_preview_entry/u.test(begin)) {
    violations.add('ordinary_cli_or_id_route_reaches_web_fixture_registry');
  }
  const fixtureResolver = gdscriptFunctionSource(
    fragmentSource, 'get_web_e2e_preview_entry',
  );
  if (!fixtureResolver.includes('WEB_E2E_PREVIEW_ENTRIES.get(entry_id, null)')
      || !fixtureResolver.includes('get_preview_entry(entry_id)')) {
    violations.add('web_query_resolver_does_not_isolate_fixture_registry');
  }
  const chunkLookup = gdscriptFunctionSource(fragmentSource, '_get_chunk_scene');
  const fixtureEntryGuard = chunkLookup.indexOf(
    'if WEB_E2E_PREVIEW_ENTRIES.has(_active_preview_entry_id):',
  );
  const fixtureSceneLookup = chunkLookup.indexOf('WEB_E2E_CHUNK_SCENES.get(');
  const ordinarySceneLookup = chunkLookup.indexOf('CHUNK_SCENES.get(chunk_name, null)');
  if (fixtureEntryGuard < 0 || fixtureSceneLookup < fixtureEntryGuard
      || ordinarySceneLookup < fixtureSceneLookup) {
    violations.add('web_fixture_scene_lookup_not_entry_gated');
  }
  for (const entry of gdscriptNamedFunctionSources(fragmentSource)) {
    if (/WEB_E2E_PREVIEW_ENTRIES|WEB_E2E_CHUNK_SCENES/u.test(entry.source)
        && !['get_web_e2e_preview_entry', '_get_chunk_scene'].includes(entry.name)) {
      violations.add('web_fixture_registry_referenced_by_unapproved_fragment_route');
    }
  }

  const webSetup = gdscriptFunctionSource(mainMenuSource, '_setup_web_e2e_probe');
  if (!webSetup.includes(
    'if not OS.has_feature("web") or _web_query_value("e2e") != "1":',
  ) || !webSetup.includes('FragmentPreviewScript.get_web_e2e_preview_entry(requested_fragment)')
      || !webSetup.includes('requested_fragment == "" or requested_entry.is_empty()')
      || !webSetup.includes('FragmentPreviewScript.menu_launch_entry = requested_entry.duplicate(true)')) {
    violations.add('web_fixture_launch_not_web_query_gated');
  }
  const fixtureResolverCalls = mainMenuSource.match(
    /FragmentPreviewScript\.get_web_e2e_preview_entry\s*\(/gu,
  ) ?? [];
  const fixtureEntryAssignments = mainMenuSource.match(
    /FragmentPreviewScript\.menu_launch_entry\s*=/gu,
  ) ?? [];
  if (fixtureResolverCalls.length !== 1 || fixtureEntryAssignments.length !== 1) {
    violations.add('web_fixture_launch_has_additional_main_menu_route');
  }
  for (const entry of gdscriptNamedFunctionSources(mainMenuSource)) {
    if (entry.name === '_setup_web_e2e_probe') continue;
    if (/get_web_e2e_preview_entry|menu_launch_entry\s*=|generated_player_surface_seed_5|result_pulse_static_green_contract/u
      .test(entry.source)) {
      violations.add('ordinary_main_menu_route_reaches_web_fixture_registry');
    }
  }
  return [...violations].sort();
}

function webHintProjectionViolations(source) {
  const violations = new Set();
  const projection = gdscriptFunctionSource(source, '_visible_input_hint_texts');
  const visibility = gdscriptFunctionSource(source, '_control_has_player_visible_area');
  if (!projection.includes('_control_has_player_visible_area')) {
    violations.add('hint_current_render_guard_missing');
  }
  if (!projection.includes('get_binding_label')) {
    violations.add('hint_rendered_binding_label_missing');
  }
  if (/\b(?:InputMap|command_|headless_)|["']_?action["']|\.action\b/iu.test(projection)) {
    violations.add('hint_private_action_or_command_leak');
  }
  if (!visibility.includes('is_visible_in_tree')
      || !visibility.includes('modulate.a')
      || !visibility.includes('self_modulate.a')) {
    violations.add('hint_inherited_or_alpha_visibility_guard_missing');
  }
  if (!visibility.includes('get_visible_rect')
      || !visibility.includes('get_global_rect')
      || !visibility.includes('intersection')
      || !visibility.includes('has_area')) {
    violations.add('hint_viewport_visibility_guard_missing');
  }
  if (!visibility.includes('clip_contents')) {
    violations.add('hint_ancestor_clipping_guard_missing');
  }
  return [...violations].sort();
}

function requirePlayerObservationPolicyInput(observation, context) {
  if (observation?.schema !== 'player_observation_v1'
      || observation?.source !== 'player_observable'
      || !Number.isInteger(observation?.tick)
      || !Number.isInteger(observation?.capture_serial)
      || typeof observation?.state !== 'object'
      || observation.state === null) {
    throw new TypeError(`${context} requires one player_observation_v1 policy input`);
  }
  for (const privateField of WEB_PRIVATE_BRIDGE_POLICY_FIELDS) {
    if (privateField === 'player_observation') continue;
    if (Object.hasOwn(observation, privateField)) {
      throw new TypeError(`${context} rejects private bridge field ${privateField}`);
    }
  }
  return observation;
}

function personaPolicyAffordance(observation, affordance, context) {
  requirePlayerObservationPolicyInput(observation, context);
  if (!affordance) return null;
  const selected = structuredClone(affordance);
  Object.defineProperty(selected, PERSONA_POLICY_AFFORDANCE, {
    value: true, enumerable: false, configurable: false, writable: false,
  });
  return Object.freeze(selected);
}

function requirePersonaPolicyAffordance(affordance, context) {
  if (affordance?.[PERSONA_POLICY_AFFORDANCE] !== true) {
    throw new TypeError(`${context} requires a target selected from player_observation_v1`);
  }
  return affordance;
}

function authorizePersonaAction(inputLedger, observation, affordance, request, context) {
  requirePlayerObservationPolicyInput(observation, context);
  requirePersonaPolicyAffordance(affordance, context);
  return authorizeObservationPlayerAction(inputLedger, observation, {
    ...request,
    choice: affordance,
  });
}

function authorizePassiveObservationDecision(inputLedger, observation, context) {
  requirePlayerObservationPolicyInput(observation, context);
  return authorizeObservationPlayerAction(inputLedger, observation, {
    gesture: 'passive_wait', targetToken: `passive_wait:${observation.capture_serial}`,
  });
}

function visibleGroundConditions() {
  return GROUND_BIN_ORDER.map((bin) => ({
    path: `viewport_bins.${bin}.0`, op: 'exists', value: true,
  }));
}

function rallyCandidate(persona, selectedAffordance = {}) {
  const isEazy = persona === 'eazy_speezy';
  const consequence = String(selectedAffordance?.consequence ?? '').trim();
  const conditions = isEazy
    ? (consequence && /LADDER/i.test(consequence) ? [{
      path: 'visible_affordance_consequences', op: 'contains', value: consequence,
    }] : [])
    : visibleGroundConditions();
  if (conditions.length === 0) return {};
  return {
    node_id: isEazy
      ? 'eazy_speezy_rally_marked_deck_access'
      : 'dean_takahashi_rally_unmarked_visible_floor',
    rule: isEazy
      ? 'Eazy reads the visible instructions and rallies the full party toward the marked DECK ACCESS target in screen-space.'
      : 'Dean ignores the visible DECK ACCESS marker and issues a pointless Rally toward an arbitrary screen-space floor target.',
    scope: 'fragment',
    priority: isEazy ? 60 : 40,
    condition: { any: conditions },
    action: {
      verb: 'rally',
      target_ref: isEazy ? 'matching_visible_ladder_route' : 'chosen_visible_ground',
    },
    expected: isEazy
      ? { path: 'accepted', op: 'eq', value: true }
      : structuredClone(DEAN_ATTEMPT_EXPECTED),
  };
}

function shelterRallyCandidate(visibleShelterVerb) {
  const exactVerb = String(visibleShelterVerb ?? '').trim();
  if (!exactVerb) return {};
  return {
    node_id: 'eazy_speezy_rally_full_party_to_visible_shelter',
    rule: 'When REST PARTY is visible, hold Rally on that exact shelter surface so its shown formation region gathers the full party before interacting.',
    scope: 'fragment',
    priority: 68,
    condition: {
      path: 'visible_affordance_verbs', op: 'contains', value: exactVerb,
    },
    action: { verb: 'rally', target_ref: 'matching_visible_shelter_surface' },
    expected: { path: 'accepted', op: 'eq', value: true },
  };
}

function hideInstructionsCandidate(cue) {
  if (cue?.kind !== 'instruction' || cue?.visible !== true
      || String(cue?.text ?? '').trim() === '') return {};
  return {
    node_id: 'hide_instructions_when_they_occlude_the_board',
    rule: 'Hide a visible instruction panel when it occludes the board needed for the next route decision.',
    scope: 'global',
    priority: 90,
    condition: { path: 'cues', op: 'contains', value: structuredClone(cue) },
    action: { verb: 'toggle_instructions', target_ref: 'advertised_visible_hide_control' },
    expected: { path: 'visible_change', op: 'eq', value: true },
  };
}

function selectVisibleRosterCandidate(observation) {
  requirePlayerObservationPolicyInput(observation, 'visible-roster candidate');
  const portraits = (observation?.state?.hud?.portraits ?? [])
    .filter((portrait) => portrait?.visible === true).map((portrait) => structuredClone(portrait));
  if (portraits.length === 0 || portraits.every((portrait) => portrait.selected === true)) return {};
  return {
    node_id: 'eazy_speezy_select_full_visible_roster',
    rule: 'Select every currently visible party portrait before an advertised selected-party interaction.',
    scope: 'global',
    priority: 80,
    condition: {
      all: portraits.map((portrait) => ({
        path: 'hud.portraits', op: 'contains', value: portrait,
      })),
    },
    action: { verb: 'select_party', target_ref: 'visible_hud_roster' },
    expected: { path: 'visible_change', op: 'eq', value: true },
  };
}

function announcedWaitCandidate(cue) {
  if (cue?.visible !== true
      || !/CROSSING STAGING|CROSSING ARMED|NEXT MID/i.test(`${cue?.text ?? ''} ${cue?.label ?? ''}`)) {
    return {};
  }
  return {
    node_id: 'wait_for_visible_announced_mid_crossing',
    rule: 'Wait on the rendered clock while an announced selected-party consequence is visibly in progress.',
    scope: 'fragment',
    priority: 75,
    condition: { path: 'cues', op: 'contains', value: structuredClone(cue) },
    action: { verb: 'wait', target_ref: 'announced_visible_consequence' },
    expected: { path: 'visible_change', op: 'eq', value: true },
  };
}

function interactionCandidate(persona, visibleVerb) {
  const exactVerb = String(visibleVerb ?? '').trim();
  const upper = exactVerb.toUpperCase();
  const suffix = upper.includes('ARM NEXT MID') ? 'arm_visible_mid_console'
    : (upper.includes('REST') || upper.includes('SHELTER') ? 'use_visible_exit_shelter' : '');
  if (!suffix) return {};
  const displayPersona = persona === 'dean_takahashi' ? 'Dean' : 'Eazy';
  const rationale = persona === 'dean_takahashi'
    ? `${displayPersona} clicks the visible ${visibleVerb} prompt without checking whether it advances the puzzle.`
    : `${displayPersona} prioritizes the visible ${visibleVerb} prompt before wandering to another floor target.`;
  return {
    node_id: `${persona}_${suffix}`,
    rule: rationale,
    scope: 'fragment',
    priority: 70,
    condition: { path: 'visible_affordance_verbs', op: 'contains', value: exactVerb },
    action: { verb: 'interact', target_ref: 'matching_visible_interaction' },
    expected: { path: 'accepted', op: 'eq', value: true },
  };
}

function verifyNativeCandidatePolicyParity() {
  const instructionCue = {
    kind: 'instruction', text: 'H HIDE INSTRUCTIONS', visible: true,
  };
  const announcedCue = {
    kind: 'status', text: 'CROSSING STAGING // NEXT MID', visible: true,
  };
  const rosterObservation = {
    schema: 'player_observation_v1', source: 'player_observable', tick: 1, capture_serial: 1,
    state: { hud: { portraits: [
    {
      token: 'portrait-0', label: 'aster', visible: true, downed: false, selected: true,
    },
    {
      token: 'portrait-1', label: 'peris', visible: true, downed: false, selected: false,
    },
    {
      token: 'portrait-2', label: 'endo', visible: true, downed: false, selected: false,
    },
    ] } },
  };
  const candidates = {
    dean_rally: rallyCandidate('dean_takahashi'),
    eazy_rally: rallyCandidate('eazy_speezy', { consequence: 'ROUTE VIA LADDER' }),
    shelter_rally: shelterRallyCandidate('REST PARTY'),
    hide: hideInstructionsCandidate(instructionCue),
    select: selectVisibleRosterCandidate(rosterObservation),
    wait: announcedWaitCandidate(announcedCue),
    console: interactionCandidate('eazy_speezy', 'UPPER DECK > ARM NEXT MID'),
    shelter: interactionCandidate('eazy_speezy', 'REST PARTY'),
  };
  for (const [label, expectedHash] of Object.entries(NATIVE_CANDIDATE_HASHES)) {
    const actualHash = canonicalHash(candidates[label]);
    if (actualHash !== expectedHash) {
      throw new Error(
        `Web/Native candidate policy mismatch for ${label}: ${actualHash} != ${expectedHash}`,
      );
    }
  }
}

function contractPlayerObservation(captureSerial = 1) {
  return {
    schema: 'player_observation_v1', source: 'player_observable', tick: captureSerial,
    capture_serial: captureSerial,
    state: {
      hud: { portraits: PARTY.map((label, index) => ({
        token: `portrait-${index}`, label, visible: true, downed: false,
        selected: index === 0,
      })) },
      viewport: { origin: [0, 0], size: [1102, 598] },
      affordances: [{
        token: 'ordinary-floor', kind: 'move', verb: 'MOVE',
        consequence: 'WALK ROUTE', screen: [420, 420],
      }],
      visible_affordance_verbs: ['MOVE'],
      visible_affordance_consequences: ['WALK ROUTE'],
      viewport_bins: { middle_center: ['ordinary-floor'] },
      cues: PARTY.map((subject, index) => ({
        kind: 'party_body', source_token: `body-${subject}`, screen: [300 + index * 20, 300],
        binding: `portrait-${index}`, visible: true,
      })),
    },
  };
}

// Discovery itself fails if a Web policy shape would conflict with the Native node of the same id.
verifyNativeCandidatePolicyParity();

test.beforeAll(async () => {
  expect(godotHashCompatibilityVector(),
    'Web traces hash the same parser-normalized bytes as PersonaDecisionTrace.gd')
    .toBe(GODOT_TRACE_HASH_VECTOR);
  const interactionTargetObservation = contractPlayerObservation(1);
  interactionTargetObservation.state.affordances = [{
    token: 'shelter-surface', kind: 'interact', verb: 'REST PARTY',
    consequence: 'Shelter', screen: [552, 320],
  }];
  expect(movementTargetAffordanceReasons(interactionTargetObservation, {
    verb: 'rally', target: { token: 'shelter-surface' },
  }), 'Web Rally evidence may bind its real right-hold movement to a visible interaction surface')
    .toEqual([]);
  expect(movementTargetAffordanceReasons(interactionTargetObservation, {
    verb: 'move', target: { token: 'shelter-surface' },
  }), 'Web ordinary Move evidence remains bound to a visible move affordance').toContain(
    'movement_target_not_visible_move_affordance_before',
  );
  const webTestSource = await readFile(new URL(import.meta.url), 'utf8');
  expect(webPlayerBoundaryViolations(webTestSource),
    'the Web persona player contains no hidden semantic action or direct gameplay mutation')
    .toEqual([]);
  const cameraRecoverySource = topLevelNamedFunctionSources(webTestSource)
    .find((entry) => entry.name === 'discoverGeneratedHideThroughVisibleControls')?.source ?? '';
  for (const requiredVisibleControlGuard of [
    'chooseVisibleCue(observation, attempt.pattern)',
    "visibleControl.kind !== 'instruction'",
    'attempt.pattern.test(visibleControlText)',
    'attempt.glyph.test(visibleControlText)',
    'authorizePersonaAction(',
  ]) {
    expect(cameraRecoverySource,
      `seed camera recovery requires visible glyph/description guard ${requiredVisibleControlGuard}`)
      .toContain(requiredVisibleControlGuard);
  }
  const fragmentPreviewSource = await readFile(new URL(
    '../../scripts/fragments/fragment_preview_sequence.gd', import.meta.url,
  ), 'utf8');
  const mainMenuSource = await readFile(new URL(
    '../../scripts/ui/main_menu.gd', import.meta.url,
  ), 'utf8');
  expect(webFixtureQuarantineViolations(fragmentPreviewSource, mainMenuSource),
    'Web-only fixture ids and scenes have no ordinary picker, handoff, CLI, or resolver route')
    .toEqual([]);
  const quarantineMutations = [
    {
      label: 'fixture id inserted into PREVIEW_ENTRIES',
      fragmentSource: fragmentPreviewSource.replace(
        'const PREVIEW_ENTRIES := [',
        'const PREVIEW_ENTRIES := [\n\t{"id": "generated_player_surface_seed_5"},',
      ),
      mainMenuSource,
      expected: 'fixture_id_in_ordinary_preview_registry',
    },
    {
      label: 'fixture scene inserted into CHUNK_SCENES',
      fragmentSource: fragmentPreviewSource.replace(
        'const CHUNK_SCENES := {',
        'const CHUNK_SCENES := {\n\t"result_pulse_web_contract": RESULT_PULSE_WEB_CONTRACT_CHUNK_SCENE,',
      ),
      mainMenuSource,
      expected: 'fixture_scene_in_ordinary_chunk_registry',
    },
    {
      label: 'ordinary picker switched to the Web fixture registry',
      fragmentSource: fragmentPreviewSource.replace(
        'var ordered := PREVIEW_ENTRIES.duplicate()',
        'var ordered := WEB_E2E_PREVIEW_ENTRIES.values()',
      ),
      mainMenuSource,
      expected: 'ordinary_picker_reaches_web_fixture_registry',
    },
    {
      label: 'ordinary handoff switched to the Web fixture resolver',
      fragmentSource: fragmentPreviewSource.replace(
        'if get_preview_entry(entry_id).is_empty():',
        'if get_web_e2e_preview_entry(entry_id).is_empty():',
      ),
      mainMenuSource,
      expected: 'ordinary_handoff_reaches_web_fixture_registry',
    },
    {
      label: 'ordinary id resolver switched to the Web fixture registry',
      fragmentSource: fragmentPreviewSource.replace(
        'for entry in PREVIEW_ENTRIES:',
        'for entry in WEB_E2E_PREVIEW_ENTRIES.values():',
      ),
      mainMenuSource,
      expected: 'ordinary_resolver_reaches_web_fixture_registry',
    },
    {
      label: 'CLI preview id switched to the Web fixture resolver',
      fragmentSource: fragmentPreviewSource.replace(
        '_apply_preview_entry(get_preview_entry(cli_id))',
        '_apply_preview_entry(get_web_e2e_preview_entry(cli_id))',
      ),
      mainMenuSource,
      expected: 'ordinary_cli_or_id_route_reaches_web_fixture_registry',
    },
    {
      label: 'fixture scene lookup loses its quarantined-entry guard',
      fragmentSource: fragmentPreviewSource.replace(
        'if WEB_E2E_PREVIEW_ENTRIES.has(_active_preview_entry_id):',
        'if true:',
      ),
      mainMenuSource,
      expected: 'web_fixture_scene_lookup_not_entry_gated',
    },
    {
      label: 'query setup loses its Web platform guard',
      fragmentSource: fragmentPreviewSource,
      mainMenuSource: mainMenuSource.replace(
        'if not OS.has_feature("web") or _web_query_value("e2e") != "1":',
        'if _web_query_value("e2e") != "1":',
      ),
      expected: 'web_fixture_launch_not_web_query_gated',
    },
    {
      label: 'ordinary Fragments button writes a fixture launch entry',
      fragmentSource: fragmentPreviewSource,
      mainMenuSource: mainMenuSource.replace(
        'func _on_fragments() -> void:\n\tget_tree().change_scene_to_file(FRAGMENTS_SCENE)',
        'func _on_fragments() -> void:\n'
          + '\tFragmentPreviewScript.menu_launch_entry = {"id": "result_pulse_static_green_contract"}\n'
          + '\tget_tree().change_scene_to_file(FRAGMENTS_SCENE)',
      ),
      expected: 'ordinary_main_menu_route_reaches_web_fixture_registry',
    },
  ];
  for (const mutation of quarantineMutations) {
    expect(
      mutation.fragmentSource !== fragmentPreviewSource
        || mutation.mainMenuSource !== mainMenuSource,
      `${mutation.label} mutation changes one guarded production source`,
    ).toBe(true);
    expect(webFixtureQuarantineViolations(
      mutation.fragmentSource, mutation.mainMenuSource,
    ), `fixture quarantine rejects ${mutation.label}`).toContain(mutation.expected);
  }
  expect(webHintProjectionViolations(fragmentPreviewSource),
    'visible hint projection uses only current rendered glyph/description evidence')
    .toEqual([]);
  const hintProjectionMutations = [
    {
      label: 'visibility-only chip admission',
      source: fragmentPreviewSource.replace(
        'or not _control_has_player_visible_area(chip_v as Control):',
        'or not (chip_v as Control).is_visible_in_tree():',
      ),
      expected: 'hint_current_render_guard_missing',
    },
    {
      label: 'ancestor clip omission',
      source: fragmentPreviewSource.replace('clip_contents:', 'mouse_filter > 99:'),
      expected: 'hint_ancestor_clipping_guard_missing',
    },
    {
      label: 'private action-name projection',
      source: fragmentPreviewSource.replace(
        'part_v.call(\n\t\t\t\t\t"get_binding_label")',
        'part_v.get("_action")',
      ),
      expected: 'hint_private_action_or_command_leak',
    },
  ];
  for (const mutation of hintProjectionMutations) {
    expect(mutation.source, `${mutation.label} mutation changes the guarded source`)
      .not.toBe(fragmentPreviewSource);
    expect(webHintProjectionViolations(mutation.source),
      `hint projection rejects ${mutation.label}`).toContain(mutation.expected);
  }
  const webBoundaryMutations = [
    {
      label: 'qa target shortcut',
      source: ['qa', '_move_character("aster", [0, 0, 0])'].join(''),
      expected: 'hidden_qa_action',
    },
    {
      label: 'direct bridge state mutation',
      source: ['globalThis.__trawf', 'E2E.characters.aster.position = [0, 0, 0]'].join(''),
      expected: 'direct_bridge_mutation',
    },
    {
      label: 'non-input gameplay command',
      source: ['authority.command_move', '_to_pos("aster", [0, 0, 0])'].join(''),
      expected: 'non_input_gameplay_command',
    },
    {
      label: 'dynamic non-input gameplay command',
      source: ['authority.call("command_', 'rally_members", ["aster"])'].join(''),
      expected: 'non_input_gameplay_command',
    },
    {
      label: 'policy helper pulls raw bridge state',
      source: [
        'function chooseFutureTarget(observation) {',
        '  const privateState = bridge' + 'State(observation.page);',
        '  return privateState.anchors.failure_bowl;',
        '}',
      ].join('\n'),
      expected: 'private_bridge_policy_read',
    },
    {
      label: 'policy helper reads a private bridge field',
      source: [
        'function decideFutureAction(state) {',
        '  return state["click_' + 'targets"].failure_bowl;',
        '}',
      ].join('\n'),
      expected: 'private_bridge_policy_read',
    },
    {
      label: 'policy helper unwraps player observation from raw bridge payload',
      source: [
        'function targetFutureAction(state) {',
        '  return state.player_' + 'observation.state.affordances[0];',
        '}',
      ].join('\n'),
      expected: 'private_bridge_policy_read',
    },
    {
      label: 'new selector skips the player-observation input check',
      source: [
        'function chooseDeanUnmarkedGround(observation) {',
        '  return observation.state.affordances[0];',
        '}',
      ].join('\n'),
      expected: 'unguarded_policy_input',
    },
    {
      label: 'gameplay uses a named private bridge click target',
      source: ['await clickBridge', 'Target(page, "failure_bowl");'].join(''),
      expected: 'private_bridge_policy_target',
    },
  ];
  for (const mutation of webBoundaryMutations) {
    expect(webPlayerBoundaryViolations(mutation.source),
      `Web static boundary rejects ${mutation.label}`).toContain(mutation.expected);
  }
  expect(webPlayerBoundaryViolations([
    'function expectFutureMechanismOracle(state) {',
    '  return state.characters.aster.logical_position;',
    '}',
  ].join('\n')), 'private bridge fields remain legal inside post-choice assertion helpers')
    .toEqual([]);
  expect(() => requirePlayerObservationPolicyInput({
    player_observation: {
      schema: 'player_observation_v1', source: 'player_observable', tick: 1, capture_serial: 1,
      state: {},
    },
    characters: {},
  }, 'raw bridge mutation vector'),
  'a raw bridge payload cannot masquerade as policy input by containing player_observation')
    .toThrow(/requires one player_observation_v1 policy input/);
  expect(() => requirePersonaPolicyAffordance({
    token: 'private-anchor', screen: [1, 1],
  }, 'unbranded target mutation vector'),
  'pointer execution rejects a target that was not selected by an observation-gated policy helper')
    .toThrow(/requires a target selected from player_observation_v1/);
  expect(WEB_BOOT_BRIDGE_TARGETS.has('failure_bowl'),
    'private gameplay bridge targets are absent from the boot-only allowlist').toBe(false);
  const fingerprint = '7'.repeat(64);
  const gameplayBuildFingerprint = '6'.repeat(64);
  const first = new PersonaDecisionTrace({
    persona: 'trace_contract_probe', fragmentId: 'basin_fill_proof', seed: 0,
    contentFingerprintSchema: 'authored_fragment_resource_bytes_v1',
    contentFingerprint: fingerprint,
    gameplayBuildFingerprintSchema: 'gameplay_build_resource_set_bytes_v1',
    gameplayBuildFingerprint,
    runIndex: 0,
  });
  const second = new PersonaDecisionTrace({
    persona: 'trace_contract_probe', fragmentId: 'basin_fill_proof', seed: 1,
    contentFingerprintSchema: 'authored_fragment_resource_bytes_v1',
    contentFingerprint: fingerprint,
    gameplayBuildFingerprintSchema: 'gameplay_build_resource_set_bytes_v1',
    gameplayBuildFingerprint,
    runIndex: 1,
  });
  expect(first.run.run_id, 'repeat 0 has an independent Web run identity')
    .not.toBe(second.run.run_id);
  expect(first.run.trace_id, 'repeat 0 has an independent Web trace identity')
    .not.toBe(second.run.trace_id);
  expect(first.artifactFileName, 'repeat traces cannot overwrite one artifact')
    .not.toBe(second.artifactFileName);

  const manifestDocuments = ['dean_takahashi', 'eazy_speezy'].flatMap((persona) =>
    [0, 1].map((repeatIndex) => ({
      run: {
        run_id: `${persona}:web:${repeatIndex}`,
        trace_id: `${persona}:web:${repeatIndex}`,
        persona,
        fragment_id: 'basin_fill_proof',
        execution_platform: 'web',
        repeat_index: repeatIndex,
        content_fingerprint_schema: 'authored_fragment_resource_bytes_v1',
        content_fingerprint: fingerprint,
        gameplay_build_fingerprint_schema: 'gameplay_build_resource_set_bytes_v1',
        gameplay_build_fingerprint: gameplayBuildFingerprint,
      },
      issues: [],
      summaryRecord: {
        record_hash: `${repeatIndex + 1}`.repeat(64),
        summary: { trace_complete: true, persona_goal_reached: true },
      },
      decisionCount: 1,
    })));
  expect(makeInvocationManifest(manifestDocuments, 'uniform-content-vector').passed,
    'the complete Web 2x2 cohort can bind one authored content identity').toBe(true);
  expect(deterministicInvocationId(manifestDocuments, 'web'),
    'the same exact trace identities and summaries always derive the same invocation identity')
    .toBe(deterministicInvocationId(structuredClone(manifestDocuments), 'web'));
  const changedSummaryDocuments = structuredClone(manifestDocuments);
  changedSummaryDocuments[0].summaryRecord.record_hash = '9'.repeat(64);
  expect(deterministicInvocationId(changedSummaryDocuments, 'web'),
    'a materially different trace summary cannot masquerade as the same invocation')
    .not.toBe(deterministicInvocationId(manifestDocuments, 'web'));
  const splitContentDocuments = structuredClone(manifestDocuments);
  splitContentDocuments[3].run.content_fingerprint = '8'.repeat(64);
  const splitContentManifest = makeInvocationManifest(
    splitContentDocuments, 'split-content-vector',
  );
  expect(splitContentManifest.passed,
    'a 2x2 cohort cannot seal traces from different authored Basin bytes').toBe(false);
  expect(splitContentManifest.failures).toContain('cohort_content_identity_mismatch');
  const splitBuildDocuments = structuredClone(manifestDocuments);
  splitBuildDocuments[3].run.gameplay_build_fingerprint = '5'.repeat(64);
  const splitBuildManifest = makeInvocationManifest(
    splitBuildDocuments, 'split-build-vector',
  );
  expect(splitBuildManifest.passed,
    'a 2x2 cohort cannot pool traces produced by different gameplay code bytes').toBe(false);
  expect(splitBuildManifest.failures).toContain('cohort_gameplay_build_identity_mismatch');
  const requiredWebInvocation = [
    'Web persona trace refusal and input-ledger contract vectors',
    'DeanTakahashi records a real missed-rise Basin playthrough',
    'EazySpeezy records a legal Basin clear through real Web input',
    'Generated seed-5 Capbage HIDE roundtrip uses strict Web player observations',
    'Static Capbage-green source cannot self-attest a suppressed Web result pulse',
  ].flatMap((title) => [0, 1].map((repeatEachIndex) => ({ title, repeatEachIndex })));
  expect(isRequiredBasinInvocation(requiredWebInvocation),
    'the complete release spec preserves the exact 2x2 trace cohort plus veto tests')
    .toBe(true);
  expect(isRequiredBasinInvocation(requiredWebInvocation.filter((entry) =>
    entry.title !== 'EazySpeezy records a legal Basin clear through real Web input')),
    'extra release tests cannot make a filtered persona cohort attestable').toBe(false);
  expect(isRequiredBasinInvocation(requiredWebInvocation.filter((entry) =>
    entry.title !== 'Static Capbage-green source cannot self-attest a suppressed Web result pulse')),
    'a persona-only filter cannot bypass a required non-persona veto test').toBe(false);

  const deanVisibleChoiceVector = {
    schema: 'player_observation_v1', source: 'player_observable', tick: 1, capture_serial: 1,
    state: {
      affordances: [
        {
          token: 'ordinary-floor', kind: 'move',
          consequence: 'RISK: RISING BASIN SWEEP // WALK ROUTE',
          screen: [420, 420],
        },
        {
          token: 'visible-ladder-route', kind: 'move', consequence: 'ROUTE VIA LADDER',
          screen: [620, 420],
        },
        {
          token: 'visible-portal-route', kind: 'move', consequence: 'ROUTE VIA PORTAL',
          screen: [720, 420],
        },
      ],
      viewport_bins: {
        middle_center: ['ordinary-floor', 'visible-ladder-route', 'visible-portal-route'],
      },
      cues: [],
    },
  };
  for (let runIndex = 0; runIndex < 12; runIndex += 1) {
    expect(chooseDeanUnmarkedGround(deanVisibleChoiceVector, runIndex)?.token,
      `Dean repeat ${runIndex} keeps an arbitrary decision on visibly sweep-risky ground`)
      .toBe('ordinary-floor');
  }
  expect(contractPredicateMatches(DEAN_ATTEMPT_EXPECTED, {
    status: 'arrived', accepted: true,
  }), 'Dean attempt policy accepts a successful whole-party Rally').toBe(true);
  expect(contractPredicateMatches(DEAN_ATTEMPT_EXPECTED, {
    status: 'refused', accepted: false,
  }), 'Dean attempt policy accepts a visible whole-party refusal').toBe(true);
  expect(contractPredicateMatches(DEAN_ATTEMPT_EXPECTED, {
    status: 'mixed_group_result', accepted: false,
  }), 'Dean attempt policy never accepts a mixed group result').toBe(false);

  // Contract vector: a group receipt is derived from the exact roster in the production event,
  // not from the test's intended-member claim or a substring search. This is intentionally built
  // through the opaque browser ledger boundary used by the real journey.
  let consoleListener = null;
  const contractLedger = captureProductionEvents({
    on: (eventName, listener) => {
      if (eventName === 'console') consoleListener = listener;
    },
  });
  const emitConsoleEvent = (kind, payload = {}) => consoleListener({
    text: () => `[EVENT t= 1.00] ${kind} ${JSON.stringify(payload)}`,
  });
  const emitProductionEvent = (members) => emitConsoleEvent('rally_members', {
    members, target: [0, 0, 0], destinations: [],
  });
  let contractInputCount = 0;
  const contractInputLedger = capturePlayerInput({
    keyboard: {
      press: async () => { contractInputCount += 1; },
      down: async () => { contractInputCount += 1; },
      up: async () => { contractInputCount += 1; },
    },
    mouse: {
      move: async () => { contractInputCount += 1; },
      down: async () => { contractInputCount += 1; },
      up: async () => { contractInputCount += 1; },
      click: async () => { contractInputCount += 1; },
    },
  });
  const contractHeldAction = (captureSerial) => {
    const inputObservation = contractPlayerObservation(captureSerial);
    const choice = personaPolicyAffordance(
      inputObservation,
      observedAffordanceFromObservation(inputObservation, 'ordinary-floor'),
      'contract pointer choice',
    );
    return authorizePersonaAction(contractInputLedger, inputObservation, choice, {
      gesture: 'pointer_hold', button: 'right', targetToken: choice.token,
    }, 'contract pointer choice');
  };

  const renamedDriver = contractInputLedger;
  const directDispatchCount = contractInputCount;
  await expect(renamedDriver.press('h', 'visible_h_hide_control'),
    `${UNGUARDED_PERSONA_INPUT_DISPATCH}: aliases cannot bypass action authorization`)
    .rejects.toThrow(/observation-derived action capability/);
  expect(contractInputCount,
    'rejected alias dispatch reaches neither Playwright nor the mechanical input ledger')
    .toBe(directDispatchCount);

  const targetSwapObservation = contractPlayerObservation(14);
  targetSwapObservation.state.affordances.push({
    token: 'visible-ladder-route', kind: 'move', verb: 'MOVE',
    consequence: 'ROUTE VIA LADDER', screen: [620, 420],
  });
  targetSwapObservation.state.visible_affordance_consequences = [
    'ROUTE VIA LADDER', 'WALK ROUTE',
  ];
  targetSwapObservation.state.viewport_bins.middle_center.push('visible-ladder-route');
  expect(validatePlayerObservation(targetSwapObservation),
    'the private-choice mutation starts from one valid player observation').toEqual([]);
  const ordinaryBrandedChoice = personaPolicyAffordance(
    targetSwapObservation,
    observedAffordanceFromObservation(targetSwapObservation, 'ordinary-floor'),
    'ordinary observation choice',
  );
  const ladderBrandedChoice = personaPolicyAffordance(
    targetSwapObservation,
    observedAffordanceFromObservation(targetSwapObservation, 'visible-ladder-route'),
    'alternate observation choice',
  );
  let privateReadCount = 0;
  const privateOraclePage = {
    evaluate: async () => {
      privateReadCount += 1;
      return { anchors: { preferred: 'visible-ladder-route' } };
    },
  };
  await expect(bridgeState(privateOraclePage),
    'private bridge state cannot choose between already observation-branded targets')
    .rejects.toThrow(/post-choice assertion oracle/);
  expect(privateReadCount, 'a pre-choice private read is rejected before page.evaluate').toBe(0);
  const fixedChoiceCapability = authorizePersonaAction(
    contractInputLedger, targetSwapObservation, ordinaryBrandedChoice, {
      gesture: 'pointer_hold', button: 'right', targetToken: ordinaryBrandedChoice.token,
    }, 'fixed observation choice',
  );
  const fixedChoiceOracle = postChoiceAssertionOracle(fixedChoiceCapability);
  expect(await bridgeState(privateOraclePage, fixedChoiceOracle),
    'private bridge data remains available as a post-choice assertion oracle')
    .toEqual({ anchors: { preferred: 'visible-ladder-route' } });
  expect(() => authorizePersonaAction(
    contractInputLedger, targetSwapObservation, ladderBrandedChoice, {
      gesture: 'pointer_hold', button: 'right', targetToken: ladderBrandedChoice.token,
    }, 'private-driven alternate choice',
  ), 'one observation cannot mint a second capability after a private oracle read')
    .toThrow(/only one fixed persona action choice/);
  const targetSwapInputCount = contractInputCount;
  await expect(contractInputLedger.pointerDown(
    'right', ladderBrandedChoice.token, fixedChoiceCapability,
  ), 'a fixed capability cannot dispatch the private oracle\'s preferred alternate target')
    .rejects.toThrow(/different visible target token/);
  expect(contractInputCount,
    'the private-driven target substitution reaches neither Playwright nor the input ledger')
    .toBe(targetSwapInputCount);

  const exactMarker = contractLedger.mark();
  const exactInputMarker = contractInputLedger.mark();
  const exactInputCapability = contractHeldAction(10);
  await contractInputLedger.pointerDown('right', 'ordinary-floor', exactInputCapability);
  await contractInputLedger.pointerUp('right', 'ordinary-floor', exactInputCapability);
  emitProductionEvent(PARTY);
  const exactReceipt = first.keyboardPointerReceipt({
    verb: 'rally',
    consoleEvents: contractLedger.after(exactMarker),
    inputEvents: contractInputLedger.after(exactInputMarker),
    intendedMembers: PARTY,
    targetToken: 'ordinary-floor',
    input: 'contract vector',
  });
  expect(exactReceipt.atomic_group,
    'one production group event with the exact roster is atomic').toBe(true);
  expect(exactReceipt.member_results,
    'the exact roster accepts every intended member').toEqual({
    aster: 'accepted', peris: 'accepted', endo: 'accepted',
  });

  const omittedMarker = contractLedger.mark();
  const omittedInputMarker = contractInputLedger.mark();
  const omittedInputCapability = contractHeldAction(11);
  await contractInputLedger.pointerDown('right', 'ordinary-floor', omittedInputCapability);
  await contractInputLedger.pointerUp('right', 'ordinary-floor', omittedInputCapability);
  emitProductionEvent(['aster', 'peris']);
  const omittedReceipt = first.keyboardPointerReceipt({
    verb: 'rally',
    consoleEvents: contractLedger.after(omittedMarker),
    inputEvents: contractInputLedger.after(omittedInputMarker),
    intendedMembers: PARTY,
    targetToken: 'ordinary-floor',
    input: 'contract vector',
  });
  expect(omittedReceipt.atomic_group,
    'a production group event that omits one intended member is not atomic').toBe(false);
  expect(omittedReceipt.member_results.endo,
    'the omitted member is independently classified as refused').toBe('refused');

  const observation = contractPlayerObservation(1);
  const unknownPortraitObservation = structuredClone(observation);
  unknownPortraitObservation.state.hud.portraits.push({
    token: 'portrait-3', label: 'marco', visible: true, downed: true, selected: false,
  });
  let unknownPortraitKeyPresses = 0;
  const unknownPortraitReceipt = await selectFullVisiblePartyFromPortraits({
    press: async () => { unknownPortraitKeyPresses += 1; },
  }, unknownPortraitObservation);
  expect(visibleSubjectIds(unknownPortraitObservation),
    'presentation intent retains every visible portrait, including a downed/unbound fourth member')
    .toEqual(['aster', 'endo', 'marco', 'peris']);
  expect(visibleRosterTokens(unknownPortraitObservation),
    'the opaque Rally roster also retains every visible portrait token, including downed members')
    .toEqual(['portrait-0', 'portrait-1', 'portrait-2', 'portrait-3']);
  expect(unknownPortraitReceipt,
    'an unbound visible portrait fails the whole selection closed without shrinking the roster')
    .toMatchObject({
      accepted: false,
      status: 'refused',
      inputIssued: false,
      expected: ['aster', 'endo', 'marco', 'peris'],
      unboundMembers: ['marco'],
    });
  expect(unknownPortraitKeyPresses,
    'the fail-closed selection emits no partial number-key sequence').toBe(0);
  const duplicatePortraitObservation = structuredClone(observation);
  duplicatePortraitObservation.state.hud.portraits.push({
    token: 'portrait-duplicate', label: 'Aster', visible: true, downed: true, selected: false,
  });
  let duplicatePortraitKeyPresses = 0;
  const duplicatePortraitReceipt = await selectFullVisiblePartyFromPortraits({
    press: async () => { duplicatePortraitKeyPresses += 1; },
  }, duplicatePortraitObservation);
  expect(duplicatePortraitReceipt,
    'a duplicate visible subject identity invalidates the whole roster before selection input')
    .toMatchObject({
      accepted: false,
      status: 'refused',
      inputIssued: false,
      duplicateMembers: ['aster'],
    });
  expect(duplicatePortraitKeyPresses,
    'duplicate presentation identities cannot produce a partial selection gesture').toBe(0);
  const currentCueSchemaObservation = structuredClone(observation);
  currentCueSchemaObservation.state.cues.push(
    {
      kind: 'rally', state: 'holding', text: 'RALLY', progress: 0.5,
      screen: [400, 300], visible: true,
    },
    {
      kind: 'consequence', source_token: 'portrait-0', phase: 'active',
      label: 'SWEPT', destination_label: 'START / CURRENT RETURN',
      text: 'SWEPT // START / CURRENT RETURN', progress: 0.5, visible: true,
    },
    {
      kind: 'interaction_result', source_token: 'affordance-1',
      presentation_serial: 2, result: 'success', screen: [420, 300], visible: true,
    },
  );
  expect(validatePlayerObservation(currentCueSchemaObservation),
    'Web observation validation accepts every current shared cue field').toEqual([]);
  const backgroundEventMarker = contractLedger.mark();
  PARTY.forEach((subject) => emitConsoleEvent('begin_external_traversal', {
    id: subject,
    traversal_id: `private-sweep/${subject}`,
    presentation_receipt: {
      scope: 'player_facing', event_id: 'private-event', label: 'SWEPT',
      destination_label: 'START / CURRENT RETURN',
    },
  }));
  const backgroundEvents = contractLedger.after(backgroundEventMarker);
  const backgroundRosterTokens = observation.state.hud.portraits.map(({ token }) => token);
  const backgroundActiveObservation = structuredClone(observation);
  backgroundActiveObservation.tick = 2;
  backgroundActiveObservation.capture_serial = 2;
  backgroundActiveObservation.state.cues.push(...backgroundRosterTokens.map((sourceToken) => ({
    kind: 'consequence', source_token: sourceToken, phase: 'active', label: 'SWEPT',
    destination_label: 'START / CURRENT RETURN',
    text: 'SWEPT // START / CURRENT RETURN', progress: 0.5, visible: true,
  })));
  const backgroundArrivalObservation = structuredClone(observation);
  backgroundArrivalObservation.tick = 3;
  backgroundArrivalObservation.capture_serial = 3;
  backgroundArrivalObservation.state.cues.push(...backgroundRosterTokens.map((sourceToken) => ({
    kind: 'consequence', source_token: sourceToken, phase: 'arrival', label: 'SWEPT',
    destination_label: 'START / CURRENT RETURN',
    text: 'ARRIVED // SWEPT // START / CURRENT RETURN', progress: 1.0, visible: true,
  })));
  const backgroundValidation = validateBackgroundEventPresentation({
    observationBefore: observation,
    observationAfter: backgroundArrivalObservation,
    observationSamples: [backgroundActiveObservation],
    consoleEvents: backgroundEvents,
    expectedRosterTokens: backgroundRosterTokens,
    expectedLabel: 'SWEPT',
    expectedDestination: 'START / CURRENT RETURN',
  });
  expect(backgroundValidation,
    'validation-only EventLog evidence binds every traversal to rendered opaque portrait cues')
    .toMatchObject({
      ok: true,
      event_count: PARTY.length,
      event_kinds: PARTY.map(() => 'begin_external_traversal'),
      causal_cue_delta_visible: true,
      player_facing_traversal_count: PARTY.length,
      subject_lineages: backgroundRosterTokens.map((sourceToken) => ({
        source_tokens: [sourceToken],
        label: 'SWEPT',
        destination_label: 'START / CURRENT RETURN',
        active_visible: true,
        arrival_visible: true,
      })),
      failures: [],
    });
  const backgroundWaitReceipt = first.observedInputReceipt({
    verb: 'wait', input: 'no input', boundary: 'player_command', backgroundValidation,
  });
  expect(backgroundWaitReceipt,
    'a passive wait keeps production input empty while preserving background validation')
    .toMatchObject({
      production_event_count: 0,
      production_event_kinds: [],
      validation_background_event_count: PARTY.length,
      validation_background_event_kinds: PARTY.map(() => 'begin_external_traversal'),
      validation_background_visual_lineage: { ok: true },
    });
  const persistedBackgroundProof = JSON.stringify({
    validation_background_event_kinds:
      backgroundWaitReceipt.validation_background_event_kinds,
    validation_background_visual_lineage:
      backgroundWaitReceipt.validation_background_visual_lineage,
  });
  for (const privateValue of [...PARTY, 'private-event', 'private-sweep', 'event_id', 'traversal_id']) {
    expect(persistedBackgroundProof,
      `background proof never persists private identifier ${privateValue}`).not.toContain(privateValue);
  }
  const missingArrivalBackgroundValidation = validateBackgroundEventPresentation({
    observationBefore: observation,
    observationAfter: backgroundActiveObservation,
    observationSamples: [],
    consoleEvents: backgroundEvents,
    expectedRosterTokens: backgroundRosterTokens,
    expectedLabel: 'SWEPT',
    expectedDestination: 'START / CURRENT RETURN',
  });
  expect(missingArrivalBackgroundValidation.failures,
  'a background traversal cannot pass on active feedback without a rendered arrival')
    .toContain('background_traversal_arrival_cue_missing');
  expect(() => first.observedInputReceipt({
    verb: 'wait', input: 'no input', boundary: 'player_command',
    backgroundValidation: missingArrivalBackgroundValidation,
  }), 'failed background presentation proof cannot be persisted in a trace receipt')
    .toThrow(/failed background presentation validation/i);
  const exactVisibleTextObservation = structuredClone(observation);
  exactVisibleTextObservation.state.affordances = [
    {
      token: 'route-a', kind: 'move', verb: 'MOVE',
      consequence: 'ROUTE VIA LADDER', screen: [400, 300],
    },
    {
      token: 'route-b', kind: 'move', verb: 'MOVE',
      consequence: 'ROUTE VIA LADDER', screen: [420, 300],
    },
    {
      token: 'shelter', kind: 'interact', verb: 'REST PARTY',
      consequence: 'Shelter', screen: [440, 300],
    },
  ];
  exactVisibleTextObservation.state.visible_affordance_verbs = ['MOVE', 'REST PARTY'];
  exactVisibleTextObservation.state.visible_affordance_consequences = [
    'ROUTE VIA LADDER', 'Shelter',
  ];
  expect(validatePlayerObservation(exactVisibleTextObservation),
    'policy text lists are sorted, de-duplicated, and derived from visible affordances')
    .toEqual([]);
  const staleVisibleTextObservation = structuredClone(exactVisibleTextObservation);
  staleVisibleTextObservation.state.visible_affordance_verbs = ['REST PARTY', 'MOVE'];
  expect(validatePlayerObservation(staleVisibleTextObservation),
    'an index-order-derived policy list cannot pass the observation contract')
    .toContain('observation.state.visible_affordance_verbs must be the sorted exact visible verb list');
  const routeStatusObservation = contractPlayerObservation(14);
  routeStatusObservation.state.cues.push({
    kind: 'movement_result', target_token: 'ordinary-floor',
    subjects: ['portrait-0', 'portrait-1', 'portrait-2'],
    phase: 'progress', progress: 0.35, accepted: true, reason: '',
    presentation_serial: 1, visible: true,
    route_status: 'cooperative_hold', route_status_serial: 1,
    route_status_subjects: ['portrait-1'], route_status_remaining_seconds: 0.6,
  });
  expect(validatePlayerObservation(routeStatusObservation),
    'Web accepts the exact visible cooperative-hold fields emitted by the shared observer')
    .toEqual([]);
  const normalizedRouteStatusSamples = normalizeObservationSamples([
    routeStatusObservation, structuredClone(routeStatusObservation),
  ]);
  expect(normalizedRouteStatusSamples,
    'browser trace normalization preserves the visible route-state bundle while de-duplicating it')
    .toHaveLength(1);
  expect(normalizedRouteStatusSamples[0].state.cues.at(-1)).toMatchObject({
    route_status: 'cooperative_hold', route_status_serial: 1,
    route_status_subjects: ['portrait-1'], route_status_remaining_seconds: 0.6,
  });
  const reformingRouteObservation = structuredClone(routeStatusObservation);
  Object.assign(reformingRouteObservation.state.cues.at(-1), {
    route_status: 'reforming_route', route_status_serial: 2,
    route_status_subjects: ['portrait-0'], route_status_remaining_seconds: 0,
  });
  expect(validatePlayerObservation(reformingRouteObservation),
    'Web accepts the exact visible reforming-route transition that explains a replan')
    .toEqual([]);
  const impossibleReformingObservation = structuredClone(reformingRouteObservation);
  impossibleReformingObservation.state.cues.at(-1).route_status_remaining_seconds = 0.4;
  expect(validatePlayerObservation(impossibleReformingObservation),
    'a reforming-route transition cannot masquerade as an unrelated countdown')
    .toContain('observation.state.cues.3.route_status_remaining_seconds must be zero while reforming');
  const clearedRouteStatusObservation = structuredClone(routeStatusObservation);
  Object.assign(clearedRouteStatusObservation.state.cues.at(-1), {
    route_status: '', route_status_subjects: [], route_status_remaining_seconds: 0,
  });
  expect(validatePlayerObservation(clearedRouteStatusObservation),
    'a cleared status may retain its monotonic serial while exposing no subjects or countdown')
    .toEqual([]);
  const legacyMovementObservation = structuredClone(routeStatusObservation);
  for (const key of [
    'route_status', 'route_status_serial', 'route_status_subjects',
    'route_status_remaining_seconds',
  ]) delete legacyMovementObservation.state.cues.at(-1)[key];
  expect(validatePlayerObservation(legacyMovementObservation),
    'legacy movement-result cues remain valid only when the route-status bundle is wholly absent')
    .toEqual([]);
  const partialRouteStatusObservation = structuredClone(routeStatusObservation);
  delete partialRouteStatusObservation.state.cues.at(-1).route_status_remaining_seconds;
  expect(validatePlayerObservation(partialRouteStatusObservation),
    'a partial route-status bundle cannot become Web persona evidence')
    .toContain('observation.state.cues.3 route-status fields must be present together');
  const unrelatedRouteStatusObservation = structuredClone(legacyMovementObservation);
  unrelatedRouteStatusObservation.state.cues.push({
    kind: 'status', text: 'COOPERATIVE HOLD', visible: true,
    route_status: 'cooperative_hold', route_status_serial: 1,
    route_status_subjects: ['portrait-1'], route_status_remaining_seconds: 0.6,
  });
  expect(validatePlayerObservation(unrelatedRouteStatusObservation),
    'route liveness metadata cannot be forged on an unrelated visible cue')
    .toContain('observation.state.cues.4 route-status fields require a movement_result cue');
  const foreignRouteSubjectObservation = structuredClone(routeStatusObservation);
  foreignRouteSubjectObservation.state.cues.at(-1).route_status_subjects = ['portrait-forged'];
  expect(validatePlayerObservation(foreignRouteSubjectObservation),
    'route liveness must bind a visible portrait from the exact movement subject roster')
    .toEqual(expect.arrayContaining([
      'observation.state.cues.3.route_status_subjects must be a subset of movement subjects',
      'observation.state.cues.3.route_status_subjects must contain only visible portrait tokens',
    ]));
  const zeroHoldObservation = structuredClone(routeStatusObservation);
  zeroHoldObservation.state.cues.at(-1).route_status_remaining_seconds = 0;
  expect(validatePlayerObservation(zeroHoldObservation),
    'an active cooperative hold cannot falsely render a zero-second countdown')
    .toContain('observation.state.cues.3.route_status_remaining_seconds must be positive during a cooperative hold');
  const wholeRefusalMarker = contractLedger.mark();
  const wholeRefusalInputMarker = contractInputLedger.mark();
  const wholeRefusalInputCapability = contractHeldAction(12);
  await contractInputLedger.pointerDown(
    'right', 'ordinary-floor', wholeRefusalInputCapability,
  );
  await contractInputLedger.pointerUp('right', 'ordinary-floor', wholeRefusalInputCapability);
  const wholeRefusalReceipt = first.keyboardPointerReceipt({
    verb: 'rally',
    consoleEvents: contractLedger.after(wholeRefusalMarker),
    inputEvents: contractInputLedger.after(wholeRefusalInputMarker),
    intendedMembers: PARTY,
    targetToken: 'ordinary-floor',
    input: 'contract vector',
  });
  expect(wholeRefusalReceipt.status, 'zero production events receipt the whole-group refusal')
    .toBe('refused');
  expect(wholeRefusalReceipt.atomic_group,
    'a zero-event refusal keeps the exact intended roster atomic').toBe(true);
  expect(wholeRefusalReceipt.member_results,
    'a whole-group refusal refuses every intended member').toEqual({
    aster: 'refused', peris: 'refused', endo: 'refused',
  });
  expect(inputSequenceProgressionReasons([], { input_receipt: omittedReceipt }),
    'the first active decision cannot start after an unrecorded input gap').toEqual([
    'input_event_sequence_gap_across_decisions',
  ]);
  expect(inputSequenceProgressionReasons([
    { input_receipt: exactReceipt },
    { input_receipt: { boundary: 'player_command', input_issued: false } },
  ], { input_receipt: omittedReceipt }),
  'a passive wait neither consumes nor resets the active input sequence').toEqual([]);
  expect(inputSequenceProgressionReasons([
    { input_receipt: omittedReceipt },
  ], { input_receipt: exactReceipt }),
  'an active decision cannot reuse an earlier decision input range').toEqual([
    'input_event_sequence_reused_across_decisions',
  ]);
  const emptyInputMarker = contractInputLedger.mark();
  expect(() => first.keyboardPointerReceipt({
    verb: 'rally',
    consoleEvents: contractLedger.after(wholeRefusalMarker),
    inputEvents: contractInputLedger.after(emptyInputMarker),
    intendedMembers: PARTY,
    input: 'forged empty input',
  }), 'an empty opaque ledger slice cannot attest a player action').toThrow(/mechanically issued/);
  expect(() => first.observedInputReceipt({
    verb: 'select_party', boundary: 'keyboard_pointer', input: 'constructor only',
  }), 'a constructor-only active receipt cannot attest a player action').toThrow(/opaque/);
  expect(() => first.observedInputReceipt({
    verb: 'select_party', boundary: 'controller', input: 'inactive boundary',
  }), 'Web active receipts cannot claim an unexercised controller boundary').toThrow(/keyboard_pointer/);
  const chordInputMarker = contractInputLedger.mark();
  const chordObservation = contractPlayerObservation(13);
  const chordCapability = authorizeObservationPlayerAction(
    contractInputLedger, chordObservation, {
      gesture: 'key_press',
      choice: chordObservation.state.hud.portraits[1],
      key: 'Control+2',
      targetToken: 'hud_portraits',
    },
  );
  await contractInputLedger.press('Control+2', 'hud_portraits', chordCapability);
  const chordInputEvents = contractInputLedger.after(chordInputMarker);
  expect(chordInputEvents.map(({ kind, key, pressed, modifiers }) => ({
    kind, key, pressed, modifiers,
  })), 'Ctrl-add is recorded as one shared key down/up gesture with explicit modifiers')
    .toEqual([
      {
        kind: 'key', key: 'Digit2', pressed: true,
        modifiers: { ctrl: true, shift: false, alt: false, meta: false },
      },
      {
        kind: 'key', key: 'Digit2', pressed: false,
        modifiers: { ctrl: true, shift: false, alt: false, meta: false },
      },
    ]);
  expect(validateMechanicalInputEvents(chordInputEvents),
    'the shared mechanical event validator accepts the real Ctrl-add ledger slice').toEqual([]);
  expect(validateMechanicalInputEvents([
    { sequence: 0, kind: 'key_press', key: '2', issued: true },
  ]), 'zero-based browser-specific event shapes fail closed before trace emission')
    .toEqual(expect.arrayContaining([
      'input_events.0.sequence_or_issued_invalid',
    ]));
  expect(validateMechanicalInputEvents([
    {
      sequence: 1, kind: 'key', key: 'Digit2', pressed: true, issued: true,
      modifiers: { ctrl: true, shift: false },
    },
  ]), 'missing explicit modifiers cannot be admitted as mechanical input evidence')
    .toEqual(expect.arrayContaining([
      'input_events.0.modifiers.alt_invalid',
      'input_events.0.modifiers.meta_invalid',
    ]));
  expect(contractInputCount,
    'the positive contract receipts mechanically issue their fake Playwright input methods').toBe(7);
  const movementSubjects = PARTY.map((_, index) => `portrait-${index}`);
  const movementCue = (phase, accepted, reason = '') => ({
    kind: 'movement_result', target_token: 'ordinary-floor',
    subjects: movementSubjects, phase, accepted, reason,
    presentation_serial: 1, visible: true,
  });
  const acceptedObservation = structuredClone(observation);
  acceptedObservation.tick = 2;
  acceptedObservation.capture_serial = 2;
  acceptedObservation.state.cues.push(movementCue('accepted', true));
  const progressObservation = structuredClone(observation);
  progressObservation.tick = 3;
  progressObservation.capture_serial = 3;
  progressObservation.state.cues = progressObservation.state.cues.map((cue, index) => ({
    ...cue, screen: [cue.screen[0] + 8 + index, cue.screen[1]],
  }));
  progressObservation.state.cues.push(movementCue('progress', true));
  const afterObservation = structuredClone(observation);
  afterObservation.tick = 4;
  afterObservation.capture_serial = 4;
  afterObservation.state.cues = afterObservation.state.cues.map((cue, index) => ({
    ...cue, screen: [cue.screen[0] + 20 + index, cue.screen[1]],
  }));
  afterObservation.state.cues.push(movementCue('arrival', true));
  const interruptedObservation = structuredClone(afterObservation);
  interruptedObservation.state.cues = interruptedObservation.state.cues
    .filter((cue) => cue.kind !== 'movement_result');
  interruptedObservation.state.cues.push(movementCue(
    'interrupted', true,
    'RALLY INTERRUPTED // SWEPT BY RISING BASIN stopped the party before the shown destination.',
  ));
  const silentInterruptedObservation = structuredClone(interruptedObservation);
  silentInterruptedObservation.state.cues = silentInterruptedObservation.state.cues.map((cue) =>
    (cue.kind === 'movement_result' ? { ...cue, reason: '' } : cue));
  const lateArrivalObservation = structuredClone(afterObservation);
  lateArrivalObservation.tick = 5;
  lateArrivalObservation.capture_serial = 5;
  const refusalAfterObservation = structuredClone(observation);
  refusalAfterObservation.tick = 2;
  refusalAfterObservation.capture_serial = 2;
  refusalAfterObservation.state.cues.push(
    movementCue('refused', false, 'NO ROUTE // WHOLE PARTY REFUSED'),
    { kind: 'status', text: 'NO ROUTE // WHOLE PARTY REFUSED', visible: true },
  );

  const cameraAfterObservation = structuredClone(observation);
  cameraAfterObservation.tick = 2;
  cameraAfterObservation.capture_serial = 2;
  cameraAfterObservation.state.cues = cameraAfterObservation.state.cues.map((cue) => (
    cue.kind === 'party_body'
      ? { ...cue, screen: [cue.screen[0] + 12, cue.screen[1] + 4] }
      : cue
  ));
  const pairedInput = (kind, detail) => [
    {
      sequence: 1, kind, ...detail, pressed: true, issued: true,
      ...(kind === 'key' ? { modifiers: {
        ctrl: false, shift: false, alt: false, meta: false,
      } } : {}),
    },
    {
      sequence: 2, kind, ...detail, pressed: false, issued: true,
      ...(kind === 'key' ? { modifiers: {
        ctrl: false, shift: false, alt: false, meta: false,
      } } : {}),
    },
  ];
  const cameraCases = [
    ['camera_pan', pairedInput('key', { key: 'KeyW' })],
    ['camera_recenter', pairedInput('key', { key: 'Home' })],
    ['camera_rotate', pairedInput('key', { key: 'KeyQ' })],
    ['camera_zoom', pairedInput('pointer_button', { button: 5 })],
  ];
  const cameraRecords = cameraCases.map(([verb, inputEvents]) => {
    const decision = {
      verb, world_change: false, group_verb: false, intended_subjects: [],
      target: { kind: 'visible_control', token: verb },
    };
    const inputReceipt = {
      receipt_id: `fixture-${verb}`,
      boundary: 'keyboard_pointer', status: 'accepted', player_reproducible: true,
      verb, atomic_group: false, production_event_count: 0,
      production_event_kinds: [], input_issued: true,
      input_event_count: inputEvents.length, input_sequence_before: 0,
      input_sequence_after: inputEvents.length, input_events: inputEvents,
      observation_before_capture_serial: observation.capture_serial,
      first_post_input_capture_serial: cameraAfterObservation.capture_serial,
      input_target_token: verb,
    };
    const derived = deriveDecisionArtifacts({
      observationBefore: observation, observationAfter: cameraAfterObservation,
      observationSamples: [], decision, inputReceipt,
    });
    return {
      observation_before: observation,
      observation_after: cameraAfterObservation,
      observation_samples: [],
      rationale: { text: `Recover presentation with ${verb}.` },
      decision,
      input_receipt: inputReceipt,
      feedback: derived.feedback,
      outcome: derived.outcome,
      evidence_context: {
        authored_state: true, fixture_quarantine: false,
        evidence_baseline_id: 'camera-presentation-contract',
      },
    };
  });
  for (const cameraRecord of cameraRecords) {
    expect(validateDecisionRecord(cameraRecord),
      `${cameraRecord.decision.verb} has an exact semantic verb and mechanical packet`).toEqual([]);
    expect(classifyEvidence(cameraRecord),
      `${cameraRecord.decision.verb} is reproducible presentation evidence but cannot promote gameplay`)
      .toMatchObject({
        player_reproducible: true,
        eligible_for_learning: false,
        rejection_reasons: ['presentation_recovery_not_gameplay_learning_candidate'],
      });
    expect(cameraRecord.outcome.world_causal_evidence,
      `${cameraRecord.decision.verb} cannot satisfy a gameplay outcome predicate`).toBe(false);
  }

  const multiSelectedBefore = structuredClone(observation);
  multiSelectedBefore.state.hud.portraits.forEach((portrait) => { portrait.selected = true; });
  const asterSingleAfter = structuredClone(multiSelectedBefore);
  asterSingleAfter.tick = 2;
  asterSingleAfter.capture_serial = 2;
  asterSingleAfter.state.hud.portraits.forEach((portrait) => {
    portrait.selected = portrait.label === 'aster';
  });
  const selectionPair = (sequenceBefore, key, ctrl) => [
    {
      sequence: sequenceBefore + 1, kind: 'key', key, pressed: true, issued: true,
      modifiers: { ctrl, shift: false, alt: false, meta: false },
    },
    {
      sequence: sequenceBefore + 2, kind: 'key', key, pressed: false, issued: true,
      modifiers: { ctrl, shift: false, alt: false, meta: false },
    },
  ];
  const ctrlOffEvents = [
    ...selectionPair(0, 'Digit2', true),
    ...selectionPair(2, 'Digit3', true),
  ];
  const makeSelectSingleRecord = (
    inputEvents, resultObservation = asterSingleAfter, target = 'aster',
  ) => {
    const targetToken = multiSelectedBefore.state.hud.portraits.find(
      (portrait) => portrait.label === target,
    )?.token ?? '';
    const decision = {
      verb: 'select_single', world_change: false, group_verb: false,
      intended_subjects: [target], target: { token: targetToken },
    };
    const inputReceipt = {
      receipt_id: `fixture-select-single-${target}`,
      boundary: 'keyboard_pointer', status: 'accepted', player_reproducible: true,
      verb: 'select_single', atomic_group: false, production_event_count: 0,
      production_event_kinds: [], input_issued: true,
      input_event_count: inputEvents.length, input_sequence_before: 0,
      input_sequence_after: inputEvents.length, input_events: inputEvents,
      observation_before_capture_serial: multiSelectedBefore.capture_serial,
      first_post_input_capture_serial: resultObservation.capture_serial,
      input_target_token: targetToken,
    };
    const derived = deriveDecisionArtifacts({
      observationBefore: multiSelectedBefore, observationAfter: resultObservation,
      observationSamples: [], decision, inputReceipt,
    });
    return {
      observation_before: multiSelectedBefore,
      observation_after: resultObservation,
      observation_samples: [],
      rationale: { text: 'Keep Aster selected and Ctrl-toggle the selected siblings off.' },
      decision,
      input_receipt: inputReceipt,
      feedback: derived.feedback,
      outcome: derived.outcome,
      evidence_context: {
        authored_state: true, fixture_quarantine: false,
        evidence_baseline_id: 'select-single-human-chord-contract',
      },
    };
  };
  const validCtrlOffSelection = makeSelectSingleRecord(ctrlOffEvents);
  expect(classifyEvidence(validCtrlOffSelection).eligible_for_learning,
    'Web evidence accepts the human full-group to singleton Ctrl-toggle-off chord').toBe(true);
  expect(classifyEvidence(makeSelectSingleRecord(ctrlOffEvents.slice(0, 2))).rejection_reasons,
    'Web singleton evidence rejects a missing selected-sibling key pair')
    .toContain('select_single_subject_key_pair_missing');
  const unmodifiedSiblingEvents = structuredClone(ctrlOffEvents);
  unmodifiedSiblingEvents.slice(0, 2).forEach((event) => { event.modifiers.ctrl = false; });
  expect(classifyEvidence(makeSelectSingleRecord(unmodifiedSiblingEvents)).rejection_reasons,
    'Web singleton evidence rejects an unmodified sibling pair')
    .toContain('select_single_subject_key_pair_missing');
  const extraTargetKeyEvents = [
    ...ctrlOffEvents,
    ...selectionPair(ctrlOffEvents.length, 'Digit1', false),
  ];
  expect(classifyEvidence(makeSelectSingleRecord(extraTargetKeyEvents)).rejection_reasons,
    'Web singleton evidence rejects an extra retained-target key pair')
    .toContain('select_single_subject_key_pair_missing');
  const nonSingletonAfter = structuredClone(asterSingleAfter);
  nonSingletonAfter.state.hud.portraits[1].selected = true;
  expect(classifyEvidence(makeSelectSingleRecord(
    ctrlOffEvents, nonSingletonAfter,
  )).rejection_reasons, 'Web singleton evidence rejects a non-singleton visible result')
    .toContain('select_single_subject_key_pair_missing');

  const legacyBeforeAlias = {
    ...structuredClone(cameraRecords[0]),
    observation: structuredClone(cameraRecords[0].observation_before),
  };
  expect(validateDecisionRecord(legacyBeforeAlias),
    'the legacy top-level observation alias cannot pass the Web validator').toContain(
    'legacy observation is not valid v3 evidence',
  );
  const legacyOutcomeAlias = structuredClone(cameraRecords[0]);
  legacyOutcomeAlias.outcome.observation = structuredClone(
    cameraRecords[0].observation_after,
  );
  expect(validateDecisionRecord(legacyOutcomeAlias),
    'the legacy outcome.observation alias cannot masquerade as writer-derived outcome').toContain(
    'outcome does not match the exact v3 derived outcome',
  );

  const regressedBefore = structuredClone(afterObservation);
  regressedBefore.tick = 3;
  expect(observationProgressionReasons([
    { observation_after: afterObservation },
  ], { observation_before: regressedBefore }),
  'decision traces reject reused captures and clock regressions across actions').toEqual([
    'observation_capture_not_monotonic_across_decisions',
    'observation_tick_regressed_across_decisions',
  ]);
  const makeGroupEvidenceRecord = (
    receipt,
    resultObservation = receipt.status === 'accepted'
      ? afterObservation : refusalAfterObservation,
    resultSamples = receipt.status === 'accepted'
      ? [acceptedObservation, progressObservation] : [],
  ) => {
    const decision = {
      verb: 'rally', world_change: true, group_verb: true,
      intended_subjects: PARTY,
      target: { kind: 'visible_affordance', token: 'ordinary-floor', screen: [420, 420] },
    };
    const boundReceipt = {
      ...receipt,
      observation_before_capture_serial: observation.capture_serial,
      first_post_input_capture_serial:
        (resultSamples[0] ?? resultObservation).capture_serial,
    };
    const derived = deriveDecisionArtifacts({
      observationBefore: observation, observationAfter: resultObservation,
      observationSamples: resultSamples, decision, inputReceipt: boundReceipt,
    });
    return {
      observation_before: observation, observation_after: resultObservation,
      observation_samples: resultSamples, decision, input_receipt: boundReceipt,
      feedback: derived.feedback, outcome: derived.outcome,
      evidence_context: {
        authored_state: true, fixture_quarantine: false,
        evidence_baseline_id: 'web-group-contract',
      },
    };
  };
  const acceptedGroupRecord = makeGroupEvidenceRecord(exactReceipt);
  expect(classifyEvidence(acceptedGroupRecord).eligible_for_learning,
    'an accepted exact-roster group receipt remains eligible').toBe(true);
  expect(movementCandidateDemonstrated(
    acceptedGroupRecord.outcome, acceptedGroupRecord.observation_after,
  ), 'only an exact fresh accepted-progress-arrival lineage demonstrates a movement candidate')
    .toBe(true);
  const interruptedGroupRecord = makeGroupEvidenceRecord(
    exactReceipt, interruptedObservation, [acceptedObservation, progressObservation],
  );
  const interruptedGroupEvidence = classifyEvidence(interruptedGroupRecord);
  expect(interruptedGroupEvidence.eligible_for_learning,
    'an accepted Rally stopped short by a visible cause remains valid decision evidence').toBe(true);
  expect(interruptedGroupRecord.outcome).toMatchObject({
    status: 'accepted', accepted: true,
    movement_result: {
      accepted: true,
      phases: ['accepted', 'progress', 'interrupted'],
      reason: expect.stringContaining('SWEPT BY RISING BASIN'),
    },
  });
  expect(movementCandidateDemonstrated(
    interruptedGroupRecord.outcome, interruptedGroupRecord.observation_after,
  ), 'an accepted-but-interrupted route cannot seed a movement policy node').toBe(false);
  expect(classifyEvidence(makeGroupEvidenceRecord(
    exactReceipt, silentInterruptedObservation, [acceptedObservation, progressObservation],
  )).rejection_reasons,
  'an interrupted movement terminal must state its visible cause').toContain(
    'interrupted_movement_visible_reason_missing',
  );
  expect(classifyEvidence(makeGroupEvidenceRecord(
    exactReceipt, lateArrivalObservation,
    [acceptedObservation, progressObservation, interruptedObservation],
  )).rejection_reasons,
  'an interrupted lineage is terminal and cannot later claim arrival').toContain(
    'movement_result_phase_sequence_invalid',
  );
  expect(classifyEvidence(makeGroupEvidenceRecord(omittedReceipt)).rejection_reasons,
    'mixed accepted/refused group results cannot enter learning').toContain(
    'group_member_result_not_atomic:endo',
  );
  const wholeRefusalRecord = makeGroupEvidenceRecord(
    wholeRefusalReceipt, refusalAfterObservation,
  );
  expect(classifyEvidence(wholeRefusalRecord).eligible_for_learning,
    'a visibly receipted zero-event whole-group refusal remains eligible').toBe(true);
  const driftingRefusalObservation = structuredClone(refusalAfterObservation);
  driftingRefusalObservation.state.cues = driftingRefusalObservation.state.cues.map((cue) => (
    cue.kind === 'party_body'
      ? { ...cue, screen: [cue.screen[0] + 17, cue.screen[1] - 6] }
      : cue
  ));
  const driftingRefusalRecord = makeGroupEvidenceRecord(
    wholeRefusalReceipt, driftingRefusalObservation,
  );
  expect(driftingRefusalRecord.feedback.party_body_movement,
    'camera-relative pixels remain descriptive feedback during a refusal').toMatchObject({
    observed: true,
    classification: 'screen_space_presentation_only',
    subjects: ['body-aster', 'body-endo', 'body-peris'],
  });
  expect(driftingRefusalRecord.outcome.moved_subjects,
    'a rejected command cannot causally claim camera-relative body drift').toEqual([]);
  expect(classifyEvidence(driftingRefusalRecord).eligible_for_learning,
    'descriptive camera drift does not invalidate an exact zero-production refusal').toBe(true);
  const freshPostParkObservation = structuredClone(observation);
  freshPostParkObservation.tick = 3;
  freshPostParkObservation.capture_serial = 3;
  const sampledRefusalRecord = makeGroupEvidenceRecord(
    wholeRefusalReceipt, freshPostParkObservation, [driftingRefusalObservation],
  );
  expect(sampledRefusalRecord.outcome.movement_result.phase_capture_serials.refused,
    'the short refusal remains bound to its in-action capture').toBe(2);
  expect(sampledRefusalRecord.observation_after.capture_serial,
    'pointer parking seals a strictly newer terminal observation').toBe(3);
  expect(sampledRefusalRecord.outcome.moved_subjects,
    'sampled camera drift still cannot become refused-command movement').toEqual([]);
  expect(classifyEvidence(sampledRefusalRecord).eligible_for_learning,
    'the fresh post-park chronology remains valid refusal evidence').toBe(true);
  expect(movementCandidateDemonstrated(
    sampledRefusalRecord.outcome,
    sampledRefusalRecord.observation_after,
    { persona: 'dean_takahashi', inputReceipt: sampledRefusalRecord.input_receipt },
  ), 'Dean may demonstrate a human-visible refusal sample before the fresh terminal capture')
    .toBe(true);
  expect(classifyEvidence(makeGroupEvidenceRecord({
    ...exactReceipt, production_event_count: 0,
  })).rejection_reasons, 'accepted group receipts require one production event').toContain(
    'group_verb_production_event_count_does_not_match_receipt',
  );
  expect(classifyEvidence(makeGroupEvidenceRecord({
    ...exactReceipt,
    status: 'refused',
    member_results: { aster: 'refused', peris: 'refused', endo: 'refused' },
  }, refusalAfterObservation)).rejection_reasons,
  'refused group receipts require zero production events').toContain(
    'group_verb_production_event_count_does_not_match_receipt',
  );

  const recordInputLedger = capturePlayerInput({
    keyboard: { press: async () => {}, down: async () => {}, up: async () => {} },
    mouse: {
      move: async () => {}, down: async () => {}, up: async () => {}, click: async () => {},
    },
  });
  const recordInputMarker = recordInputLedger.mark();
  const recordInputObservation = contractPlayerObservation(30);
  const recordInputChoice = personaPolicyAffordance(
    recordInputObservation,
    observedAffordanceFromObservation(recordInputObservation, 'ordinary-floor'),
    'record contract choice',
  );
  const recordInputCapability = authorizePersonaAction(
    recordInputLedger, recordInputObservation, recordInputChoice, {
      gesture: 'pointer_hold', button: 'right', targetToken: recordInputChoice.token,
    }, 'record contract choice',
  );
  await recordInputLedger.pointerDown('right', 'ordinary-floor', recordInputCapability);
  await recordInputLedger.pointerUp('right', 'ordinary-floor', recordInputCapability);
  const recordProductionMarker = contractLedger.mark();
  emitProductionEvent(['aster', 'peris']);
  const recordReceipt = first.keyboardPointerReceipt({
    verb: 'rally', consoleEvents: contractLedger.after(recordProductionMarker),
    inputEvents: recordInputLedger.after(recordInputMarker), intendedMembers: PARTY,
    targetToken: 'ordinary-floor', input: 'contract trace vector',
  });
  const ineligibleDecision = first.record({
    observationBefore: observation,
    observationAfter: interruptedObservation,
    observationSamples: [acceptedObservation, progressObservation],
    rationale: { text: 'Contract vector deliberately omits one intended group member.' },
    decision: {
      verb: 'rally', intended_subjects: PARTY,
      target: { kind: 'visible_affordance', token: 'ordinary-floor', screen: [420, 420] },
    },
    inputReceipt: recordReceipt,
    learningCandidate: rallyCandidate('dean_takahashi', {
      consequence: 'WALK ROUTE',
    }),
  });
  expect(ineligibleDecision.evidence.eligible_for_learning,
    'the run-atomic vector contains one genuinely ineligible decision').toBe(false);
  expect(ineligibleDecision.learning_candidate,
    'the Web writer records the interrupted decision without reserving its policy node')
    .toBeUndefined();
  expect(() => first.record({
    observationBefore: observation, observationAfter: afterObservation,
    observationSamples: [acceptedObservation, progressObservation],
    rationale: { text: 'Caller tries to attest itself.' },
    decision: { verb: 'wait', intended_subjects: [], target: { kind: 'none', token: '' } },
    inputReceipt: first.observedInputReceipt({ verb: 'wait', input: 'none' }),
    feedback: { player_observable: true }, outcome: { status: 'accepted' },
  }), 'v3 callers cannot provide feedback or outcome').toThrow(/derived internally/);

  first.finish();
  const firstSummary = first.records.at(-1).summary;
  expect(firstSummary.trace_complete,
    'one ineligible decision forces the hash-covered Web trace summary closed').toBe(false);
  expect(firstSummary.persona_goal_reached,
    'unsupported probe personas cannot self-declare a goal').toBe(false);
  expect(firstSummary.evidence_failures,
    'the summary records the exact ineligible decision count').toBe(1);
  expect(firstSummary.ineligible_decision_indices,
    'the summary records the exact ineligible decision index').toEqual([0]);
  expect(first.verify(), 'the fail-closed contract vector remains internally valid').toEqual([]);

  const staleSamples = [observation, observation, afterObservation, afterObservation];
  expect(normalizeObservationSamples(staleSamples),
    'transient observations are canonical-exact deduplicated in first-seen order')
    .toEqual([observation, afterObservation]);

  const shelterProximityObservation = {
    state: {
      hud: { portraits: [
        { token: 'portrait_0001', visible: true },
        { token: 'portrait_0002', visible: true },
        { token: 'portrait_0003', visible: true },
      ] },
      cues: [
        { kind: 'landmark', text: 'SHELTER', screen: [592, 360], visible: true },
        {
          kind: 'party_body', source_token: 'body_0001', binding: 'portrait_0001',
          screen: [584, 328], visible: true,
        },
        {
          kind: 'party_body', source_token: 'body_0002', binding: 'portrait_0002',
          screen: [664, 352], visible: true,
        },
        {
          kind: 'party_body', source_token: 'body_0003', binding: 'portrait_0003',
          screen: [568, 216], visible: true,
        },
      ],
    },
  };
  expect(partyVisiblyNearCue(shelterProximityObservation, /SHELTER/i),
    'a body 146 px away on another stacked route line is not at the shelter').toBe(false);
  shelterProximityObservation.state.cues.at(-1).screen = [592, 278];
  expect(partyVisiblyNearCue(shelterProximityObservation, /SHELTER/i),
    'the live 82 px stacked-route alias is still visibly outside the shelter').toBe(false);
  shelterProximityObservation.state.cues.at(-1).screen = [568, 288];
  expect(partyVisiblyNearCue(shelterProximityObservation, /SHELTER/i),
    'the exact visible portrait roster is near once every bound body is within 80 px').toBe(true);
});

test('Web persona trace refusal and input-ledger contract vectors', async () => {
  // The pure contract assertions live in beforeAll so both real persona journeys
  // share one parity gate. This named probe lets CI run that gate independently
  // of a several-minute Basin journey.
});

function contractPredicateMatches(predicate, root) {
  if (Array.isArray(predicate?.any)) {
    return predicate.any.some((child) => contractPredicateMatches(child, root));
  }
  const lookup = String(predicate?.path ?? '').split('.').filter(Boolean)
    .reduce((value, component) => value?.[component], root);
  return predicate?.op === 'eq' && canonicalHash(lookup) === canonicalHash(predicate.value);
}

function personaTraceRun(testInfo) {
  const runIndex = testInfo.repeatEachIndex;
  expect(Number.isInteger(runIndex), 'Playwright supplies a deterministic repeat index').toBe(true);
  return { runIndex, seed: runIndex };
}

async function bootBridgeState(page) {
  return page.evaluate(() => globalThis.__trawfE2E ?? null);
}

async function bridgeState(page, assertionOracle) {
  assertPostChoiceAssertionOracle(assertionOracle, 'private bridge state read');
  return page.evaluate(() => globalThis.__trawfE2E ?? null);
}

async function publishedPlayerObservation(page) {
  return page.evaluate(() => globalThis.__trawfE2E?.player_observation ?? null);
}

async function waitForBootState(page, label, predicate, timeout = 30_000) {
  let matchedState = null;
  await expect.poll(async () => {
    const state = await bootBridgeState(page);
    const matched = Boolean(state && predicate(state));
    if (matched) matchedState = state;
    return matched;
  }, { message: label, timeout }).toBe(true);
  return matchedState;
}

async function assertFixtureRequiresInitialWebE2EQuery(page, fixtureId) {
  expect(WEB_E2E_FIXTURE_IDS, `${fixtureId} is one declared Web-only fixture id`)
    .toContain(fixtureId);
  await page.goto(`/index.html?fragment=${encodeURIComponent(fixtureId)}`);
  await expect(page.locator('#status'),
    `${fixtureId} no-query probe finishes the real exported-Web bootstrap`)
    .toHaveCount(0, { timeout: 90_000 });
  await page.waitForTimeout(250);
  expect(await bootBridgeState(page),
    `${fixtureId} cannot enable the browser bridge without ?e2e=1`).toBeNull();

  // Turn observation on only after MainMenu has already evaluated the original
  // no-e2e URL. History replacement does not rerun its launch resolver. Driving
  // the focused Play -> Builder -> Fragments controls with ordinary keyboard
  // input must therefore reach the production picker, never the requested
  // fixture. The newly constructed preview controller may observe that result.
  await page.evaluate((requestedFixtureId) => {
    const url = new URL(globalThis.location.href);
    url.searchParams.set('e2e', '1');
    url.searchParams.set('fragment', requestedFixtureId);
    globalThis.history.replaceState({}, '', url);
  }, fixtureId);
  await page.locator('canvas').focus();
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('Enter');
  const ordinaryPickerState = await waitForBootState(
    page,
    `${fixtureId} no-query launch reaches the ordinary Fragments picker`,
    (state) => state.stage === 'fragment',
    30_000,
  );
  expect(ordinaryPickerState.ready,
    `${fixtureId} was not resolved to any active chunk before entering Fragments`).toBe(false);
  expect(ordinaryPickerState.fragment,
    `${fixtureId} remains absent from the ordinary picker launch state`).not.toBe(fixtureId);
}

async function waitForState(page, assertionOracle, label, predicate, timeout = 30_000) {
  let matchedState = null;
  await expect.poll(async () => {
    const state = await bridgeState(page, assertionOracle);
    const matched = Boolean(state && predicate(state));
    if (matched) matchedState = state;
    return matched;
  }, { message: label, timeout }).toBe(true);
  return matchedState;
}

function playerObservation(state, context) {
  const observation = structuredClone(state?.player_observation ?? {});
  const issues = validatePlayerObservation(observation);
  expect(issues, `${context}: browser publishes strict player_observation_v1`).toEqual([]);
  return observation;
}

async function currentPlayerObservation(page, context) {
  const observation = structuredClone(await publishedPlayerObservation(page) ?? {});
  const issues = validatePlayerObservation(observation);
  expect(issues, `${context}: browser publishes strict player_observation_v1`).toEqual([]);
  return observation;
}

async function waitForPlayerObservation(page, label, predicate, timeout = 30_000) {
  try {
    await expect.poll(async () => {
      const observation = await publishedPlayerObservation(page);
      return validatePlayerObservation(observation ?? {}).length === 0 && predicate(observation);
    }, { message: label, timeout }).toBe(true);
  } catch (error) {
    const observation = await publishedPlayerObservation(page) ?? {};
    const diagnostic = {
      validation_issues: validatePlayerObservation(observation),
      visible_cues: (observation?.state?.cues ?? [])
        .filter((cue) => cue?.visible === true)
        .map((cue) => ({
          kind: cue.kind ?? '',
          phase: cue.phase ?? '',
          text: cue.text ?? '',
          destination: cue.destination ?? '',
        })),
    };
    throw new Error(`${label}\nLast player-observable state: ${JSON.stringify(diagnostic)}`, {
      cause: error,
    });
  }
  return currentPlayerObservation(page, label);
}

async function collectPlayerObservationsUntil(
  page, label, predicate, timeout = 30_000, minimumCaptureSerial = 0, interval = 125,
) {
  const captured = [];
  let matchedObservation = null;
  try {
    await expect.poll(async () => {
      const observation = structuredClone(await publishedPlayerObservation(page) ?? {});
      if (validatePlayerObservation(observation).length > 0) return false;
      const priorSerial = Number(captured.at(-1)?.capture_serial ?? minimumCaptureSerial);
      if (observation.capture_serial <= priorSerial) return false;
      captured.push(observation);
      if (!predicate(observation, captured)) return false;
      matchedObservation = observation;
      return true;
    }, { message: label, timeout, intervals: [interval] }).toBe(true);
  } catch (error) {
    const observation = await publishedPlayerObservation(page) ?? {};
    throw new Error(`${label}\nLast player-observable state: ${JSON.stringify({
      validation_issues: validatePlayerObservation(observation),
      visible_cues: (observation?.state?.cues ?? []).filter((cue) => cue?.visible === true),
    })}`, { cause: error });
  }
  // The matched observation is evidence sampled during the action. Capture a
  // distinct, strictly newer terminal snapshot so v3 chronology can prove
  // before < samples < after without replaying the last sample as `after`.
  const observationAfter = await waitForPlayerObservation(
    page,
    `${label}: capture a fresh terminal observation`,
    (observation) => observation.capture_serial > matchedObservation.capture_serial,
    timeout,
  );
  return {
    observationAfter: structuredClone(observationAfter),
    observationSamples: normalizeObservationSamples(captured),
  };
}

function visibleRosterTokens(observation) {
  return (observation?.state?.hud?.portraits ?? [])
    .filter((portrait) => portrait?.visible === true)
    .map((portrait) => String(portrait?.token ?? '')).filter(Boolean).sort();
}

function partyBodyScreens(observation) {
  return new Map((observation?.state?.cues ?? [])
    .filter((cue) => cue?.kind === 'party_body' && cue?.visible === true
      && typeof cue?.source_token === 'string' && Array.isArray(cue?.screen))
    .map((cue) => [cue.source_token, cue.screen]));
}

function visiblePartyBodyTokens(observation) {
  return [...partyBodyScreens(observation).keys()].sort();
}

function exactPartyPresenceBindings(observation) {
  requirePlayerObservationPolicyInput(observation, 'exact visible party-presence assertion');
  const portraits = (observation?.state?.hud?.portraits ?? [])
    .filter((portrait) => portrait?.visible === true);
  const portraitTokens = portraits.map((portrait) => String(portrait?.token ?? ''));
  const members = portraits.map((portrait) => normalizeVisibleSubjectId(portrait?.label));
  const uniquePortraitTokens = new Set(portraitTokens);
  const bodyByPortrait = new Map();
  const duplicateBindings = new Set();
  const bodyTokens = new Set();
  for (const cue of observation?.state?.cues ?? []) {
    if (cue?.kind !== 'party_body' || cue?.visible !== true) continue;
    const binding = String(cue?.binding ?? '');
    const bodyToken = String(cue?.source_token ?? '');
    if (!uniquePortraitTokens.has(binding) || !bodyToken) continue;
    if (bodyByPortrait.has(binding) || bodyTokens.has(bodyToken)) {
      duplicateBindings.add(binding);
      continue;
    }
    bodyByPortrait.set(binding, bodyToken);
    bodyTokens.add(bodyToken);
  }
  const concealedPortraitTokens = portraits
    .filter((portrait) => {
      const statuses = portrait?.statuses ?? [];
      return Array.isArray(statuses) && statuses.includes('HIDDEN')
        && !statuses.includes('COVERED');
    })
    .map((portrait) => String(portrait.token));
  const contradictoryPortraits = concealedPortraitTokens
    .filter((token) => bodyByPortrait.has(token));
  const represented = new Set([
    ...bodyByPortrait.keys(), ...concealedPortraitTokens,
  ]);
  const valid = portraits.length === PARTY.length
    && sameMembers(members, PARTY)
    && portraitTokens.every(Boolean)
    && uniquePortraitTokens.size === portraits.length
    && duplicateBindings.size === 0
    && contradictoryPortraits.length === 0
    && portraitTokens.every((token) => represented.has(token))
    && represented.size === portraitTokens.length;
  return {
    valid,
    members: [...members].sort(),
    portraitTokens: [...portraitTokens].sort(),
    bodyTokens: [...bodyTokens].sort(),
    concealedPortraitTokens: [...concealedPortraitTokens].sort(),
    bindings: Object.fromEntries([...bodyByPortrait.entries()].sort()),
  };
}

function chooseFarthestVisibleMove(observation, originScreen) {
  observation = requirePlayerObservationPolicyInput(
    observation, 'farthest visible move selection',
  );
  if (!Array.isArray(originScreen) || originScreen.length !== 2) return null;
  const moves = (observation?.state?.affordances ?? [])
    .filter((candidate) => candidate?.kind === 'move'
      && candidate?.visible !== false
      && Array.isArray(candidate?.screen) && candidate.screen.length === 2
      && !/NO ROUTE/i.test(String(candidate?.consequence ?? '')))
    .sort((left, right) => screenDistance(right.screen, originScreen)
      - screenDistance(left.screen, originScreen)
      || String(left.token).localeCompare(String(right.token)));
  return personaPolicyAffordance(
    observation, moves[0] ?? null, 'farthest visible move selection',
  );
}

async function sampleDistinctPlayerObservations(page, durationMs, intervalMs = 100) {
  const samples = [];
  const deadline = Date.now() + durationMs;
  while (Date.now() < deadline) {
    const observation = await currentPlayerObservation(page, 'bounded Web observation sample');
    if (observation.capture_serial > Number(samples.at(-1)?.capture_serial ?? -1)) {
      samples.push(observation);
    }
    await page.waitForTimeout(intervalMs);
  }
  return normalizeObservationSamples(samples);
}

function productionEventRecords(messages, kind) {
  return messages.map((message) => {
    const text = String(message);
    const eventKind = text.match(/\[EVENT[^\]]*\]\s+([a-z0-9_]+)\s+/iu)?.[1] ?? '';
    const payloadStart = text.indexOf('{');
    let payload = {};
    if (payloadStart >= 0) {
      try { payload = JSON.parse(text.slice(payloadStart)); } catch { payload = {}; }
    }
    return { kind: eventKind, payload, text };
  }).filter((event) => event.kind === kind);
}

function movedVisiblePartyTokens(before, after, tolerance = 1.0) {
  const baseline = partyBodyScreens(before);
  const current = partyBodyScreens(after);
  return [...baseline.keys()].filter((token) => current.has(token)
    && screenDistance(baseline.get(token), current.get(token)) > tolerance).sort();
}

function visiblePartyIsStable(captured, rosterTokens, sampleCount = 3, tolerance = 2.0) {
  if (captured.length < sampleCount) return false;
  const recent = captured.slice(-sampleCount).map(partyBodyScreens);
  if (recent.some((index) => rosterTokens.some((token) => !index.has(token)))) return false;
  const first = recent[0];
  return recent.slice(1).every((index) => rosterTokens.every((token) =>
    screenDistance(first.get(token), index.get(token)) <= tolerance));
}

function highestVisibleMovementSerial(observation) {
  return Math.max(0, ...(observation?.state?.cues ?? [])
    .filter((cue) => cue?.visible === true && cue?.kind === 'movement_result'
      && Number.isInteger(cue?.presentation_serial))
    .map((cue) => cue.presentation_serial));
}

function hasCompleteVisibleMovementLineage(
  observations, targetToken, rosterTokens, minimumSerial = 0,
) {
  const expectedSubjects = [...rosterTokens].sort();
  const bySerial = new Map();
  for (const observation of observations) {
    for (const cue of observation?.state?.cues ?? []) {
      if (cue?.visible !== true || cue?.kind !== 'movement_result'
          || cue?.target_token !== targetToken
          || !Number.isInteger(cue?.presentation_serial)
          || cue.presentation_serial <= minimumSerial
          || JSON.stringify([...(cue?.subjects ?? [])].sort()) !== JSON.stringify(expectedSubjects)) {
        continue;
      }
      const lineage = bySerial.get(cue.presentation_serial) ?? [];
      if (lineage.at(-1) !== cue.phase) lineage.push(cue.phase);
      bySerial.set(cue.presentation_serial, lineage);
    }
  }
  return [...bySerial.values()].some((phases) =>
    JSON.stringify(phases) === JSON.stringify(['accepted', 'progress', 'arrival']));
}

function newestVisibleInteractionResult(observation, targetToken, minimumSerial = 0) {
  return (observation?.state?.cues ?? [])
    .filter((cue) => cue?.visible === true && cue?.kind === 'interaction_result'
      && cue?.source_token === targetToken && Number.isInteger(cue?.presentation_serial)
      && cue.presentation_serial > minimumSerial)
    .sort((left, right) => right.presentation_serial - left.presentation_serial)[0] ?? null;
}

function highestVisibleInteractionSerial(observation, targetToken) {
  return Math.max(0, ...(observation?.state?.cues ?? [])
    .filter((cue) => cue?.visible === true && cue?.kind === 'interaction_result'
      && cue?.source_token === targetToken && Number.isInteger(cue?.presentation_serial))
    .map((cue) => cue.presentation_serial));
}

function sweepPhaseTokens(observations, phase, rosterTokens) {
  const expected = new Set(rosterTokens);
  return new Set(observations.flatMap((observation) => observation?.state?.cues ?? [])
    .filter((cue) => cue?.visible === true && cue?.kind === 'consequence'
      && cue?.phase === phase && expected.has(String(cue?.source_token ?? ''))
      && /SWEPT/i.test(`${cue?.label ?? ''} ${cue?.text ?? ''}`)
      && /START|CURRENT RETURN/i.test(`${cue?.destination_label ?? ''} ${cue?.text ?? ''}`))
    .map((cue) => String(cue.source_token)));
}

async function selectFullVisiblePartyFromPortraits(inputLedger, observation) {
  observation = requirePlayerObservationPolicyInput(observation, 'visible portrait selection');
  const keyByLabel = { aster: '1', peris: '2', endo: '3' };
  const visible = (observation?.state?.hud?.portraits ?? [])
    .filter((portrait) => portrait?.visible === true);
  expect(visible.length, 'the selection decision sees at least one portrait').toBeGreaterThan(0);
  const expected = visible
    .map((portrait) => normalizeVisibleSubjectId(portrait.label))
    .filter(Boolean)
    .sort();
  const visibleTokens = visible
    .map((portrait) => String(portrait?.token ?? '').trim())
    .filter(Boolean);
  const duplicateMembers = [...new Set(expected.filter(
    (subject, index) => expected.indexOf(subject) !== index,
  ))].sort();
  const duplicateTokens = [...new Set(visibleTokens.filter(
    (token, index) => visibleTokens.indexOf(token) !== index,
  ))].sort();
  const unboundMembers = expected.filter((subject) => !keyByLabel[subject]);
  if (expected.length !== visible.length || visibleTokens.length !== visible.length
      || duplicateMembers.length > 0 || duplicateTokens.length > 0
      || unboundMembers.length > 0) {
    return {
      acted: false,
      accepted: false,
      status: 'refused',
      inputIssued: false,
      expected,
      unboundMembers,
      duplicateMembers,
      duplicateTokens,
      activeSubject: '',
      input: `no selection input; visible portraits lack shipped bindings: ${unboundMembers.join(', ')}`,
    };
  }
  if (visible.every((portrait) => portrait.selected === true)) {
    return {
      acted: false,
      accepted: true,
      status: 'accepted',
      inputIssued: false,
      expected,
      unboundMembers: [],
      duplicateMembers: [],
      duplicateTokens: [],
      activeSubject: '',
      input: 'no selection input; every visible portrait was already selected',
    };
  }
  const primary = visible.find((portrait) => portrait.selected !== true);
  const primaryLabel = normalizeVisibleSubjectId(primary.label);
  const chords = [keyByLabel[primaryLabel]];
  for (const portrait of visible.filter((candidate) => candidate !== primary)) {
    const label = normalizeVisibleSubjectId(portrait.label);
    chords.push(`Control+${keyByLabel[label]}`);
  }
  const actionCapability = authorizeObservationPlayerAction(inputLedger, observation, {
    gesture: 'key_sequence', choices: visible, keys: chords, targetToken: 'hud_portraits',
  });
  await inputLedger.press(keyByLabel[primaryLabel], 'hud_portraits', actionCapability);
  for (const chord of chords.slice(1)) {
    await inputLedger.press(chord, 'hud_portraits', actionCapability);
  }
  return {
    acted: true,
    accepted: true,
    status: 'accepted',
    inputIssued: true,
    expected,
    unboundMembers: [],
    duplicateMembers: [],
    duplicateTokens: [],
    activeSubject: primaryLabel,
    actionCapability,
    input: `${chords.join(', ')} through production keyboard input`,
  };
}

function visibleSubjectIds(observation) {
  observation = requirePlayerObservationPolicyInput(observation, 'visible subject selection');
  return visibleSubjectIdsFromObservation(observation);
}

function selectedVisibleMemberResults(observationBefore, observationAfter) {
  const intended = visibleSubjectIds(observationBefore);
  const selected = new Set((observationAfter?.state?.hud?.portraits ?? [])
    .filter((portrait) => portrait?.visible === true && portrait?.selected === true)
    .map((portrait) => normalizeVisibleSubjectId(portrait.label))
    .filter(Boolean));
  return Object.fromEntries(intended.map((subject) => [
    subject, selected.has(subject) ? 'accepted' : 'refused',
  ]));
}

function visibleCue(observation, textPattern) {
  return (observation?.state?.cues ?? []).find((cue) =>
    cue.visible === true && textPattern.test(`${cue.text ?? ''} ${cue.destination ?? ''}`));
}

function chooseVisibleCue(observation, textPattern) {
  observation = requirePlayerObservationPolicyInput(observation, 'visible cue selection');
  return personaPolicyAffordance(
    observation, visibleCue(observation, textPattern), 'visible cue selection',
  );
}

function portraitTokens(observation) {
  return new Set((observation?.state?.hud?.portraits ?? [])
    .map((portrait) => String(portrait?.token ?? ''))
    .filter(Boolean));
}

function partySubjectSweepCues(observation) {
  const tokens = portraitTokens(observation);
  return (observation?.state?.cues ?? []).filter((cue) =>
    cue?.kind === 'consequence'
      && cue?.visible === true
      && /SWEPT/i.test(String(cue?.text ?? ''))
      && tokens.has(String(cue?.source_token ?? '')));
}

function tracedFeedbackCues(trace, predicate) {
  return trace.records
    .filter((record) => record.record_type === 'decision')
    .flatMap((record) => (record.feedback?.cues ?? [])
      .filter(predicate)
      .map((cue) => ({ decision_index: record.decision_index, cue })));
}

function visibleCueScreens(observation, textPattern) {
  return (observation?.state?.cues ?? [])
    .filter((cue) => cue.visible === true
      && Array.isArray(cue.screen) && cue.screen.length === 2
      && textPattern.test(`${cue.text ?? ''} ${cue.destination ?? ''}`))
    .map((cue) => cue.screen);
}

function screenDistance(left, right) {
  return Math.hypot(left[0] - right[0], left[1] - right[1]);
}

// Godot's String.hash() uses the DJB2 byte hash. Matching it keeps the native and
// Web Dean policies on the same arbitrary visible target for a given repeat.
function godotStringHash(text) {
  let hash = 5381;
  for (const byte of new TextEncoder().encode(text)) {
    hash = (((hash << 5) + hash) + byte) >>> 0;
  }
  return Math.abs(hash | 0);
}

function chooseDeanUnmarkedGround(observation, runIndex, decisionIndex = 0) {
  observation = requirePlayerObservationPolicyInput(observation, 'Dean ground selection');
  const bins = [
    'top_center', 'top_left', 'middle_center', 'top_right',
    'middle_right', 'middle_left', 'bottom_center', 'bottom_right', 'bottom_left',
  ];
  const available = bins.flatMap((bin) =>
    (observation?.state?.viewport_bins?.[bin] ?? [])
      .map((token) => observedAffordanceFromObservation(observation, token))
      .filter((candidate) => candidate?.kind === 'move'));
  const visibleSweepRisk = available.filter((candidate) =>
    /RISING BASIN SWEEP/i.test(candidate.consequence ?? ''));
  // Dean can choose a foolish screen-space destination, but the rationale is still
  // constrained by what a human can see. A route explicitly labeled as a ladder,
  // stair, portal, or refusal is not an "unmarked floor patch" for any seed.
  const ordinaryGround = available.filter((candidate) =>
    !/\b(LADDER|STAIR|PORTAL|NO ROUTE)\b/i.test(candidate.consequence ?? ''));
  const deckAccessScreens = visibleCueScreens(observation, /DECK ACCESS/i);
  const unmarked = ordinaryGround.filter((candidate) => deckAccessScreens.length === 0
    || Math.min(...deckAccessScreens.map((screen) => screenDistance(candidate.screen, screen))) > 144);
  const choices = visibleSweepRisk.length > 0
    ? visibleSweepRisk
    : (unmarked.length > 0 ? unmarked : ordinaryGround);
  if (choices.length === 0) return null;
  const key = `dean_takahashi:${runIndex}:${decisionIndex}`;
  return personaPolicyAffordance(
    observation, choices[godotStringHash(key) % choices.length], 'Dean ground selection',
  );
}

function chooseVisibleLadderRoute(observation) {
  observation = requirePlayerObservationPolicyInput(observation, 'visible ladder selection');
  const bins = [
    'top_center', 'top_left', 'middle_center', 'top_right',
    'middle_right', 'middle_left', 'bottom_center', 'bottom_right', 'bottom_left',
  ];
  const routes = bins.flatMap((bin) =>
    (observation?.state?.viewport_bins?.[bin] ?? [])
      .map((token) => observedAffordanceFromObservation(observation, token))
      .filter((candidate) => candidate?.kind === 'move'
        && /LADDER/i.test(candidate.consequence ?? '')));
  const deckAccessScreens = visibleCueScreens(observation, /DECK ACCESS/i);
  routes.sort((left, right) => {
    if (deckAccessScreens.length === 0) return left.token.localeCompare(right.token);
    const leftDistance = Math.min(...deckAccessScreens.map((screen) =>
      screenDistance(left.screen, screen)));
    const rightDistance = Math.min(...deckAccessScreens.map((screen) =>
      screenDistance(right.screen, screen)));
    return leftDistance - rightDistance || left.token.localeCompare(right.token);
  });
  return personaPolicyAffordance(
    observation, routes.length > 0 ? routes[0] : null, 'visible ladder selection',
  );
}

function chooseGroundNearVisibleCue(observation, textPattern) {
  observation = requirePlayerObservationPolicyInput(observation, 'visible cue ground selection');
  const cueScreens = visibleCueScreens(observation, textPattern);
  if (cueScreens.length === 0) return null;
  const bins = [
    'top_center', 'top_left', 'middle_center', 'top_right',
    'middle_right', 'middle_left', 'bottom_center', 'bottom_right', 'bottom_left',
  ];
  const candidates = bins.flatMap((bin) =>
    (observation?.state?.viewport_bins?.[bin] ?? [])
      .map((token) => observedAffordanceFromObservation(observation, token))
      .filter((candidate) => candidate?.kind === 'move'
        && !/NO ROUTE/i.test(candidate.consequence ?? '')));
  candidates.sort((left, right) => {
    const leftDistance = Math.min(...cueScreens.map((screen) => screenDistance(left.screen, screen)));
    const rightDistance = Math.min(...cueScreens.map((screen) => screenDistance(right.screen, screen)));
    return leftDistance - rightDistance || left.token.localeCompare(right.token);
  });
  return personaPolicyAffordance(
    observation, candidates.length > 0 ? candidates[0] : null, 'visible cue ground selection',
  );
}

function chooseVisibleInteraction(observation, textPattern) {
  observation = requirePlayerObservationPolicyInput(observation, 'visible interaction selection');
  return personaPolicyAffordance(
    observation,
    chooseVisibleInteractionFromObservation(observation, textPattern),
    'visible interaction selection',
  );
}

function partyVisiblyNearCue(observation, textPattern) {
  const targets = visibleCueScreens(observation, textPattern);
  if (targets.length === 0) return false;
  const rosterTokens = visibleRosterTokens(observation);
  if (rosterTokens.length === 0) return false;
  const roster = new Set(rosterTokens);
  const bodyScreenByPortrait = new Map();
  for (const cue of observation?.state?.cues ?? []) {
    const binding = String(cue?.binding ?? '');
    if (cue?.kind !== 'party_body' || cue?.visible !== true || !roster.has(binding)
        || !Array.isArray(cue?.screen) || cue.screen.length !== 2
        || bodyScreenByPortrait.has(binding)) continue;
    bodyScreenByPortrait.set(binding, cue.screen);
  }
  return rosterTokens.every((portraitToken) => bodyScreenByPortrait.has(portraitToken)
    && Math.min(...targets.map((target) =>
      screenDistance(bodyScreenByPortrait.get(portraitToken), target)))
      <= PARTY_NEAR_CUE_MAX_DISTANCE);
}

function contentFingerprint(state) {
  expect(state?.content_fingerprint_schema,
    'the Web bridge publishes the shared authored-resource fingerprint schema')
    .toBe('authored_fragment_resource_bytes_v1');
  expect(state?.content_fingerprint,
    'the Web bridge publishes the exact shared authored-resource SHA-256')
    .toMatch(/^[a-f0-9]{64}$/);
  expect(state?.gameplay_build_fingerprint_schema,
    'the Web bridge publishes the shared gameplay-build fingerprint schema')
    .toBe('gameplay_build_resource_set_bytes_v1');
  expect(state?.gameplay_build_fingerprint,
    'the Web bridge publishes the exact shared gameplay-build SHA-256')
    .toMatch(/^[a-f0-9]{64}$/);
  return {
    contentFingerprintSchema: state.content_fingerprint_schema,
    contentFingerprint: state.content_fingerprint,
    gameplayBuildFingerprintSchema: state.gameplay_build_fingerprint_schema,
    gameplayBuildFingerprint: state.gameplay_build_fingerprint,
  };
}

function productionMessagesAfter(ledger, marker) {
  return ledger.after(marker);
}

function expectLearningEligible(record, context) {
  expect(record.evidence.rejection_reasons, `${context}: no evidence rule is self-attested`).toEqual([]);
  expect(record.evidence.eligible_for_learning,
    `${context}: the independently classified decision can enter distillation`).toBe(true);
}

function sameMembers(actual, expected) {
  return actual?.length === expected.length && expected.every((id) => actual.includes(id));
}

function distance3(a, b) {
  const left = Array.isArray(a) ? { x: a[0], y: a[1], z: a[2] } : a;
  const right = Array.isArray(b) ? { x: b[0], y: b[1], z: b[2] } : b;
  return Math.hypot(left.x - right.x, left.y - right.y, left.z - right.z);
}

function distanceXZ(a, b) {
  const left = Array.isArray(a) ? { x: a[0], z: a[2] } : a;
  const right = Array.isArray(b) ? { x: b[0], z: b[2] } : b;
  return Math.hypot(left.x - right.x, left.z - right.z);
}

function consequenceFeedback(state, context) {
  const feedback = state?.consequence_feedback;
  expect(feedback?.contract, `${context}: live consequence contract is exported`)
    .toBe('consequence_presentation/v1');
  for (const bucket of ['warning', 'active', 'recent']) {
    expect(Array.isArray(feedback[bucket]), `${context}: ${bucket} feedback is portable`).toBe(true);
  }
  return feedback;
}

function findFeedbackRecord(state, bucket, expected) {
  const records = state?.consequence_feedback?.[bucket] ?? [];
  return records.find((record) => Object.entries(expected)
    .every(([key, value]) => record?.[key] === value));
}

function forcedMovementRecords(state) {
  const feedback = state?.consequence_feedback ?? {};
  return ['warning', 'active', 'recent'].flatMap((bucket) => feedback[bucket] ?? [])
    .filter((record) => record.effect_kind === 'forced_movement');
}

function sameCell(a, b) {
  return Boolean(a && b && a.x === b.x && a.y === b.y);
}

function expectConnectedLadderGraph(state, context) {
  const edges = state?.ladder_edges ?? [];
  expect(edges.length, `${context}: runtime graph exports ladder edges`).toBeGreaterThan(0);
  for (const edge of edges) {
    expect(edge.kind, `${context}: ${edge.id} is an inter-level graph edge`).toBe('inter_level');
    expect(edge.type, `${context}: ${edge.id} retains its ladder type`).toBe('ladder');
    expect(edge.annotation, `${context}: ${edge.id} retains its ladder annotation`).toBe('ladder');
    expect(edge.from_cell, `${context}: ${edge.id} has a source cell`).toBeTruthy();
    expect(edge.to_cell, `${context}: ${edge.id} has a destination cell`).toBeTruthy();
    expect(Number.isInteger(edge.from_level), `${context}: ${edge.id} has a source level`).toBe(true);
    expect(Number.isInteger(edge.to_level), `${context}: ${edge.id} has a destination level`).toBe(true);
    expect(edge.from_walkable, `${context}: ${edge.id}'s source vertex is walkable`).toBe(true);
    expect(edge.to_walkable, `${context}: ${edge.id}'s destination vertex is walkable`).toBe(true);
    expect(edge.connected, `${context}: ${edge.id} connects two graph vertices`).toBe(true);
  }
}

function expectAnnotatedLevelTransitions(state, id, context, requireLowToUpper = false) {
  const transitions = state?.characters?.[id]?.level_transitions ?? [];
  if (requireLowToUpper) {
    expect(
      transitions.some((entry) => entry.from_level === 0 && entry.to_level === 1),
      `${context}: ${id} records its low-to-upper transition`,
    ).toBe(true);
  }
  for (const [index, transition] of transitions.entries()) {
    expect(transition.edge_category,
      `${context}: ${id} transition ${index} came from a graph connector`).toBe('connector');
    expect(transition.edge_kind,
      `${context}: ${id} transition ${index} executed the ladder traversal kind`).toBe('ladder');
    expect(transition.edge_type,
      `${context}: ${id} transition ${index} came from a ladder edge`).toBe('ladder');
    const edge = state.ladder_edges?.find((candidate) =>
      candidate.connected
        && candidate.kind === 'inter_level'
        && candidate.type === 'ladder'
        && candidate.from_level === transition.from_level
        && candidate.to_level === transition.to_level
        && sameCell(candidate.from_cell, transition.from_cell)
        && sameCell(candidate.to_cell, transition.to_cell));
    expect(edge,
      `${context}: ${id} transition ${index} matches one connected, annotated graph edge`).toBeTruthy();
  }
}

function expectPresentationParity(state, id, context, expectedY = null) {
  const character = state?.characters?.[id];
  expect(character?.logical_position, `${context}: ${id} publishes logical position`).toBeTruthy();
  expect(character?.expected_render_position,
    `${context}: ${id} publishes the render position derived from world truth`).toBeTruthy();
  expect(character?.presented_position,
    `${context}: ${id} publishes its actual CharacterBody position`).toBeTruthy();
  expect(character?.presented_transform_origin,
    `${context}: ${id} publishes its actual global transform origin`).toBeTruthy();
  expect(
    distance3(character.presented_position, character.expected_render_position),
    `${context}: ${id}'s actual presenter matches authoritative render position`,
  ).toBeLessThan(0.2);
  expect(
    distance3(character.presented_transform_origin, character.expected_render_position),
    `${context}: ${id}'s full global transform origin matches authoritative render position`,
  ).toBeLessThan(0.2);
  expect(
    distance3(character.presented_transform_origin, character.presented_position),
    `${context}: ${id}'s position and transform projections agree`,
  ).toBeLessThan(0.001);
  expect(character.max_presented_position_error,
    `${context}: ${id}'s presenter never drifted from render truth`).toBeLessThan(0.2);
  expect(character.max_presented_transform_error,
    `${context}: ${id}'s transform never drifted from render truth`).toBeLessThan(0.2);
  expect(character.transform_sample_count,
    `${context}: ${id}'s per-frame transform sampler actually ran`).toBeGreaterThan(0);
  expect(character.logical_to_render_projection_valid,
    `${context}: ${id}'s logical-to-render projection stayed valid in full XYZ`).toBe(true);
  expect(character.logical_to_render_projection_error,
    `${context}: ${id}'s current logical-to-render projection agrees in full XYZ`).toBeLessThan(0.2);
  expect(character.max_logical_to_render_projection_error,
    `${context}: ${id}'s logical-to-render projection never drifted in full XYZ`).toBeLessThan(0.2);
  if (expectedY !== null) {
    expect(Math.abs(character.logical_position.y - expectedY),
      `${context}: ${id}'s logical Y is on the expected floor`).toBeLessThan(0.05);
    expect(Math.abs(character.presented_position.y - expectedY),
      `${context}: ${id}'s actual CharacterBody Y is on the expected floor`).toBeLessThan(0.05);
    expect(Math.abs(character.presented_transform_origin.y - expectedY),
      `${context}: ${id}'s transform origin Y is on the expected floor`).toBeLessThan(0.05);
  }
}

function movementSampleCount(state, id, context) {
  const character = state?.characters?.[id];
  expect(Number.isInteger(character?.movement_transform_sample_count),
    `${context}: ${id} publishes an integer movement-only transform sample count`).toBe(true);
  expect(character.in_flight_transform_sample_count,
    `${context}: ${id}'s in-flight sample alias agrees with movement coverage`)
    .toBe(character.movement_transform_sample_count);
  return character.movement_transform_sample_count;
}

function expectMovementPresentationParity(state, id, context, baselineCount = null) {
  const character = state?.characters?.[id];
  const sampleCount = movementSampleCount(state, id, context);
  expect(sampleCount,
    `${context}: ${id} was sampled while a real movement command was in flight`).toBeGreaterThan(0);
  if (baselineCount !== null) {
    expect(sampleCount,
      `${context}: ${id} accumulated in-flight samples after the covered command's baseline`)
      .toBeGreaterThan(baselineCount);
  }
  expect(character.max_movement_presented_position_error,
    `${context}: ${id}'s global_position stayed aligned during movement`)
    .toBeLessThan(MOVEMENT_TRANSFORM_TOLERANCE);
  expect(character.max_movement_presented_transform_error,
    `${context}: ${id}'s global_transform origin stayed aligned during movement`)
    .toBeLessThan(MOVEMENT_TRANSFORM_TOLERANCE);
  expect(character.movement_logical_to_render_projection_valid,
    `${context}: ${id}'s movement projection stayed valid in full XYZ`).toBe(true);
  expect(character.max_movement_logical_to_render_projection_error,
    `${context}: ${id}'s logical-to-render projection stayed aligned during movement`)
    .toBeLessThan(MOVEMENT_TRANSFORM_TOLERANCE);
}

async function snapshotMovementCountsBeforeLaunch(page, assertionOracle, ids, context) {
  // A bare bridgeState(page) call is deliberately forbidden here; the fixed
  // action choice must supply its post-choice assertion oracle first.
  const state = await bridgeState(page, assertionOracle);
  return Object.fromEntries(ids.map((id) =>
    [id, movementSampleCount(state, id, `${context} pre-launch baseline`)]));
}

function movementContinuityReceipt(state, id, context) {
  const receipt = state?.characters?.[id]?.movement_continuity;
  expect(receipt?.contract_id,
    `${context}: ${id} publishes the shared continuity contract`)
    .toBe('movement_continuity/v1');
  expect(Number.isInteger(receipt.completed_continuous_episode_count),
    `${context}: ${id} publishes a continuous-episode counter`).toBe(true);
  expect(Number.isInteger(receipt.invalid_episode_count),
    `${context}: ${id} publishes an invalid-episode counter`).toBe(true);
  expect(Number.isInteger(receipt.settled_jump_violation_count),
    `${context}: ${id} publishes a settled-jump counter`).toBe(true);
  expect(Number.isInteger(receipt.typed_portal_exception_count),
    `${context}: ${id} publishes a typed-portal exception counter`).toBe(true);
  expect(Number.isInteger(receipt.bounded_step_count),
    `${context}: ${id} publishes a committed-plan bounded-step counter`).toBe(true);
  expect(Number.isInteger(receipt.invalid_motion_authority_count),
    `${context}: ${id} publishes an invalid motion-authority counter`).toBe(true);
  expect(Number.isFinite(receipt.max_logical_speed_excess),
    `${context}: ${id} publishes finite logical plan-budget excess`).toBe(true);
  expect(Number.isFinite(receipt.max_render_speed_excess),
    `${context}: ${id} publishes finite render plan-budget excess`).toBe(true);
  return receipt;
}

async function snapshotMovementContinuityBeforeLaunch(
  page, assertionOracle, ids, context,
) {
  const state = await bridgeState(page, assertionOracle);
  return Object.fromEntries(ids.map((id) => {
    const receipt = movementContinuityReceipt(
      state, id, `${context} pre-launch continuity baseline`);
    expect(receipt.valid,
      `${context}: ${id}'s continuity ledger is clean before action attribution`)
      .toBe(true);
    expect(receipt.active_episode,
      `${context}: ${id} is settled before the measured action launches`)
      .toBe(false);
    expect(receipt.max_logical_speed_excess,
      `${context}: ${id}'s pre-launch logical plan budget is clean`).toBeLessThanOrEqual(0.01);
    expect(receipt.max_render_speed_excess,
      `${context}: ${id}'s pre-launch render plan budget is clean`).toBeLessThanOrEqual(0.01);
    return [id, {
      completed: receipt.completed_continuous_episode_count,
      invalid: receipt.invalid_episode_count,
      settledJumps: receipt.settled_jump_violation_count,
      portalExceptions: receipt.typed_portal_exception_count,
      boundedSteps: receipt.bounded_step_count,
      invalidAuthorities: receipt.invalid_motion_authority_count,
      logicalExcess: receipt.max_logical_speed_excess,
      renderExcess: receipt.max_render_speed_excess,
    }];
  }));
}

function expectMovementContinuity(
  state, id, context, baseline, expectedProvenance = null,
) {
  const receipt = movementContinuityReceipt(state, id, context);
  expect(receipt.completed_continuous_episode_count,
    `${context}: ${id} completes a new bounded origin/interior/endpoint episode`)
    .toBeGreaterThan(baseline.completed);
  expect(receipt.invalid_episode_count,
    `${context}: ${id} adds no invalid movement episode`).toBe(baseline.invalid);
  expect(receipt.settled_jump_violation_count,
    `${context}: ${id} never synchronizes authorities directly to an endpoint`)
    .toBe(baseline.settledJumps);
  expect(receipt.typed_portal_exception_count,
    `${context}: ${id} receives no portal exemption in the portal-free Basin`)
    .toBe(baseline.portalExceptions);
  expect(receipt.bounded_step_count,
    `${context}: ${id}'s covered action executes committed timed-plan interval budgets`)
    .toBeGreaterThan(baseline.boundedSteps);
  expect(receipt.invalid_motion_authority_count,
    `${context}: ${id}'s covered action adds no invalid authority interval`)
    .toBe(baseline.invalidAuthorities);
  expect(receipt.max_logical_speed_excess,
    `${context}: ${id}'s logical steps stay within exact plan-arc budgets`)
    .toBeLessThanOrEqual(0.01);
  expect(receipt.max_render_speed_excess,
    `${context}: ${id}'s render steps stay within exact plan-arc budgets`)
    .toBeLessThanOrEqual(0.01);
  expect(receipt.valid, `${context}: ${id}'s continuity ledger remains valid`).toBe(true);
  expect(receipt.active_episode,
    `${context}: ${id}'s measured movement has reached a settled endpoint`).toBe(false);
  const episode = receipt.last_completed_episode;
  expect(episode?.valid, `${context}: ${id}'s latest completed episode is valid`).toBe(true);
  expect(episode.strict_interior_presented_frame_count,
    `${context}: ${id} has strict interior full-XYZ progress on multiple rendered frames`)
    .toBeGreaterThanOrEqual(2);
  expect(episode.strict_interior_scheduler_tick_count,
    `${context}: ${id} has strict interior full-XYZ progress on multiple scheduler ticks`)
    .toBeGreaterThanOrEqual(2);
  expect(episode.max_step_fraction,
    `${context}: ${id}'s largest presented step is bounded below an endpoint snap`)
    .toBeLessThan(0.5);
  expect(episode.max_scheduler_tick_gap_fraction,
    `${context}: ${id}'s scheduler progress is bounded below a one-tick jump`)
    .toBeLessThan(0.9);
  expect(episode.full_xyz_displacement,
    `${context}: ${id}'s episode contains a non-trivial full-XYZ displacement`)
    .toBeGreaterThan(0.12);
  expect(episode.max_presented_position_error,
    `${context}: ${id}'s global_position remains continuous with render truth`)
    .toBeLessThan(MOVEMENT_TRANSFORM_TOLERANCE);
  expect(episode.max_presented_transform_error,
    `${context}: ${id}'s global_transform.origin remains continuous with render truth`)
    .toBeLessThan(MOVEMENT_TRANSFORM_TOLERANCE);
  expect(episode.max_logical_render_projection_error,
    `${context}: ${id}'s logical/render projection remains continuous`)
    .toBeLessThan(MOVEMENT_TRANSFORM_TOLERANCE);
  if (expectedProvenance) {
    const matching = (episode.movement_provenance ?? []).some((entry) =>
      Object.entries(expectedProvenance).every(([key, value]) => entry?.[key] === value));
    expect(matching,
      `${context}: ${id}'s continuity episode retains ${JSON.stringify(expectedProvenance)} provenance`)
      .toBe(true);
  }
}

async function waitForMovementSampleGrowth(
  page, assertionOracle, ids, baselineCounts, context, timeout = 30_000,
) {
  await Promise.all(ids.map(async (id) => {
    await expect.poll(async () => {
      const state = await bridgeState(page, assertionOracle);
      const count = state?.characters?.[id]?.movement_transform_sample_count;
      return Number.isInteger(count) ? count : -1;
    }, {
      message: `${context}: ${id}'s production traversal receives an in-flight transform sample`,
      timeout,
    }).toBeGreaterThan(baselineCounts[id]);
  }));
}

async function bridgeTargetPagePoint(page, name) {
  expect(WEB_BOOT_BRIDGE_TARGETS.has(name),
    `private bridge target '${name}' is reserved for boot orchestration`).toBe(true);
  const state = await bootBridgeState(page);
  const target = state?.click_targets?.[name];
  expect(target, "bridge target '" + name + "' exists").toBeTruthy();
  expect(target.visible, "bridge target '" + name + "' is camera-visible").toBe(true);
  const canvasBox = await page.locator('canvas').first().boundingBox();
  expect(canvasBox, 'Godot canvas has a page-space bounding box').toBeTruthy();
  return {
    x: canvasBox.x + (target.x / state.viewport.width) * canvasBox.width,
    y: canvasBox.y + (target.y / state.viewport.height) * canvasBox.height,
  };
}

async function clickBridgeTarget(page, name, button = 'right') {
  const point = await bridgeTargetPagePoint(page, name);
  await page.mouse.click(point.x, point.y, { button });
}

async function observedAffordancePagePoint(page, affordance, actionCapability) {
  requirePersonaPolicyAffordance(affordance, 'pointer target projection');
  assertObservationActionCapability(actionCapability, {
    choice: affordance, targetToken: affordance.token,
  }, 'pointer target projection');
  expect(affordance?.token, 'the persona selected an opaque visible affordance token').toBeTruthy();
  expect(affordance?.screen?.length, 'the visible affordance carries one screen-space point').toBe(2);
  const canvasBox = await page.locator('canvas').first().boundingBox();
  expect(canvasBox, 'Godot canvas has a page-space bounding box').toBeTruthy();
  const viewportSize = actionCapability.viewport_size;
  expect(viewportSize?.length, 'the action capability retains the observed viewport size').toBe(2);
  return {
    x: canvasBox.x + (affordance.screen[0] / viewportSize[0]) * canvasBox.width,
    y: canvasBox.y + (affordance.screen[1] / viewportSize[1]) * canvasBox.height,
  };
}

async function pressObservedKey(inputLedger, key, cue, targetToken, actionCapability) {
  requirePersonaPolicyAffordance(cue, 'keyboard decision');
  assertObservationActionCapability(actionCapability, {
    choice: cue, gesture: 'key_press', targetToken,
  }, 'keyboard decision');
  await inputLedger.press(key, targetToken, actionCapability);
}

async function observedKeyDown(inputLedger, key, cue, targetToken, actionCapability) {
  requirePersonaPolicyAffordance(cue, 'held-key decision');
  assertObservationActionCapability(actionCapability, {
    choice: cue, gesture: 'key_hold', targetToken,
  }, 'held-key decision');
  await inputLedger.keyDown(key, targetToken, actionCapability);
}

async function observedKeyUp(inputLedger, key, cue, targetToken, actionCapability) {
  requirePersonaPolicyAffordance(cue, 'held-key decision release');
  assertObservationActionCapability(actionCapability, {
    choice: cue, gesture: 'key_hold', targetToken,
  }, 'held-key decision release');
  await inputLedger.keyUp(key, targetToken, actionCapability);
}

async function clickObservedAffordance(
  page, inputLedger, affordance, actionCapability, button = 'right',
) {
  const point = await observedAffordancePagePoint(page, affordance, actionCapability);
  await inputLedger.pointerClick(
    point.x, point.y, button, affordance.token, actionCapability,
  );
}

async function holdBridgeTarget(
  page, inputLedger, affordance, actionCapability, holdMs = 1350,
) {
  // Kept under the historical helper name because the release contract audits
  // this exact held gesture. The target is now an opaque player-observation
  // affordance, never a named bridge click target or authored anchor.
  const point = await observedAffordancePagePoint(page, affordance, actionCapability);
  await inputLedger.pointerMove(point.x, point.y, affordance.token, actionCapability);
  await inputLedger.pointerDown('right', affordance.token, actionCapability);
  const heldObservations = [];
  try {
    const sampleOffsets = [250, 600, 950, holdMs].filter((offset, index, values) =>
      offset <= holdMs && values.indexOf(offset) === index);
    let elapsed = 0;
    for (const offset of sampleOffsets) {
      await page.waitForTimeout(offset - elapsed);
      heldObservations.push(await currentPlayerObservation(page, 'held Rally presentation'));
      elapsed = offset;
    }
  } finally {
    await inputLedger.pointerUp('right', affordance.token, actionCapability);
  }
  return normalizeObservationSamples(heldObservations);
}

test('DeanTakahashi records a real missed-rise Basin playthrough', async ({ page }, testInfo) => {
  const runtimeFailures = [];
  const productionEvents = captureProductionEvents(page);
  const playerInputs = capturePlayerInput(page);
  page.on('pageerror', (error) => runtimeFailures.push(`pageerror: ${error.message}`));
  page.on('console', (message) => {
    const messageText = message.text();
    if (message.type() === 'error' || message.type() === 'assert') {
      runtimeFailures.push(`console.${message.type()}: ${messageText}`);
    }
  });

  await page.goto('/index.html?e2e=1&fragment=basin_fill_proof');
  await waitForBootState(page, 'failure journey reaches the real Fragments button', (state) =>
    state.stage === 'main_menu' && state.ready && state.click_targets?.fragments?.visible,
  );
  await clickBridgeTarget(page, 'fragments', 'left');
  await waitForBootState(page, 'failure journey boots the authored Basin', (state) =>
    state.stage === 'fragment'
      && state.ready
      && state.fragment === 'basin_fill_proof'
      && PARTY.every((id) => state.characters?.[id]),
    45_000,
  );

  // Dean does not tidy the UI before acting; leaving both optional panels alone avoids hidden
  // setup input and matches the persona's visible-first fumble.
  const enterBowlObservation = await currentPlayerObservation(page, 'Dean authored-spawn baseline');
  const traceRun = personaTraceRun(testInfo);

  // Policy receives only presentation. Match the Windowed persona: Dean ignores
  // the visible DECK ACCESS markers, hashes among floor affordances openly marked
  // RISING BASIN SWEEP, and pointlessly rallies everyone instead of issuing a
  // hidden singleton move.
  const deanFloorChoice = chooseDeanUnmarkedGround(
    enterBowlObservation, traceRun.runIndex,
  );
  expect(deanFloorChoice, 'Dean can see a real ground affordance to fumble toward').toBeTruthy();
  expect(deanFloorChoice.kind).toBe('move');
  const deanRallyCapability = authorizePersonaAction(
    playerInputs, enterBowlObservation, deanFloorChoice, {
      gesture: 'pointer_hold', button: 'right', targetToken: deanFloorChoice.token,
    }, 'Dean visible-floor Rally',
  );
  const deanRallyOracle = postChoiceAssertionOracle(deanRallyCapability);
  let state = await bridgeState(page, deanRallyOracle);
  consequenceFeedback(state, 'authored failure spawn');
  expect(forcedMovementRecords(state),
    'idle authored spawn has no forced-movement feedback').toEqual([]);
  expectPresentationParity(state, 'aster', 'authored failure spawn', 0.0);
  const deanProvenance = contentFingerprint(state);
  const trace = new PersonaDecisionTrace({
    persona: 'dean_takahashi',
    fragmentId: 'basin_fill_proof',
    ...deanProvenance,
    ...traceRun,
  });
  expect({
    contentFingerprintSchema: trace.run.content_fingerprint_schema,
    contentFingerprint: trace.run.content_fingerprint,
    gameplayBuildFingerprintSchema: trace.run.gameplay_build_fingerprint_schema,
    gameplayBuildFingerprint: trace.run.gameplay_build_fingerprint,
  }, 'Dean trace provenance is the exact exported bridge identity').toEqual(deanProvenance);
  const intendedRallyMembers = visibleSubjectIds(enterBowlObservation);
  expect(sameMembers(intendedRallyMembers, PARTY),
    'Dean\'s pointless Rally still covers every conscious visible portrait').toBe(true);

  // Private authored coordinates begin here and remain post-choice test oracles;
  // they did not select the action or its target.
  const initialPartyPositions = Object.fromEntries(PARTY.map((id) => [
    id, { ...state.characters[id].logical_position },
  ]));
  const initialAsterPosition = initialPartyPositions.aster;
  const startReturn = state.anchors?.start_return;
  expect(startReturn, 'the browser bridge exports the CURRENT RETURN oracle').toBeTruthy();
  const deanRosterTokens = visibleRosterTokens(enterBowlObservation);
  expect(deanRosterTokens.length,
    'Dean begins with one opaque visible roster token per party member').toBe(PARTY.length);
  const deanBodyTokens = visiblePartyBodyTokens(enterBowlObservation);
  expect(deanBodyTokens.length,
    'Dean begins with one visible body token per party member').toBe(PARTY.length);

  const ordinaryMovementBaselines = await snapshotMovementCountsBeforeLaunch(
    page, deanRallyOracle, PARTY, 'failure journey pointless Rally');
  const ordinaryContinuityBaselines = await snapshotMovementContinuityBeforeLaunch(
    page, deanRallyOracle, PARTY, 'failure journey pointless Rally');
  const deanMovementPresentationBaseline = highestVisibleMovementSerial(enterBowlObservation);
  const moveEventStart = productionEvents.mark();
  const moveInputStart = playerInputs.mark();
  const heldRallyObservations = await holdBridgeTarget(
    page, playerInputs, deanFloorChoice, deanRallyCapability,
  );
  const deanArrival = await collectPlayerObservationsUntil(
    page,
    'Dean sees the full party move and settle on the chosen unsafe floor',
    (observation, samples) =>
      movedVisiblePartyTokens(enterBowlObservation, observation).length === deanRosterTokens.length
        && visiblePartyIsStable(samples, deanBodyTokens)
        && hasCompleteVisibleMovementLineage(
          samples, deanFloorChoice.token, deanRosterTokens, deanMovementPresentationBaseline,
        ),
    60_000,
    enterBowlObservation.capture_serial,
  );
  const enterBowlAfterObservation = deanArrival.observationAfter;
  const enterBowlSamples = normalizeObservationSamples([
    ...heldRallyObservations, ...deanArrival.observationSamples,
  ]);
  // Mechanism/transform state is a post-observation oracle only; it never decides
  // when to release Rally or what Dean does next.
  await waitForMovementSampleGrowth(
    page, deanRallyOracle, PARTY, ordinaryMovementBaselines,
    'pointless Rally into the unsafe low floor');
  await waitForState(page, deanRallyOracle,
    'the visible party settles on the unsafe low floor before the first fill',
    (next) => PARTY.every((id) => next.characters?.[id]?.level === 0
      && !next.characters?.[id]?.committed && !next.characters?.[id]?.moving),
    // A far but visibly ordinary floor target can require ~7 simulation seconds.
    // Exported-frame observation runs slower than wall time on the Web gate, so
    // preserve the route instead of biasing Dean toward a nearby test target.
    60_000,
  );
  state = await bridgeState(page, deanRallyOracle);
  playerObservation(state, 'Dean bowl arrival mechanism oracle');
  expect(distanceXZ(state.characters.aster.logical_position, initialAsterPosition),
    'Dean\'s visible Rally actually leaves Aster\'s safe start').toBeGreaterThan(2.5);
  const enterBowlReceipt = trace.keyboardPointerReceipt({
    verb: 'rally',
    consoleEvents: productionMessagesAfter(productionEvents, moveEventStart),
    inputEvents: playerInputs.after(moveInputStart),
    intendedMembers: intendedRallyMembers,
    targetToken: deanFloorChoice.token,
    input: 'one held RMB canvas gesture at the chosen visible affordance',
  });
  expect(enterBowlReceipt.production_event_count,
    'Dean\'s held gesture emits exactly one production rally_members command').toBe(1);
  expect(enterBowlReceipt.atomic_group, 'Dean\'s Rally is not decomposed into singleton moves')
    .toBe(true);
  const enterBowlRecord = trace.record({
    observationBefore: enterBowlObservation,
    observationAfter: enterBowlAfterObservation,
    observationSamples: enterBowlSamples,
    rationale: {
      text: 'Dean ignores DECK ACCESS and rallies everyone toward an arbitrary visibly sweep-risky floor patch.',
      policy_nodes: ['dean_takahashi_rally_unmarked_visible_floor'],
    },
    decision: {
      verb: 'rally',
      intended_subjects: intendedRallyMembers,
      target: {
        kind: 'visible_affordance',
        token: deanFloorChoice.token,
        screen: deanFloorChoice.screen,
      },
    },
    inputReceipt: enterBowlReceipt,
    // The attempt itself is always retained as trace evidence. The writer only
    // attaches this policy candidate after the exact accepted route visibly
    // arrives; a refused or interrupted attempt cannot reserve the node.
    learningCandidate: rallyCandidate('dean_takahashi', deanFloorChoice),
  });
  expectLearningEligible(enterBowlRecord, 'Dean visible-floor Rally');
  expect(forcedMovementRecords(state),
    'ordinary Rally movement does not impersonate an involuntary consequence').toEqual([]);
  for (const id of PARTY) {
    expectMovementPresentationParity(
      state, id, 'ordinary bowl arrival', ordinaryMovementBaselines[id]);
    expectMovementContinuity(
      state, id, 'ordinary non-portal whole-party Rally',
      ordinaryContinuityBaselines[id],
      { category: 'navigation', kind: 'continuous_route', type: 'walk' });
    expectPresentationParity(state, id, 'ordinary bowl arrival', 0.0);
  }
  const carryMovementBaselines = await snapshotMovementCountsBeforeLaunch(
    page, deanRallyOracle, PARTY, 'missed-rise carry');
  const carryContinuityBaselines = await snapshotMovementContinuityBeforeLaunch(
    page, deanRallyOracle, PARTY, 'missed-rise carry');
  const idleInBowlObservation = await waitForPlayerObservation(
    page,
    'Dean receives a fresh pre-wait observation after the Rally decision',
    (observation) => observation.capture_serial > enterBowlAfterObservation.capture_serial,
    15_000,
  );
  const warningWaitCapability = authorizePassiveObservationDecision(
    playerInputs, idleInBowlObservation, 'Dean visible rise warning wait',
  );
  const warningWaitOracle = postChoiceAssertionOracle(warningWaitCapability);

  const warningEventStart = productionEvents.mark();
  const warningJourney = await collectPlayerObservationsUntil(
    page,
    'rising water exposes a player-visible warning before commitment',
    (observation) => Boolean(visibleCue(observation, /BASIN RISING|CURRENT RETURNS TO START/i)),
    45_000,
    idleInBowlObservation.capture_serial,
  );
  const warningObservation = warningJourney.observationAfter;
  const warningBackgroundValidation = validateBackgroundEventPresentation({
    observationBefore: idleInBowlObservation,
    observationAfter: warningObservation,
    observationSamples: warningJourney.observationSamples,
    consoleEvents: productionMessagesAfter(productionEvents, warningEventStart),
  });
  expect(warningBackgroundValidation.ok,
    'any authoritative work during Dean\'s passive warning wait has a new rendered cue').toBe(true);
  await waitForState(page, warningWaitOracle,
    'warning also carries its exact consequence oracle', (next) => {
    const warning = findFeedbackRecord(next, 'warning', {
      phase: 'warning',
      mode: 'warning',
      cause_id: 'basin:bf',
      cause_kind: 'rising_water',
      effect_kind: 'hazard_transition',
      cue_kind: 'basin_level_warning',
    });
    return Boolean(warning?.visible
      && warning.sample_count > 1
      && warning.visible_sample_count > 1
      && warning.render_visible
      && warning.render_visible_sample_count > 1
      && !next.characters?.aster?.committed);
  }, 15_000);
  state = await bridgeState(page, warningWaitOracle);
  const warning = findFeedbackRecord(state, 'warning', {
    phase: 'warning',
    cause_id: 'basin:bf',
    effect_kind: 'hazard_transition',
    cue_kind: 'basin_level_warning',
  });
  expect(warning, 'the warning record remains available for semantic inspection').toBeTruthy();
  expect(warning.destination_label).toBe('START / CURRENT RETURN');
  expect(warning.label).toContain('BASIN RISING');
  expect(state.consequence_feedback.active_count,
    'warning is sampled before the forced movement exists').toBe(0);
  const consequenceEventId = warning.event_id;
  expect(consequenceEventId, 'warning has a stable causal event id').not.toBe('');
  const warningWaitReceipt = trace.observedInputReceipt({
    verb: 'wait',
    input: 'no input while the production scheduler advances',
    boundary: 'player_command',
    backgroundValidation: warningBackgroundValidation,
  });
  expect(warningWaitReceipt.production_event_count,
    'Dean\'s passive warning wait emits no player-command production event').toBe(0);
  const warningRecord = trace.record({
    observationBefore: idleInBowlObservation,
    observationAfter: warningObservation,
    observationSamples: warningJourney.observationSamples,
    rationale: {
      text: 'Dean waits in place instead of checking the rota or seeking higher ground.',
      policy_nodes: ['dean_takahashi_repeat_without_learning'],
    },
    decision: {
      verb: 'wait',
      intended_subjects: [],
      target: { kind: 'none', token: '' },
    },
    inputReceipt: warningWaitReceipt,
  });
  expectLearningEligible(warningRecord, 'Dean visible rise warning');

  const sweepEventStart = productionEvents.mark();
  const sweepStartObservation = await waitForPlayerObservation(
    page,
    'Dean receives a fresh pre-consequence observation after the warning decision',
    (observation) => observation.capture_serial > warningObservation.capture_serial,
    15_000,
  );
  const forcedReturnWaitCapability = authorizePassiveObservationDecision(
    playerInputs, sweepStartObservation, 'Dean visible forced-return wait',
  );
  const forcedReturnWaitOracle = postChoiceAssertionOracle(forcedReturnWaitCapability);

  const sweepJourney = await collectPlayerObservationsUntil(
    page,
    'every visible party portrait receives active and arrival SWEPT feedback',
    (_observation, samples) =>
      sweepPhaseTokens(samples, 'active', deanRosterTokens).size === deanRosterTokens.length
        && sweepPhaseTokens(samples, 'arrival', deanRosterTokens).size === deanRosterTokens.length
        && visiblePartyIsStable(samples, deanBodyTokens),
    45_000,
    sweepStartObservation.capture_serial,
  );
  const forcedReturnObservation = sweepJourney.observationAfter;
  const sweepBackgroundValidation = validateBackgroundEventPresentation({
    observationBefore: sweepStartObservation,
    observationAfter: forcedReturnObservation,
    observationSamples: sweepJourney.observationSamples,
    consoleEvents: productionMessagesAfter(productionEvents, sweepEventStart),
    expectedRosterTokens: deanRosterTokens,
    expectedLabel: 'SWEPT',
    expectedDestination: 'START / CURRENT RETURN',
  });
  expect(sweepBackgroundValidation,
    'the background sweep is valid only when every visible portrait gets active and arrival cues')
    .toMatchObject({
      ok: true,
      causal_cue_delta_visible: true,
      subject_lineages: deanRosterTokens.map((sourceToken) => ({
        source_tokens: [sourceToken],
        active_visible: true,
        arrival_visible: true,
      })),
      failures: [],
    });
  expect(sweepBackgroundValidation.event_count,
    'the post-hoc sweep validator sees authoritative background mutations').toBeGreaterThan(0);
  expect(sweepBackgroundValidation.event_kinds,
    'the authoritative interval includes external traversal commits').toContain(
    'begin_external_traversal',
  );
  expect(sweepBackgroundValidation.player_facing_traversal_count,
    'each visible roster member has a player-facing traversal receipt')
    .toBeGreaterThanOrEqual(deanRosterTokens.length);
  const persistedSweepValidation = JSON.stringify(sweepBackgroundValidation);
  for (const privateValue of [...PARTY, consequenceEventId, 'event_id', 'traversal_id']) {
    expect(persistedSweepValidation,
      `Web sweep validation never persists private identifier ${privateValue}`)
      .not.toContain(privateValue);
  }
  const activeCarryObservation = sweepJourney.observationSamples.find((observation) =>
    sweepPhaseTokens([observation], 'active', deanRosterTokens).size > 0);
  expect(activeCarryObservation,
    'the persisted observation samples retain the transient active carry cue').toBeTruthy();
  expect(sweepPhaseTokens(sweepJourney.observationSamples, 'active', deanRosterTokens).size,
    'active SWEPT feedback names the whole visible roster').toBe(deanRosterTokens.length);
  expect(sweepPhaseTokens(sweepJourney.observationSamples, 'arrival', deanRosterTokens).size,
    'arrival SWEPT feedback names the whole visible roster').toBe(deanRosterTokens.length);

  await waitForMovementSampleGrowth(
    page, forcedReturnWaitOracle, PARTY, carryMovementBaselines,
    'visible missed-rise current carry');
  state = await waitForState(page, forcedReturnWaitOracle,
    'mechanism agrees with the visible whole-party return', (next) =>
    next.chunk?.basin_states?.[0]?.swept_party === PARTY.length
      && PARTY.every((id) => !next.characters?.[id]?.committed
        && distance3(next.characters[id].logical_position, initialPartyPositions[id]) < 0.15),
  20_000);
  expect(state.chunk?.basin_states?.[0]?.swept_party,
    'the authored failure counts each rallied party member exactly once').toBe(PARTY.length);
  expect(
    [...new Set(forcedMovementRecords(state)
      .map((record) => record.subject_id)
      .filter((id) => PARTY.includes(id)))].sort(),
    'the forced-current presentation names every rallied party member',
  ).toEqual([...PARTY].sort());
  for (const id of PARTY) {
    const arrival = findFeedbackRecord(state, 'recent', {
      phase: 'arrival', event_id: consequenceEventId, subject_id: id,
      effect_kind: 'forced_movement', traversal_id: `channel_sweep/bf_carry/${id}`,
    });
    expect(arrival, `${id}'s arrival remains causally linked to the basin event`).toBeTruthy();
    expect(arrival.destination_label,
      `${id}'s destination is named to the player`).toBe('START / CURRENT RETURN');
    expect(distance3(arrival.destination, initialPartyPositions[id]),
      `${id}'s arrival cue terminates at that character's authored recovery vertex`).toBeLessThan(0.05);
    expect(distanceXZ(arrival.destination, startReturn),
      `${id}'s recovery vertex remains on the advertised CURRENT RETURN shelf`).toBeLessThan(2.5);
    expectMovementPresentationParity(
      state, id, 'completed missed-rise current carry', carryMovementBaselines[id]);
    expectMovementContinuity(
      state, id, 'completed missed-rise current carry',
      carryContinuityBaselines[id],
      { category: 'external_traversal', kind: 'forced_movement', type: 'current_carry' });
    expectPresentationParity(state, id, 'completed missed-rise current carry', 0.0);
  }
  expect(state.move_refusals, 'real failure-path canvas movement is accepted').toEqual([]);
  expect(runtimeFailures, 'the exported failure journey emits no runtime errors').toEqual([]);
  playerObservation(state, 'Dean forced-return mechanism oracle');
  const forcedReturnWaitReceipt = trace.observedInputReceipt({
    verb: 'wait',
    input: 'no corrective input',
    boundary: 'player_command',
    backgroundValidation: sweepBackgroundValidation,
  });
  expect(forcedReturnWaitReceipt,
    'the sweep remains validation-only rather than becoming a hidden player command')
    .toMatchObject({
      production_event_count: 0,
      production_event_kinds: [],
      validation_background_event_count: sweepBackgroundValidation.event_count,
      validation_background_event_kinds: sweepBackgroundValidation.event_kinds,
      validation_background_visual_lineage: { ok: true },
    });
  const forcedReturnRecord = trace.record({
    observationBefore: sweepStartObservation,
    observationAfter: forcedReturnObservation,
    observationSamples: sweepJourney.observationSamples,
    rationale: {
      text: 'Dean sees BASIN RISING and still does nothing; he never repairs the mistake or teleports home.',
      policy_nodes: ['dean_takahashi_ignore_visible_warning'],
    },
    decision: {
      verb: 'wait',
      intended_subjects: [],
      target: { kind: 'visible_cue', token: '', text: 'BASIN RISING' },
    },
    inputReceipt: forcedReturnWaitReceipt,
  });
  expectLearningEligible(forcedReturnRecord, 'Dean visible full-party sweep consequence');
  trace.finish({ trace_complete: true, swept_party: PARTY.length });
  expect(trace.records.at(-1).summary.persona_goal_reached,
    'Dean goal is derived from the visible full-roster SWEPT lineage').toBe(true);
  expect(trace.records.at(-1).summary.trace_complete,
    'Dean trace is complete only when every decision is independently eligible').toBe(true);
  await trace.save(testInfo);
});

test('EazySpeezy records a legal Basin clear through real Web input', async ({ page }, testInfo) => {
  const runtimeFailures = [];
  const productionEvents = captureProductionEvents(page);
  const playerInputs = capturePlayerInput(page);
  page.on('pageerror', (error) => runtimeFailures.push(`pageerror: ${error.message}`));
  page.on('console', (message) => {
    const messageText = message.text();
    if (message.type() === 'error' || message.type() === 'assert') {
      runtimeFailures.push(`console.${message.type()}: ${messageText}`);
    }
  });

  await page.goto('/index.html?e2e=1&fragment=basin_fill_proof');
  await waitForBootState(page, 'main menu exposes its real Fragments button', (state) =>
    state.stage === 'main_menu' && state.ready && state.click_targets?.fragments?.visible,
  );
  await clickBridgeTarget(page, 'fragments', 'left');

  await waitForBootState(page, 'the authored Basin preview finishes booting', (state) =>
    state.stage === 'fragment'
      && state.ready
      && state.fragment === 'basin_fill_proof'
      && PARTY.every((id) => state.characters?.[id]),
    45_000,
  );
  const traceRun = personaTraceRun(testInfo);
  const instructionsObservation = await currentPlayerObservation(
    page, 'Eazy visible instructions before hiding them');
  const visibleInstructionTexts = (instructionsObservation?.state?.cues ?? [])
    .filter((cue) => cue?.kind === 'instruction' && cue?.visible === true)
    .map((cue) => String(cue?.text ?? ''));
  const visiblePanHint = visibleInstructionTexts.find((text) =>
    /\bW\b.*\bA\b.*\bS\b.*\bD\b.*\bPAN\b/i.test(text));
  const visibleHideHint = visibleInstructionTexts.find((text) =>
    /\bH\b.*\bHIDE\b|\bHIDE\b.*\bH\b/i.test(text));
  expect(visiblePanHint,
    'the observation projects the same currently rendered W/A/S/D Pan chip a human reads')
    .toBeTruthy();
  expect(visibleHideHint,
    'the observation projects the same currently rendered H Hide chip a human reads')
    .toBeTruthy();
  expect(JSON.stringify(instructionsObservation),
    'rendered hint projection leaks no private InputMap/action/command identifiers')
    .not.toMatch(/camera_pan_(?:forward|back|left|right)|preview_toggle_instructions|select_primary|ability_secondary|InputMap|command_move_to_pos|headless_/i);
  const instructionCue = chooseVisibleCue(
    instructionsObservation, /\bH\b.*\bHIDE\b|\bHIDE\b.*\bH\b/i,
  );
  expect(instructionCue,
    'Eazy sees the advertised H Hide control before issuing it').toBeTruthy();
  expect(instructionCue.kind, 'the advertised H control comes from the instruction surface')
    .toBe('instruction');
  const hideCapability = authorizePersonaAction(
    playerInputs, instructionsObservation, instructionCue, {
      gesture: 'key_press', key: 'h', targetToken: 'visible_h_hide_control',
    }, 'Eazy visible instruction hide',
  );
  const hideOracle = postChoiceAssertionOracle(hideCapability);
  let state = await bridgeState(page, hideOracle);
  expect(state.chunk?.complete).toBe(false);
  expect(state.active_character).toBe('aster');
  expect(sameMembers(state.selected_characters, ['aster'])).toBe(true);
  for (const id of PARTY) {
    expect(state.characters[id].level, `${id} begins at the authored low-floor spawn`).toBe(0);
    expect(state.characters[id].downed, `${id} begins conscious`).toBe(false);
    expectPresentationParity(state, id, 'authored Basin spawn', 0.0);
    expect(movementSampleCount(state, id, 'authored Basin spawn'),
      `${id}'s idle boot samples do not count as movement coverage`).toBe(0);
  }
  expectConnectedLadderGraph(state, 'authored Basin spawn');

  const eazyProvenance = contentFingerprint(state);
  const trace = new PersonaDecisionTrace({
    persona: 'eazy_speezy',
    fragmentId: 'basin_fill_proof',
    ...eazyProvenance,
    ...traceRun,
  });
  expect({
    contentFingerprintSchema: trace.run.content_fingerprint_schema,
    contentFingerprint: trace.run.content_fingerprint,
    gameplayBuildFingerprintSchema: trace.run.gameplay_build_fingerprint_schema,
    gameplayBuildFingerprint: trace.run.gameplay_build_fingerprint,
  }, 'Eazy trace provenance is the exact exported bridge identity').toEqual(eazyProvenance);

  // Read and use the rendered H control exactly as a person would. Keep the separate F4 overlay
  // untouched: it is unnecessary for this route, and every issued player command belongs in the trace.
  const hideInputStart = playerInputs.mark();
  await pressObservedKey(
    playerInputs, 'h', instructionCue, 'visible_h_hide_control', hideCapability,
  );
  const hiddenInstructions = await collectPlayerObservationsUntil(
    page,
    'the rendered instructions and their exact hint projections visibly disappear after H',
    (observation) => !(observation?.state?.cues ?? []).some((cue) =>
      cue?.kind === 'instruction' && cue?.visible === true
        && [instructionCue.text, visiblePanHint, visibleHideHint].includes(cue?.text)),
    8_000,
    instructionsObservation.capture_serial,
  );
  const hiddenInstructionsObservation = hiddenInstructions.observationAfter;
  expect((hiddenInstructionsObservation?.state?.cues ?? []).filter((cue) =>
    cue?.kind === 'instruction' && cue?.visible === true
      && [visiblePanHint, visibleHideHint].includes(cue?.text)),
    'hidden or clipped hint chips cannot remain player-observable').toEqual([]);
  const hideRecord = trace.record({
    observationBefore: instructionsObservation,
    observationAfter: hiddenInstructionsObservation,
    observationSamples: hiddenInstructions.observationSamples,
    rationale: {
      text: 'Eazy hides the visible instruction panel after reading it so the board is unobstructed.',
      policy_nodes: ['hide_instructions_when_they_occlude_the_board'],
    },
    decision: {
      verb: 'toggle_instructions', intended_subjects: [],
      target: { kind: 'visible_cue', token: 'visible_h_hide_control', text: instructionCue.text },
    },
    inputReceipt: trace.observedInputReceipt({
      verb: 'toggle_instructions', input: 'one production H key press',
      boundary: 'keyboard_pointer',
      inputEvents: playerInputs.after(hideInputStart),
    }),
    learningCandidate: hideInstructionsCandidate(instructionCue),
  });
  expectLearningEligible(hideRecord, 'Eazy visible instruction-panel hide');

  const authoredArrivalObservation = await waitForPlayerObservation(
    page,
    'Eazy receives a fresh authored-arrival observation after hiding instructions',
    (observation) => observation.capture_serial > hiddenInstructionsObservation.capture_serial,
    15_000,
  );
  const eazyBodyTokens = visiblePartyBodyTokens(authoredArrivalObservation);
  expect(eazyBodyTokens.length,
    'Eazy sees one body token per visible party member at authored spawn').toBe(PARTY.length);

  // Match the Windowed persona's first human decision: watch the visible party
  // finish its authored arrival before issuing a group command.
  const authoredSettleEventStart = productionEvents.mark();
  const authoredSettle = await collectPlayerObservationsUntil(
    page,
    'the visible authored party settles before Eazy rallies',
    (_observation, samples) => visiblePartyIsStable(samples, eazyBodyTokens),
    8_000,
    authoredArrivalObservation.capture_serial,
  );
  const authoredSettledObservation = authoredSettle.observationAfter;
  const authoredSettleBackgroundValidation = validateBackgroundEventPresentation({
    observationBefore: authoredArrivalObservation,
    observationAfter: authoredSettledObservation,
    observationSamples: authoredSettle.observationSamples,
    consoleEvents: productionMessagesAfter(productionEvents, authoredSettleEventStart),
  });
  expect(authoredSettleBackgroundValidation.ok,
    'authored-arrival background work cannot settle without a rendered causal cue').toBe(true);
  const authoredSettleWaitReceipt = trace.observedInputReceipt({
    verb: 'wait', input: 'no input while the visible authored arrival settles',
    boundary: 'player_command',
    backgroundValidation: authoredSettleBackgroundValidation,
  });
  expect(authoredSettleWaitReceipt.production_event_count,
    'the authored-arrival wait remains a passive player command').toBe(0);
  const authoredWaitRecord = trace.record({
    observationBefore: authoredArrivalObservation,
    observationAfter: authoredSettledObservation,
    observationSamples: authoredSettle.observationSamples,
    rationale: {
      text: 'Eazy watches the visible party finish its authored arrival before issuing the first group command.',
      policy_nodes: ['wait_for_visible_party_arrival_before_rally'],
    },
    decision: {
      verb: 'wait', intended_subjects: [],
      target: { kind: 'visible_party', token: '' },
    },
    inputReceipt: authoredSettleWaitReceipt,
  });
  expectLearningEligible(authoredWaitRecord, 'Eazy visible authored-arrival wait');

  const ladderObservation = await waitForPlayerObservation(
    page,
    'Eazy receives a fresh pre-Rally observation after the authored-arrival wait',
    (observation) => observation.capture_serial > authoredSettledObservation.capture_serial
      && Boolean(chooseVisibleLadderRoute(observation)),
    15_000,
  );

  // A held command is whole-party intent independent of portrait selection. Exercise the production
  // gesture once and require every member to receive a distinct target-floor route. The policy picks
  // a human-visible upper-screen route affordance; graph levels and authored anchors are oracles only.
  const rallyChoice = chooseVisibleLadderRoute(ladderObservation);
  expect(rallyChoice, 'Eazy sees a route affordance toward the marked deck access').toBeTruthy();
  expect(rallyChoice.kind).toBe('move');
  expect(rallyChoice.consequence, 'Eazy acts on the visible ladder annotation, not hidden levels')
    .toMatch(/LADDER/i);
  const ladderRallyCapability = authorizePersonaAction(
    playerInputs, ladderObservation, rallyChoice, {
      gesture: 'pointer_hold', button: 'right', targetToken: rallyChoice.token,
    }, 'Eazy upper-deck Rally',
  );
  const ladderRallyOracle = postChoiceAssertionOracle(ladderRallyCapability);
  const intendedRallyMembers = visibleSubjectIds(ladderObservation);
  const eazyRallyRosterTokens = visibleRosterTokens(ladderObservation);
  expect(sameMembers(intendedRallyMembers, PARTY),
    'the Rally intent covers every conscious portrait visible to the player').toBe(true);
  const ladderAcceptanceCounts = await snapshotMovementCountsBeforeLaunch(
    page, ladderRallyOracle, PARTY, 'whole-party upper-deck Rally');
  const ladderContinuityBaselines = await snapshotMovementContinuityBeforeLaunch(
    page, ladderRallyOracle, PARTY, 'whole-party upper-deck Rally');
  const ladderMovementPresentationBaseline = highestVisibleMovementSerial(ladderObservation);
  const rallyEventStart = productionEvents.mark();
  const rallyInputStart = playerInputs.mark();
  const heldRallyObservations = await holdBridgeTarget(
    page, playerInputs, rallyChoice, ladderRallyCapability,
  );
  const ladderJourney = await collectPlayerObservationsUntil(
    page,
    'the whole visible party settles where ARM NEXT MID can be read',
    (observation, samples) =>
      movedVisiblePartyTokens(ladderObservation, observation).length === eazyBodyTokens.length
        && visiblePartyIsStable(samples, eazyBodyTokens)
        && hasCompleteVisibleMovementLineage(
          samples, rallyChoice.token, eazyRallyRosterTokens,
          ladderMovementPresentationBaseline,
        )
        && Boolean(chooseVisibleInteraction(observation, /\bARM NEXT MID\b/i)),
    45_000,
    ladderObservation.capture_serial,
  );
  const ladderArrivalObservation = ladderJourney.observationAfter;
  const ladderSamples = normalizeObservationSamples([
    ...heldRallyObservations, ...ladderJourney.observationSamples,
  ]);
  // Graph levels and transforms corroborate the already-visible arrival.
  await waitForMovementSampleGrowth(
    page, ladderRallyOracle, PARTY, ladderAcceptanceCounts, 'whole-party upper-deck Rally');
  await waitForState(page, ladderRallyOracle,
    'all three authored climb routes reach the upper deck', (next) =>
    PARTY.every((id) => next.characters[id]?.level === 1
      && !next.characters[id]?.committed && !next.characters[id]?.moving),
    40_000,
  );
  state = await bridgeState(page, ladderRallyOracle);
  for (const id of PARTY) {
    expectPresentationParity(state, id, 'upper-deck ladder arrival', 2.7);
    expectMovementPresentationParity(
      state, id, 'upper-deck ladder arrival', ladderAcceptanceCounts[id]);
    expectMovementContinuity(
      state, id, 'whole-party typed-ladder Rally', ladderContinuityBaselines[id],
      { type: 'ladder' });
    expectAnnotatedLevelTransitions(state, id, 'upper-deck ladder arrival', true);
  }
  const rallyArrivalVertices = new Set(PARTY.map((id) => {
    const pos = state.characters[id].logical_position;
    return pos.x.toFixed(2) + ':' + pos.y.toFixed(2) + ':' + pos.z.toFixed(2);
  }));
  expect(rallyArrivalVertices.size, 'Rally settles on three distinct upper-level vertices').toBe(3);
  expect(sameMembers(state.selected_characters, ['aster']),
    'Rally preserves singleton portrait selection after arrival').toBe(true);
  playerObservation(state, 'Eazy upper-deck mechanism oracle');
  const rallyReceipt = trace.keyboardPointerReceipt({
    verb: 'rally',
    consoleEvents: productionMessagesAfter(productionEvents, rallyEventStart),
    inputEvents: playerInputs.after(rallyInputStart),
    intendedMembers: intendedRallyMembers,
    targetToken: rallyChoice.token,
    input: 'one held RMB canvas gesture at the chosen visible affordance',
  });
  expect(rallyReceipt.production_event_count,
    'the receipt counts the production rally_members event instead of declaring one').toBe(1);
  expect(rallyReceipt.atomic_group, 'Rally stayed one production group verb').toBe(true);
  expect(Object.values(rallyReceipt.member_results),
    'the production Rally event names every intended portrait').toEqual(['accepted', 'accepted', 'accepted']);
  const rallyRecord = trace.record({
    observationBefore: ladderObservation,
    observationAfter: ladderArrivalObservation,
    observationSamples: ladderSamples,
    rationale: {
      text: 'Eazy reads the visible instructions and rallies the full party toward the marked DECK ACCESS target.',
      policy_nodes: ['eazy_speezy_rally_marked_deck_access'],
    },
    decision: {
      verb: 'rally',
      intended_subjects: intendedRallyMembers,
      target: {
        kind: 'visible_affordance',
        token: rallyChoice.token,
        screen: rallyChoice.screen,
      },
    },
    inputReceipt: rallyReceipt,
    // Keep the canonical node shape byte-for-byte aligned with the Native
    // persona controller so equivalent cross-platform evidence coalesces.
    learningCandidate: rallyCandidate('eazy_speezy', rallyChoice),
  });
  expectLearningEligible(rallyRecord, 'Eazy whole-party Rally');

  // Rebuild full-party selection from the visible portrait roster with the same
  // primary-then-additive number-key sequence a person uses.
  const selectionObservation = await waitForPlayerObservation(
    page,
    'Eazy receives a fresh pre-selection observation after the Rally decision',
    (observation) => observation.capture_serial > ladderArrivalObservation.capture_serial,
    15_000,
  );
  const selectionInputStart = playerInputs.mark();
  const groupSelectionInput = await selectFullVisiblePartyFromPortraits(
    playerInputs, selectionObservation,
  );
  expect(groupSelectionInput.acted,
    'the upper-deck HUD requires a real full-party selection change').toBe(true);
  const groupSelectionOracle = postChoiceAssertionOracle(
    groupSelectionInput.actionCapability,
  );
  let eazyActiveSubject = groupSelectionInput.activeSubject;
  const groupSelection = await collectPlayerObservationsUntil(
    page,
    'the portrait HUD visibly shows the whole party selected',
    (observation) => (observation?.state?.hud?.portraits ?? [])
      .filter((portrait) => portrait?.visible !== false).every((portrait) => portrait.selected === true),
    8_000,
    selectionObservation.capture_serial,
  );
  const groupSelectedObservation = groupSelection.observationAfter;
  await waitForState(page, groupSelectionOracle,
    'selection mechanism agrees with the portrait HUD', (next) =>
    next.active_character === eazyActiveSubject && sameMembers(next.selected_characters, PARTY), 8_000);
  const selectionMembers = visibleSubjectIds(selectionObservation);
  const selectionRecord = trace.record({
    observationBefore: selectionObservation,
    observationAfter: groupSelectedObservation,
    observationSamples: groupSelection.observationSamples,
    rationale: {
      text: 'Eazy sees two unselected conscious portraits and adds them before using the party crossing tech.',
      policy_nodes: ['eazy_speezy_select_full_visible_roster'],
    },
    decision: {
      verb: 'select_party',
      intended_subjects: selectionMembers,
      target: { kind: 'hud_portraits', token: 'hud_portraits' },
    },
    inputReceipt: trace.observedInputReceipt({
      verb: 'select_party',
      input: groupSelectionInput.input,
      boundary: 'keyboard_pointer',
      inputEvents: playerInputs.after(selectionInputStart),
      intendedMembers: selectionMembers,
      memberResults: selectedVisibleMemberResults(
        selectionObservation, groupSelectedObservation,
      ),
    }),
    learningCandidate: selectVisibleRosterCandidate(selectionObservation),
  });
  expectLearningEligible(selectionRecord, 'Eazy visible full-party selection');

  const consoleObservation = await waitForPlayerObservation(
    page,
    'Eazy receives a fresh pre-console observation after selecting the party',
    (observation) => observation.capture_serial > groupSelectedObservation.capture_serial
      && Boolean(chooseVisibleInteraction(observation, /\bARM NEXT MID\b/i)),
    15_000,
  );
  const consoleChoice = chooseVisibleInteraction(
    consoleObservation,
    /\bARM NEXT MID\b/i,
  );
  expect(consoleChoice,
    'Eazy can identify the crossing leverage point from its visible action text').toBeTruthy();
  expect(consoleChoice.verb, 'Eazy does not confuse the visible ROTA chart with the crossing console')
    .toMatch(/\bARM NEXT MID\b/i);
  const consoleCapability = authorizePersonaAction(
    playerInputs, consoleObservation, consoleChoice, {
      gesture: 'pointer_click', button: 'right', targetToken: consoleChoice.token,
    }, 'Eazy crossing console interaction',
  );
  const consoleOracle = postChoiceAssertionOracle(consoleCapability);
  const consoleMembers = visibleSubjectIds(consoleObservation);
  expect(sameMembers(consoleMembers, PARTY),
    'the visible crossing decision covers the complete authored roster').toBe(true);
  const consoleResultBaseline = highestVisibleInteractionSerial(
    consoleObservation, consoleChoice.token,
  );
  const consoleEventStart = productionEvents.mark();
  const consoleInputStart = playerInputs.mark();
  await clickObservedAffordance(page, playerInputs, consoleChoice, consoleCapability);
  const consoleDispatch = await collectPlayerObservationsUntil(
    page,
    'the crossing console presents both exact-target success and staging feedback',
    (observation) => Boolean(visibleCue(observation, /CROSSING STAGING.*FULL GROUP/i))
      && newestVisibleInteractionResult(
        observation, consoleChoice.token, consoleResultBaseline,
      )?.result === 'success',
    30_000,
    consoleObservation.capture_serial,
  );
  const consoleStagingObservation = consoleDispatch.observationAfter;
  await page.waitForTimeout(350);
  expect(visibleCue(await currentPlayerObservation(page, 'persistent crossing receipt'),
    /CROSSING STAGING.*FULL GROUP/i),
  'CROSSING STAGING remains on the visible status surface while the party walks').toBeTruthy();
  await waitForState(page, consoleOracle,
    'the physical FlowReadConsole is staging, not prematurely armed', (next) =>
    next.assist_phase === 'staging' && next.assist_armed === false,
    15_000,
  );
  state = await bridgeState(page, consoleOracle);
  const consoleReceipt = trace.keyboardPointerReceipt({
    verb: 'interact',
    consoleEvents: productionMessagesAfter(productionEvents, consoleEventStart),
    inputEvents: playerInputs.after(consoleInputStart),
    intendedMembers: consoleMembers,
    targetToken: consoleChoice.token,
    input: 'one RMB canvas click at the chosen visible interaction affordance',
  });
  expect(consoleReceipt.status, 'the visible console click emitted its production consequence')
    .toBe('accepted');
  expect(consoleReceipt.production_event_count,
    'the crossing console stages the selected party with one atomic production command').toBe(1);
  expect(consoleReceipt.production_event_kinds,
    'the direct crossing-assist interaction is receipted by its authored group consequence')
    .toEqual(['rally_members']);
  expect(consoleReceipt.atomic_group,
    'the console stages the exact intended roster as one atomic group consequence').toBe(true);
  expect(consoleReceipt.member_results,
    'the console staging event accepts every intended party member').toEqual({
    aster: 'accepted', peris: 'accepted', endo: 'accepted',
  });
  const consoleRecord = trace.record({
    observationBefore: consoleObservation,
    observationAfter: consoleStagingObservation,
    observationSamples: consoleDispatch.observationSamples,
    rationale: {
      text: 'Eazy prioritizes the visible UPPER DECK > ARM NEXT MID prompt before wandering to another floor target.',
      policy_nodes: ['eazy_speezy_arm_visible_mid_console'],
    },
    decision: {
      verb: 'interact',
      intended_subjects: consoleMembers,
      target: {
        kind: 'visible_affordance',
        token: consoleChoice.token,
        screen: consoleChoice.screen,
      },
    },
    inputReceipt: consoleReceipt,
    learningCandidate: interactionCandidate('eazy_speezy', consoleChoice.verb),
  });
  expectLearningEligible(consoleRecord, 'Eazy visible crossing assist');

  const armingStartObservation = await waitForPlayerObservation(
    page,
    'Eazy receives a fresh pre-wait observation after the console decision',
    (observation) => observation.capture_serial > consoleStagingObservation.capture_serial
      && Boolean(visibleCue(observation, /CROSSING STAGING|CROSSING ARMED|NEXT MID/i)),
    15_000,
  );

  const consoleArmingEventStart = productionEvents.mark();
  const consoleArming = await collectPlayerObservationsUntil(
    page,
    'the console arms only after the full party visibly reaches the safe hold line',
    (observation) => Boolean(visibleCue(observation, /CROSSING ARMED.*NEXT MID/i)),
    45_000,
    armingStartObservation.capture_serial,
  );
  const consoleArmedObservation = consoleArming.observationAfter;
  const consoleArmingBackgroundValidation = validateBackgroundEventPresentation({
    observationBefore: armingStartObservation,
    observationAfter: consoleArmedObservation,
    observationSamples: consoleArming.observationSamples,
    consoleEvents: productionMessagesAfter(productionEvents, consoleArmingEventStart),
  });
  expect(consoleArmingBackgroundValidation.ok,
    'automatic console arming is visible whenever it mutates authoritative state').toBe(true);
  const announcedMidCue = chooseVisibleCue(
    armingStartObservation, /CROSSING STAGING|CROSSING ARMED|NEXT MID/i,
  );
  expect(announcedMidCue,
    'Eazy waits because a rendered crossing consequence is visibly in progress').toBeTruthy();
  const armingWaitCapability = authorizePassiveObservationDecision(
    playerInputs, armingStartObservation, 'Eazy crossing-arm wait',
  );
  const armingWaitOracle = postChoiceAssertionOracle(armingWaitCapability);
  await page.waitForTimeout(350);
  expect(visibleCue(await currentPlayerObservation(page, 'persistent armed receipt'),
    /CROSSING ARMED.*NEXT MID/i),
  'CROSSING ARMED remains on the visible status surface after the transition frame').toBeTruthy();
  // This is an oracle after the visible cue has already justified the persona's next decision.
  // It may prove that the presentation agrees with the mechanism, but it is never policy input.
  await waitForState(page, armingWaitOracle,
    'the physical FlowReadConsole arms the next MID crossing', (next) =>
    next.assist_phase === 'armed' && next.assist_armed === true
      && PARTY.every((id) => !next.characters[id]?.moving),
    30_000,
  );
  const armingWaitReceipt = trace.observedInputReceipt({
    verb: 'wait', input: 'no input while the selected party reaches the visible hold line',
    boundary: 'player_command',
    backgroundValidation: consoleArmingBackgroundValidation,
  });
  expect(armingWaitReceipt.production_event_count,
    'the console-arm wait remains a passive player command').toBe(0);
  const armingWaitRecord = trace.record({
    observationBefore: armingStartObservation,
    observationAfter: consoleArmedObservation,
    observationSamples: consoleArming.observationSamples,
    rationale: {
      text: 'Eazy waits for the visible CROSSING ARMED receipt before spending more time.',
      policy_nodes: ['wait_for_visible_announced_mid_crossing'],
    },
    decision: {
      verb: 'wait', intended_subjects: [],
      target: {
        kind: 'visible_cue', token: 'visible_announced_mid_crossing',
        text: String(announcedMidCue.text ?? ''),
      },
    },
    inputReceipt: armingWaitReceipt,
    learningCandidate: announcedWaitCandidate(announcedMidCue),
  });
  expectLearningEligible(armingWaitRecord, 'Eazy visible crossing-arm wait');

  // Fast-forward is itself a production input. It shortens the wall-clock wait for the already-armed
  // deterministic MID beat without bypassing the basin, scheduler, crossing, or movement systems.
  // Snapshot immediately before the automatic assisted launch, then observe movement-only sampler
  // growth independently for every intended participant. Under Web fast-forward a short traversal
  // can begin and end between the bridge's throttled publications, so `committed` is not a reliable
  // JavaScript-side acceptance edge; the persistent per-frame counter is the authoritative receipt.
  const crossingObservation = await waitForPlayerObservation(
    page,
    'Eazy receives a fresh pre-fast-forward observation after the arming wait',
    (observation) => observation.capture_serial > consoleArmedObservation.capture_serial
      && Boolean(visibleCue(observation, /CROSSING ARMED.*NEXT MID/i)),
    15_000,
  );
  const crossingFastForwardCue = chooseVisibleCue(
    crossingObservation, /CROSSING ARMED.*NEXT MID/i,
  );
  expect(crossingFastForwardCue,
    'Eazy fast-forwards only after the visible crossing announcement is present').toBeTruthy();
  const crossingFastForwardCapability = authorizePersonaAction(
    playerInputs, crossingObservation, crossingFastForwardCue, {
      gesture: 'key_hold', key: 'f', targetToken: 'visible_announced_mid_crossing',
    }, 'Eazy announced crossing fast-forward',
  );
  const crossingFastForwardOracle = postChoiceAssertionOracle(
    crossingFastForwardCapability,
  );
  const crossingLaunchBaselineCounts = await snapshotMovementCountsBeforeLaunch(
    page, crossingFastForwardOracle, PARTY, 'assisted MID crossing');
  const crossingContinuityBaselines = await snapshotMovementContinuityBeforeLaunch(
    page, crossingFastForwardOracle, PARTY, 'assisted MID crossing');
  let crossingJourney = null;
  const crossingEventStart = productionEvents.mark();
  const crossingInputStart = playerInputs.mark();
  await observedKeyDown(
    playerInputs, 'f', crossingFastForwardCue, 'visible_announced_mid_crossing',
    crossingFastForwardCapability,
  );
  try {
    crossingJourney = await collectPlayerObservationsUntil(
      page,
      'the visible party reaches and settles beside the marked shelter',
      (observation, samples) => partyVisiblyNearCue(observation, /SHELTER/i)
        && visiblePartyIsStable(samples, eazyBodyTokens),
      45_000,
      crossingObservation.capture_serial,
    );
  } finally {
    await observedKeyUp(
      playerInputs, 'f', crossingFastForwardCue, 'visible_announced_mid_crossing',
      crossingFastForwardCapability,
    );
  }
  // The complete key gesture must precede the terminal evidence capture. The
  // last held-F snapshot remains a transient sample; a newer snapshot after
  // key-up is the terminal observation bound to this decision.
  const heldCrossingTerminal = crossingJourney.observationAfter;
  const crossingAfterObservation = await waitForPlayerObservation(
    page,
    'the released F key is followed by a fresh terminal player observation',
    (observation) => observation.capture_serial > heldCrossingTerminal.capture_serial,
    15_000,
  );
  const crossingSamples = normalizeObservationSamples([
    ...crossingJourney.observationSamples,
    heldCrossingTerminal,
  ]);
  const crossingBackgroundValidation = validateBackgroundEventPresentation({
    observationBefore: crossingObservation,
    observationAfter: crossingAfterObservation,
    observationSamples: crossingSamples,
    consoleEvents: productionMessagesAfter(productionEvents, crossingEventStart),
  });
  expect(crossingBackgroundValidation.ok,
    'the automatic assisted launch has a new rendered causal cue for its background events')
    .toBe(true);
  await waitForMovementSampleGrowth(
    page, crossingFastForwardOracle, PARTY, crossingLaunchBaselineCounts,
    'assisted MID crossing', 35_000);
  await waitForState(page, crossingFastForwardOracle,
    'the assisted MID mechanism agrees with the visible south-balcony arrival',
    (next) => PARTY.every((id) => next.characters[id]?.logical_position?.z > 11.0
      && !next.characters[id]?.committed), 35_000);
  state = await bridgeState(page, crossingFastForwardOracle);
  for (const id of PARTY) {
    expectPresentationParity(state, id, 'south-balcony arrival', 2.7);
    expectMovementPresentationParity(
      state, id, 'south-balcony arrival', crossingLaunchBaselineCounts[id]);
    expectMovementContinuity(
      state, id, 'assisted MID crossing', crossingContinuityBaselines[id],
      { category: 'navigation', kind: 'continuous_route', type: 'walk' });
  }
  playerObservation(state, 'Eazy south-balcony mechanism oracle');
  const crossingWaitReceipt = trace.observedInputReceipt({
    verb: 'wait',
    input: 'held production F key',
    boundary: 'keyboard_pointer',
    inputEvents: playerInputs.after(crossingInputStart),
    backgroundValidation: crossingBackgroundValidation,
  });
  expect(crossingWaitReceipt.production_event_count,
    'the held-F wait does not claim the automatic launch as player-issued production input').toBe(0);
  const crossingRecord = trace.record({
    observationBefore: crossingObservation,
    observationAfter: crossingAfterObservation,
    observationSamples: crossingSamples,
    rationale: {
      text: 'Eazy holds the shipped fast-forward key while the already-armed legal route runs.',
      policy_nodes: ['eazy_speezy_spend_time_not_authority'],
    },
    decision: {
      verb: 'wait',
      intended_subjects: [],
      target: { kind: 'visible_wait', token: '' },
    },
    inputReceipt: crossingWaitReceipt,
  });
  expectLearningEligible(crossingRecord, 'Eazy visible assisted-crossing wait');

  const shelterApproachObservation = await waitForPlayerObservation(
    page,
    'Eazy can see the full party and the marked shelter in the same player view',
    (observation) => observation.capture_serial > crossingAfterObservation.capture_serial
      && partyVisiblyNearCue(observation, /SHELTER/i),
    15_000,
  );
  const shelterVisibleInteraction = chooseVisibleInteraction(
    shelterApproachObservation, /\bREST PARTY\b/i,
  );
  expect(shelterVisibleInteraction,
    'the shelter Rally policy is grounded in the exact visible REST PARTY verb').toBeTruthy();
  const shelterRallyChoice = shelterVisibleInteraction;
  const shelterRallyCapability = authorizePersonaAction(
    playerInputs, shelterApproachObservation, shelterRallyChoice, {
      gesture: 'pointer_hold', button: 'right', targetToken: shelterRallyChoice.token,
    }, 'Eazy shelter Rally',
  );
  const shelterRallyOracle = postChoiceAssertionOracle(shelterRallyCapability);
  const shelterRallyMembers = visibleSubjectIds(shelterApproachObservation);
  expect(sameMembers(shelterRallyMembers, PARTY),
    'the shelter Rally intent includes the full visible party').toBe(true);
  const shelterRallyBaselines = await snapshotMovementCountsBeforeLaunch(
    page, shelterRallyOracle, PARTY, 'whole-party shelter Rally');
  const shelterRallyContinuityBaselines = await snapshotMovementContinuityBeforeLaunch(
    page, shelterRallyOracle, PARTY, 'whole-party shelter Rally');
  const shelterRallyRosterTokens = visibleRosterTokens(shelterApproachObservation);
  const shelterMovementPresentationBaseline = highestVisibleMovementSerial(
    shelterApproachObservation,
  );
  const shelterRallyEventStart = productionEvents.mark();
  const shelterRallyInputStart = playerInputs.mark();
  const heldShelterRallyObservations = await holdBridgeTarget(
    page, playerInputs, shelterRallyChoice, shelterRallyCapability,
  );
  const shelterRallyJourney = await collectPlayerObservationsUntil(
    page,
    'the full visible party settles beside the shelter before REST PARTY',
    (observation, samples) => partyVisiblyNearCue(observation, /SHELTER/i)
      && visiblePartyIsStable(samples, eazyBodyTokens)
      && hasCompleteVisibleMovementLineage(
        samples, shelterRallyChoice.token, shelterRallyRosterTokens,
        shelterMovementPresentationBaseline,
      ),
    35_000,
    shelterApproachObservation.capture_serial,
  );
  const shelterRallyAfterObservation = shelterRallyJourney.observationAfter;
  await waitForMovementSampleGrowth(
    page, shelterRallyOracle, PARTY, shelterRallyBaselines,
    'whole-party shelter Rally', 35_000);
  await waitForState(page, shelterRallyOracle,
    'the full party visibly settles before REST PARTY', (next) =>
    PARTY.every((id) => !next.characters?.[id]?.committed && !next.characters?.[id]?.moving),
  35_000);
  state = await bridgeState(page, shelterRallyOracle);
  playerObservation(state, 'Eazy shelter Rally mechanism oracle');
  for (const id of PARTY) {
    expectMovementContinuity(
      state, id, 'whole-party shelter Rally',
      shelterRallyContinuityBaselines[id], {
        category: 'navigation', kind: 'continuous_route', type: 'walk',
      },
    );
  }
  expect(partyVisiblyNearCue(shelterRallyAfterObservation, /SHELTER/i),
    'all three visible party bodies finish near the SHELTER marker').toBe(true);
  const shelterRallyEvents = productionMessagesAfter(productionEvents, shelterRallyEventStart);
  const shelterRallyReceipt = trace.keyboardPointerReceipt({
    verb: 'rally',
    consoleEvents: shelterRallyEvents,
    inputEvents: playerInputs.after(shelterRallyInputStart),
    intendedMembers: shelterRallyMembers,
    targetToken: shelterRallyChoice.token,
    input: 'one held RMB canvas gesture on the exact visible REST PARTY shelter surface',
  });
  expect(shelterRallyReceipt.production_event_count,
    'the shelter gesture emits exactly one production rally_members event').toBe(1);
  expect(shelterRallyReceipt.atomic_group,
    'the shelter Rally remains one atomic group verb').toBe(true);
  expect(Object.values(shelterRallyReceipt.member_results),
    'the shelter Rally event accepts every visible party member')
    .toEqual(['accepted', 'accepted', 'accepted']);
  const semanticShelterRallies = productionEventRecords(
    shelterRallyEvents, 'rally_members',
  );
  expect(semanticShelterRallies,
    'the held shelter gesture emits one inspectable semantic Rally payload').toHaveLength(1);
  const shelterFormation = semanticShelterRallies[0]?.payload?.formation_region ?? {};
  const shelterSlots = semanticShelterRallies[0]?.payload?.formation_region_slots ?? [];
  const shelterCells = shelterFormation?.cells ?? [];
  const shelterCellKeys = new Set(shelterCells.map((cell) => JSON.stringify(cell)));
  expect(shelterFormation?.contract_id,
    'the visible shelter owns the generic typed formation contract')
    .toBe('rally_formation_region/v1');
  expect(shelterSlots,
    'the atomic event stores one exact semantic-region slot per portrait').toHaveLength(PARTY.length);
  expect(new Set(shelterSlots.map((cell) => JSON.stringify(cell))).size,
    'the three whole-party parking slots are distinct').toBe(PARTY.length);
  expect(shelterSlots.every((cell) => shelterCellKeys.has(JSON.stringify(cell))),
    'every committed endpoint belongs to the surface-published shelter region').toBe(true);
  expect(PARTY.every((id) => state.characters?.[id]?.level === shelterFormation.authored_level),
    'every live party body settles on the shelter contract\'s authored graph level').toBe(true);
  const shelterRallyRecord = trace.record({
    observationBefore: shelterApproachObservation,
    observationAfter: shelterRallyAfterObservation,
    observationSamples: normalizeObservationSamples([
      ...heldShelterRallyObservations, ...shelterRallyJourney.observationSamples,
    ]),
    rationale: {
      text: 'Eazy holds Rally on the visible REST PARTY shelter surface, whose shown parking region gathers the complete roster before the interaction.',
      policy_nodes: ['eazy_speezy_rally_full_party_to_visible_shelter'],
    },
    decision: {
      verb: 'rally',
      intended_subjects: shelterRallyMembers,
      target: {
        kind: 'visible_affordance', token: shelterRallyChoice.token,
        screen: shelterRallyChoice.screen,
      },
    },
    inputReceipt: shelterRallyReceipt,
    learningCandidate: shelterRallyCandidate(shelterVisibleInteraction.verb),
  });
  expectLearningEligible(shelterRallyRecord, 'Eazy full-party shelter Rally');

  // Do not churn selection when Rally preserved the already-complete visible
  // roster. If it did not, rebuild it primary-first and then add each remaining
  // visible portrait exactly once.
  const shelterSelectionObservation = await waitForPlayerObservation(
    page,
    'Eazy receives a fresh pre-selection observation after the shelter Rally',
    (observation) => observation.capture_serial > shelterRallyAfterObservation.capture_serial,
    15_000,
  );
  const shelterSelectionInputStart = playerInputs.mark();
  const shelterSelectionInput = await selectFullVisiblePartyFromPortraits(
    playerInputs, shelterSelectionObservation,
  );
  let shelterSelectedObservation = shelterSelectionObservation;
  if (shelterSelectionInput.acted) {
    eazyActiveSubject = shelterSelectionInput.activeSubject;
    const shelterSelection = await collectPlayerObservationsUntil(
      page,
      'the portrait HUD visibly shows the full party selected for REST PARTY',
      (observation) => (observation?.state?.hud?.portraits ?? [])
        .filter((portrait) => portrait?.visible !== false)
        .every((portrait) => portrait.selected === true),
      8_000,
      shelterSelectionObservation.capture_serial,
    );
    shelterSelectedObservation = shelterSelection.observationAfter;
    const shelterSelectionMembers = visibleSubjectIds(shelterSelectionObservation);
    const shelterSelectionRecord = trace.record({
      observationBefore: shelterSelectionObservation,
      observationAfter: shelterSelectedObservation,
      observationSamples: shelterSelection.observationSamples,
      rationale: {
        text: 'Eazy rebuilds the full visible portrait roster after Rally changes selection.',
        policy_nodes: ['eazy_speezy_select_full_party_for_shelter'],
      },
      decision: {
        verb: 'select_party',
        intended_subjects: shelterSelectionMembers,
        target: { kind: 'hud_portraits', token: 'hud_portraits' },
      },
      inputReceipt: trace.observedInputReceipt({
        verb: 'select_party', input: shelterSelectionInput.input,
        boundary: 'keyboard_pointer',
        inputEvents: playerInputs.after(shelterSelectionInputStart),
        intendedMembers: shelterSelectionMembers,
        memberResults: selectedVisibleMemberResults(
          shelterSelectionObservation, shelterSelectedObservation,
        ),
      }),
    });
    expectLearningEligible(shelterSelectionRecord, 'Eazy visible shelter-party selection');
  }
  expect((shelterSelectedObservation?.state?.hud?.portraits ?? [])
    .filter((portrait) => portrait?.visible !== false)
    .every((portrait) => portrait.selected === true),
  'Eazy attempts REST PARTY only with the complete visible roster selected').toBe(true);
  expect(visibleSubjectIds(shelterSelectedObservation),
    'Eazy remembers an active subject selected through visible portrait input')
    .toContain(eazyActiveSubject);

  const shelterInteractionObservation = await waitForPlayerObservation(
    page,
    'Eazy receives a fresh pre-shelter observation after roster preparation',
    (observation) => observation.capture_serial > shelterSelectedObservation.capture_serial
      && Boolean(chooseVisibleInteraction(observation, /\bREST PARTY\b/i)),
    15_000,
  );
  const shelterChoice = chooseVisibleInteraction(shelterInteractionObservation, /\bREST PARTY\b/i);
  expect(shelterChoice,
    'Eazy can identify the visible shelter action without a private click-target name').toBeTruthy();
  const shelterCapability = authorizePersonaAction(
    playerInputs, shelterInteractionObservation, shelterChoice, {
      gesture: 'pointer_click', button: 'right', targetToken: shelterChoice.token,
    }, 'Eazy shelter interaction',
  );
  const shelterOracle = postChoiceAssertionOracle(shelterCapability);
  const shelterResultBaseline = highestVisibleInteractionSerial(
    shelterInteractionObservation, shelterChoice.token,
  );
  const shelterEventStart = productionEvents.mark();
  const shelterInputStart = playerInputs.mark();
  await clickObservedAffordance(
    page, playerInputs, shelterChoice, shelterCapability,
  );
  const shelterDispatch = await collectPlayerObservationsUntil(
    page,
    'REST PARTY presents exact-target success and the secured shelter consequence',
    (observation) => Boolean(visibleCue(observation, /SECURED THE SHELTER|FULL PARTY SETTLED/i))
      && newestVisibleInteractionResult(
        observation, shelterChoice.token, shelterResultBaseline,
      )?.result === 'success',
    25_000,
    shelterInteractionObservation.capture_serial,
  );
  const shelterAfterObservation = shelterDispatch.observationAfter;
  await waitForState(page, shelterOracle,
    'the physical exit shelter completes the fragment', (next) =>
    next.chunk?.complete === true && next.chunk?.phase === 'complete',
    25_000,
  );

  await page.waitForTimeout(500);
  const shelterEvents = productionMessagesAfter(productionEvents, shelterEventStart);
  const shelterTrigger = shelterEvents.find((entry) =>
    entry.includes('trigger_interactable') && entry.includes('data_fragment_BasinExitShelter'));
  expect(shelterTrigger, 'the shelter click emits its physical interaction trigger').toBeTruthy();
  expect(
    shelterEvents.filter((entry) => entry.includes('party_move_to_cell')),
    'the shelter interaction click does not also issue a ground move',
  ).toEqual([]);
  console.log(`[BASIN-E2E] Shelter dispatch: ${shelterTrigger}; no party_move_to_cell`);
  state = await bridgeState(page, shelterOracle);
  expect(state.move_refusals, 'no canvas movement command is refused').toEqual([]);
  consequenceFeedback(state, 'completed safe Basin journey');
  expect(state.chunk?.basin_states?.[0]?.swept_party,
    'the completed route is the browser no-sweep control').toBe(0);
  expect(
    forcedMovementRecords(state).filter((record) => PARTY.includes(record.subject_id)),
    'the safe route never presents a party member as forcibly moved',
  ).toEqual([]);
  for (const id of PARTY) {
    expect(!state.characters[id].downed, `${id} finishes conscious`).toBe(true);
    expectPresentationParity(state, id, 'completed Basin shelter', 2.7);
    expectAnnotatedLevelTransitions(state, id, 'completed Basin shelter', true);
  }
  expect(runtimeFailures, 'the exported page emits no JavaScript/Godot console errors').toEqual([]);
  const shelterReceipt = trace.keyboardPointerReceipt({
    verb: 'interact',
    consoleEvents: shelterEvents,
    inputEvents: playerInputs.after(shelterInputStart),
    targetToken: shelterChoice.token,
    input: 'one RMB canvas click at the chosen visible shelter affordance',
  });
  expect(shelterReceipt.status, 'the visible shelter click emitted trigger_interactable')
    .toBe('accepted');
  const shelterRecord = trace.record({
    observationBefore: shelterInteractionObservation,
    observationAfter: shelterAfterObservation,
    observationSamples: shelterDispatch.observationSamples,
    rationale: {
      text: 'The fastest legal route ends by physically clicking the visible shelter once settled.',
      policy_nodes: ['eazy_speezy_use_visible_exit_shelter'],
    },
    decision: {
      verb: 'interact',
      intended_subjects: [eazyActiveSubject],
      target: {
        kind: 'visible_affordance',
        token: shelterChoice.token,
        screen: shelterChoice.screen,
      },
    },
    inputReceipt: shelterReceipt,
    learningCandidate: interactionCandidate('eazy_speezy', shelterChoice.verb),
  });
  expectLearningEligible(shelterRecord, 'Eazy visible shelter completion');
  const eazyPortraitTokenSet = portraitTokens(shelterAfterObservation);
  const tracedPartySweeps = tracedFeedbackCues(trace, (cue) =>
    cue?.kind === 'consequence'
      && /SWEPT/i.test(String(cue?.text ?? ''))
      && eazyPortraitTokenSet.has(String(cue?.source_token ?? '')));
  expect(tracedPartySweeps,
    'Eazy never receives a SWEPT consequence linked to any current party portrait').toEqual([]);
  const visibleDwellerSweeps = tracedFeedbackCues(trace, (cue) =>
    cue?.kind === 'consequence'
      && cue?.visible === true
      && /SWEPT/i.test(String(cue?.text ?? ''))
      && !eazyPortraitTokenSet.has(String(cue?.source_token ?? '')));
  expect(visibleDwellerSweeps.length,
    'the visible dweller sweep demonstration remains present but is not attributed to the party')
    .toBeGreaterThan(0);
  trace.finish({ trace_complete: true, swept_party: 0 });
  expect(trace.records.at(-1).summary.persona_goal_reached,
    'Eazy goal is derived from same-action exact-target shelter success').toBe(true);
  expect(trace.records.at(-1).summary.trace_complete,
    'Eazy trace is complete only when every decision is independently eligible').toBe(true);
  await trace.save(testInfo);
});

async function discoverGeneratedHideThroughVisibleControls(page, inputLedger) {
  let observation = await currentPlayerObservation(page, 'generated seed-5 first read');
  let hideChoice = chooseVisibleInteraction(observation, /\bHIDE\b/i);
  const visiblePanDescription = /(?=.*\bW\b)(?=.*\bA\b)(?=.*\bS\b)(?=.*\bD\b)(?=.*\bPAN\b)/i;
  const visibleCenterDescription = /(?=.*\bHOME\b)(?=.*\bCENTER\b)/i;
  const cameraAttempts = [
    { key: 'Home', pattern: visibleCenterDescription, glyph: /\bHOME\b/i, holdMs: 0 },
    { key: 'w', pattern: visiblePanDescription, glyph: /\bW\b/i, holdMs: 650 },
    { key: 'a', pattern: visiblePanDescription, glyph: /\bA\b/i, holdMs: 650 },
    { key: 's', pattern: visiblePanDescription, glyph: /\bS\b/i, holdMs: 650 },
    { key: 'd', pattern: visiblePanDescription, glyph: /\bD\b/i, holdMs: 650 },
  ];
  for (const attempt of cameraAttempts) {
    if (hideChoice) break;
    const visibleControl = chooseVisibleCue(observation, attempt.pattern);
    const visibleControlText = String(visibleControl?.text ?? '');
    if (!visibleControl || visibleControl.kind !== 'instruction'
        || !attempt.pattern.test(visibleControlText)
        || !attempt.glyph.test(visibleControlText)) continue;
    const visibleControlToken = `visible_camera_${attempt.key.toLowerCase()}_control`;
    const capability = authorizePersonaAction(
      inputLedger, observation, visibleControl, {
        gesture: attempt.holdMs > 0 ? 'key_hold' : 'key_press',
        key: attempt.key,
        targetToken: visibleControlToken,
      }, `generated seed-5 camera recovery ${attempt.key}`,
    );
    if (attempt.holdMs > 0) {
      await observedKeyDown(
        inputLedger, attempt.key, visibleControl, visibleControlToken, capability,
      );
      try { await page.waitForTimeout(attempt.holdMs); } finally {
        await observedKeyUp(
          inputLedger, attempt.key, visibleControl, visibleControlToken, capability,
        );
      }
    } else {
      await inputLedger.press(attempt.key, visibleControlToken, capability);
    }
    const priorCaptureSerial = observation.capture_serial;
    observation = await waitForPlayerObservation(
      page,
      `generated seed-5 camera recovery ${attempt.key} yields a fresh player view`,
      (candidate) => candidate.capture_serial > priorCaptureSerial,
      10_000,
    );
    hideChoice = chooseVisibleInteraction(observation, /\bHIDE\b/i);
  }
  return { observation, hideChoice };
}

test('Generated seed-5 Capbage HIDE roundtrip uses strict Web player observations', async ({ page }) => {
  const runtimeFailures = [];
  const productionEvents = captureProductionEvents(page);
  const playerInputs = capturePlayerInput(page);
  page.on('pageerror', (error) => runtimeFailures.push(`pageerror: ${error.message}`));
  page.on('console', (message) => {
    if (message.type() === 'error' || message.type() === 'assert') {
      runtimeFailures.push(`console.${message.type()}: ${message.text()}`);
    }
  });

  await assertFixtureRequiresInitialWebE2EQuery(
    page, 'generated_player_surface_seed_5',
  );
  await page.goto('/index.html?e2e=1&fragment=generated_player_surface_seed_5');
  await waitForBootState(page, 'seed-5 contract reaches the real Fragments button', (state) =>
    state.stage === 'main_menu' && state.ready && state.click_targets?.fragments?.visible,
  );
  await clickBridgeTarget(page, 'fragments', 'left');
  await waitForBootState(page, 'exact generated seed-5 contract finishes booting', (state) =>
    state.stage === 'fragment'
      && state.ready
      && state.fragment === 'generated_player_surface_seed_5',
  90_000);

  const discovery = await discoverGeneratedHideThroughVisibleControls(page, playerInputs);
  const hideObservation = discovery.observation;
  const hideChoice = discovery.hideChoice;
  expect(hideChoice,
    'a human-visible HIDE affordance is discoverable without a named target or transform')
    .toBeTruthy();
  const baselinePresence = exactPartyPresenceBindings(hideObservation);
  expect(baselinePresence.valid,
    'the generated Web first read binds every visible portrait exactly once').toBe(true);
  expect(baselinePresence.bodyTokens,
    'all three members begin as exact rendered bodies').toHaveLength(PARTY.length);
  expect(baselinePresence.concealedPortraitTokens,
    'no member begins silently HIDDEN').toEqual([]);
  const hideResultBaseline = highestVisibleInteractionSerial(
    hideObservation, hideChoice.token,
  );

  const hideCapability = authorizePersonaAction(
    playerInputs, hideObservation, hideChoice, {
      gesture: 'pointer_click', button: 'right', targetToken: hideChoice.token,
    }, 'generated seed-5 visible HIDE interaction',
  );
  const hideOracle = postChoiceAssertionOracle(hideCapability);
  const hideEventStart = productionEvents.mark();
  await clickObservedAffordance(page, playerInputs, hideChoice, hideCapability);
  let firstSuccessObservation = null;
  let firstHiddenObservation = null;
  const hideJourney = await collectPlayerObservationsUntil(
    page,
    'seed-5 routed HIDE presents both exact-source success and exact current HIDDEN',
    (observation) => {
      const result = newestVisibleInteractionResult(
        observation, hideChoice.token, hideResultBaseline,
      );
      const presence = exactPartyPresenceBindings(observation);
      const exactHiddenNow = presence.valid
        && presence.bodyTokens.length === PARTY.length - 1
        && presence.concealedPortraitTokens.length === 1;
      if (result?.result === 'success' && firstSuccessObservation === null) {
        firstSuccessObservation = structuredClone(observation);
      }
      if (exactHiddenNow && firstHiddenObservation === null) {
        firstHiddenObservation = structuredClone(observation);
      }
      return firstSuccessObservation !== null && firstHiddenObservation !== null
        && exactHiddenNow;
    },
    45_000,
    hideObservation.capture_serial,
    75,
  );
  const hiddenObservation = hideJourney.observationAfter;
  const currentHiddenPresence = exactPartyPresenceBindings(hiddenObservation);
  expect(currentHiddenPresence.valid
      && currentHiddenPresence.bodyTokens.length === PARTY.length - 1
      && currentHiddenPresence.concealedPortraitTokens.length === 1,
  'Rally begins only from a fresh observation where exact HIDDEN remains current').toBe(true);
  expect(firstSuccessObservation, 'the first exact source success was retained independently')
    .toBeTruthy();
  expect(firstHiddenObservation, 'the first exact positional HIDDEN was retained independently')
    .toBeTruthy();
  expect(firstSuccessObservation.capture_serial,
    'success is newer than the player decision').toBeGreaterThan(hideObservation.capture_serial);
  expect(firstHiddenObservation.capture_serial,
    'HIDDEN is newer than the player decision').toBeGreaterThan(hideObservation.capture_serial);
  expect(Math.abs(firstSuccessObservation.capture_serial - firstHiddenObservation.capture_serial),
    'success and HIDDEN belong to one bounded 0.25-second concealment action').toBeLessThanOrEqual(8);

  const postHideState = await bridgeState(page, hideOracle);
  expect(postHideState.preview_chunk,
    'the e2e-only seed entry uses the production generated-stretch chunk')
    .toBe('generated_stretch');
  expect(postHideState.chunk?.contract_id).toBe('stretch_generation_v1');
  expect(postHideState.chunk?.spec_id).toBe('generated_player_surface_seed_5');
  expect(postHideState.chunk?.complexity_tier).toBe('standard');
  expect(postHideState.chunk?.node_count).toBe(7);
  expect(postHideState.chunk?.resolved_budget?.node_count).toBe(7);
  expect(postHideState.chunk?.generation_fallback?.active ?? false,
    'the exact seed fixture cannot silently substitute fallback content').toBe(false);
  expect(postHideState.content_fingerprint_schema).toBe('generated_spec_semantic_v1');
  expect(postHideState.content_fingerprint).toMatch(/^[a-f0-9]{64}$/);
  const hideTriggers = productionEventRecords(
    productionMessagesAfter(productionEvents, hideEventStart), 'trigger_interactable',
  );
  expect(hideTriggers,
    'the physical HIDE click produces exactly one production interaction event').toHaveLength(1);

  const rallyChoice = chooseFarthestVisibleMove(hiddenObservation, hideChoice.screen);
  expect(rallyChoice,
    'the HIDDEN player view still exposes a safe visible destination away from the leaf')
    .toBeTruthy();
  const rallyMembers = visibleSubjectIds(hiddenObservation);
  expect(sameMembers(rallyMembers, PARTY),
    'one Rally intent includes the exact full visible portrait roster').toBe(true);
  const rallyRosterTokens = visibleRosterTokens(hiddenObservation);
  expect(rallyRosterTokens).toHaveLength(PARTY.length);
  const rallyCapability = authorizePersonaAction(
    playerInputs, hiddenObservation, rallyChoice, {
      gesture: 'pointer_hold', button: 'right', targetToken: rallyChoice.token,
    }, 'generated seed-5 whole-party Rally',
  );
  const rallyOracle = postChoiceAssertionOracle(rallyCapability);
  const rallySampleBaselines = await snapshotMovementCountsBeforeLaunch(
    page, rallyOracle, PARTY, 'generated seed-5 Rally',
  );
  const rallyContinuityBaselines = await snapshotMovementContinuityBeforeLaunch(
    page, rallyOracle, PARTY, 'generated seed-5 Rally',
  );
  const movementPresentationBaseline = highestVisibleMovementSerial(hiddenObservation);
  const rallyEventStart = productionEvents.mark();
  const heldRallyObservations = await holdBridgeTarget(
    page, playerInputs, rallyChoice, rallyCapability,
  );
  const rallyJourney = await collectPlayerObservationsUntil(
    page,
    'the one held Rally restores three exact rendered bodies at a settled destination',
    (observation, samples) => {
      const presence = exactPartyPresenceBindings(observation);
      return presence.valid
        && presence.bodyTokens.length === PARTY.length
        && presence.concealedPortraitTokens.length === 0
        && visiblePartyIsStable(samples, presence.bodyTokens);
    },
    45_000,
    hiddenObservation.capture_serial,
  );
  const restoredObservation = rallyJourney.observationAfter;
  const restoredPresence = exactPartyPresenceBindings(restoredObservation);
  expect(restoredPresence.valid).toBe(true);
  expect(restoredPresence.bodyTokens).toHaveLength(PARTY.length);
  expect(restoredPresence.concealedPortraitTokens).toEqual([]);
  expect(hasCompleteVisibleMovementLineage(
    [...heldRallyObservations, ...rallyJourney.observationSamples, restoredObservation],
    rallyChoice.token, rallyRosterTokens, movementPresentationBaseline,
  ), 'the exact target and all three portraits share accepted-progress-arrival lineage').toBe(true);
  await waitForMovementSampleGrowth(
    page, rallyOracle, PARTY, rallySampleBaselines, 'generated seed-5 whole-party Rally', 35_000,
  );
  await waitForState(page, rallyOracle, 'all seed-5 Rally members settle', (state) =>
    PARTY.every((id) => !state.characters?.[id]?.moving && !state.characters?.[id]?.committed),
  35_000);
  const restoredState = await bridgeState(page, rallyOracle);
  for (const id of PARTY) {
    expectMovementPresentationParity(
      restoredState, id, 'generated seed-5 Rally', rallySampleBaselines[id],
    );
    expectMovementContinuity(
      restoredState, id, 'generated seed-5 Rally', rallyContinuityBaselines[id],
      { category: 'navigation', kind: 'continuous_route', type: 'walk' },
    );
  }
  const rallyEvents = productionEventRecords(
    productionMessagesAfter(productionEvents, rallyEventStart), 'rally_members',
  );
  expect(rallyEvents,
    'one held RMB gesture emits exactly one production Rally event').toHaveLength(1);
  expect((rallyEvents[0]?.payload?.members ?? []).map(String).sort(),
    'the one Rally event names exactly Aster, Peris, and Endo')
    .toEqual([...PARTY].sort());
  expect(runtimeFailures, 'the generated exported-Web roundtrip emits no runtime errors').toEqual([]);
});

test('Static Capbage-green source cannot self-attest a suppressed Web result pulse', async ({ page }) => {
  const runtimeFailures = [];
  const productionEvents = captureProductionEvents(page);
  const playerInputs = capturePlayerInput(page);
  page.on('pageerror', (error) => runtimeFailures.push(`pageerror: ${error.message}`));
  page.on('console', (message) => {
    if (message.type() === 'error' || message.type() === 'assert') {
      runtimeFailures.push(`console.${message.type()}: ${message.text()}`);
    }
  });

  await assertFixtureRequiresInitialWebE2EQuery(
    page, 'result_pulse_static_green_contract',
  );
  await page.goto('/index.html?e2e=1&fragment=result_pulse_static_green_contract');
  await waitForBootState(page, 'pulse contract reaches the real Fragments button', (state) =>
    state.stage === 'main_menu' && state.ready && state.click_targets?.fragments?.visible,
  );
  await clickBridgeTarget(page, 'fragments', 'left');
  await waitForBootState(page, 'adversarial pulse contract finishes booting', (state) =>
    state.stage === 'fragment'
      && state.ready
      && state.fragment === 'result_pulse_static_green_contract',
  90_000);

  const firstObservation = await waitForPlayerObservation(
    page,
    'the static-green fixture exposes its ordinary visible interaction',
    (observation) => chooseVisibleInteraction(observation, /TEST RESULT PULSE/i) !== null,
  );
  const firstChoice = chooseVisibleInteraction(firstObservation, /TEST RESULT PULSE/i);
  expect(firstChoice,
    'the first action is chosen only from a visible TEST RESULT PULSE affordance').toBeTruthy();
  const resultBaseline = highestVisibleInteractionSerial(
    firstObservation, firstChoice.token,
  );
  const firstCapability = authorizePersonaAction(
    playerInputs, firstObservation, firstChoice, {
      gesture: 'pointer_click', button: 'right', targetToken: firstChoice.token,
    }, 'first adversarial result-pulse interaction',
  );
  const firstOracle = postChoiceAssertionOracle(firstCapability);
  const firstEventStart = productionEvents.mark();
  await clickObservedAffordance(page, playerInputs, firstChoice, firstCapability);
  const firstJourney = await collectPlayerObservationsUntil(
    page,
    'the first physical click produces a neutral visible acknowledgement',
    (observation) => visibleCue(
      observation, /CONTROL RECEIVED.*CLICK AGAIN FOR VISIBLE PULSE/is,
    ) !== undefined,
    45_000,
    firstObservation.capture_serial,
    75,
  );

  // The private bridge is used only after the click has already been chosen and
  // dispatched. It verifies the adversarial setup; it never supplies a target,
  // coordinate, command, or timing decision to the browser player.
  const suppressedState = await bridgeState(page, firstOracle);
  expect(suppressedState.preview_chunk).toBe('result_pulse_web_contract');
  expect(suppressedState.chunk?.contract_id).toBe('web_interaction_result_adversarial_v1');
  expect(suppressedState.chunk?.interaction_count).toBe(1);
  expect(suppressedState.chunk?.first_pulse_suppression_applied).toBe(true);
  expect(suppressedState.chunk?.acknowledgement_visible).toBe(true);
  expect(suppressedState.chunk?.acknowledgement_color)
    .toEqual([0.74, 0.74, 0.74, 1.0]);
  expect(suppressedState.chunk?.first_result_serial).toBeGreaterThan(resultBaseline);
  expect(suppressedState.chunk?.current_presentation).toMatchObject({
    presentation_serial: suppressedState.chunk.first_result_serial,
    result: 'success',
    visible: true,
  });
  expect(suppressedState.chunk?.pulse_diagnostics).toMatchObject({
    presentation_serial: suppressedState.chunk.first_result_serial,
    result: 'success',
    visible: true,
    successful_interaction_count: 1,
  });
  expect(suppressedState.chunk?.pulse_diagnostics?.result_render_node_count,
    'the logical receipt still names the object meshes as its geometry').toBeGreaterThan(0);
  expect(suppressedState.chunk?.pulse_diagnostics?.result_screen_candidate_count,
    'the production observer has on-screen silhouette candidates to evaluate').toBeGreaterThan(0);
  expect(suppressedState.chunk?.pulse_diagnostics?.outline_active,
    'the logical outline state claims the result tint').toBe(true);
  expect(suppressedState.chunk?.pulse_diagnostics?.mask_registered,
    'the adversarial first mint withdrew the silhouette from the mask, so no pixels exist').toBe(false);
  expect(suppressedState.chunk?.static_capbage_box?.size).toEqual([1.5, 1.0, 1.5]);
  expect(suppressedState.chunk?.static_capbage_box?.albedo).toEqual([0.16, 0.34, 0.18]);
  expect(suppressedState.chunk?.static_capbage_box?.emission).toEqual([0.3, 0.7, 0.35]);
  expect(suppressedState.chunk?.static_capbage_box?.emission_energy).toBeCloseTo(0.25, 5);

  // Sample past the production six-second retirement bound. A permanent
  // Capbage-green box must not be able to impersonate the hidden transient at
  // any point in that presentation's complete lifetime.
  const suppressedLifetime = await sampleDistinctPlayerObservations(page, 6_500, 100);
  const firstObservations = normalizeObservationSamples([
    ...firstJourney.observationSamples,
    firstJourney.observationAfter,
    ...suppressedLifetime,
  ]);
  expect(firstObservations.length,
    'the negative assertion spans many distinct rendered captures').toBeGreaterThanOrEqual(10);
  expect(firstObservations.some((observation) => visibleCue(
    observation, /CONTROL RECEIVED.*CLICK AGAIN FOR VISIBLE PULSE/is,
  )), 'a neutral visible acknowledgement replaces the suppressed success cue').toBe(true);
  const suppressedSerial = suppressedState.chunk.first_result_serial;
  const firstVisibleResults = firstObservations.flatMap((observation) =>
    (observation?.state?.cues ?? []).filter((cue) =>
      cue?.visible === true
        && cue?.kind === 'interaction_result'
        && cue?.source_token === firstChoice.token
        && Number.isInteger(cue?.presentation_serial)
        && cue.presentation_serial > resultBaseline));
  expect(firstVisibleResults,
    'a logical receipt plus static green pixels cannot self-attest a rendered result').toEqual([]);
  const retiredSuppressedState = await bridgeState(page, firstOracle);
  expect(retiredSuppressedState.chunk?.first_result_serial).toBe(suppressedSerial);
  expect(retiredSuppressedState.chunk?.current_presentation?.visible,
    'the negative sampling reaches the suppressed presentation retirement').toBe(false);
  expect(retiredSuppressedState.chunk?.pulse_diagnostics?.result_render_node_count).toBe(0);
  const firstTriggers = productionEventRecords(
    productionMessagesAfter(productionEvents, firstEventStart), 'trigger_interactable',
  );
  expect(firstTriggers,
    'the first physical pointer action triggers exactly one production interaction').toHaveLength(1);

  const secondObservation = await currentPlayerObservation(
    page, 'fresh player view before the second physical click',
  );
  const secondChoice = chooseVisibleInteraction(secondObservation, /TEST RESULT PULSE/i);
  expect(secondChoice,
    'the second action is independently chosen from the fresh visible affordance').toBeTruthy();
  expect(secondChoice.token,
    'both clicks retain the exact rendered interaction source').toBe(firstChoice.token);
  const secondCapability = authorizePersonaAction(
    playerInputs, secondObservation, secondChoice, {
      gesture: 'pointer_click', button: 'right', targetToken: secondChoice.token,
    }, 'second production result-pulse interaction',
  );
  const secondOracle = postChoiceAssertionOracle(secondCapability);
  const secondEventStart = productionEvents.mark();
  await clickObservedAffordance(page, playerInputs, secondChoice, secondCapability);
  let visibleRestoredResult = null;
  const secondJourney = await collectPlayerObservationsUntil(
    page,
    'the second physical click renders one newer exact-source success pulse',
    (observation) => {
      const candidate = newestVisibleInteractionResult(
        observation, secondChoice.token, suppressedSerial,
      );
      if (candidate?.result === 'success') visibleRestoredResult = structuredClone(candidate);
      return visibleRestoredResult !== null;
    },
    45_000,
    secondObservation.capture_serial,
    75,
  );
  expect(visibleRestoredResult).toBeTruthy();
  expect(visibleRestoredResult.presentation_serial).toBeGreaterThan(suppressedSerial);
  const allObservedResults = normalizeObservationSamples([
    ...firstObservations,
    ...secondJourney.observationSamples,
    secondJourney.observationAfter,
  ]).flatMap((observation) => (observation?.state?.cues ?? []).filter((cue) =>
    cue?.visible === true
      && cue?.kind === 'interaction_result'
      && cue?.source_token === secondChoice.token
      && Number.isInteger(cue?.presentation_serial)
      && cue.presentation_serial > resultBaseline));
  const observedResultSerials = [...new Set(
    allObservedResults.map((cue) => cue.presentation_serial),
  )].sort((left, right) => left - right);
  expect(observedResultSerials,
    'only the second, genuinely rendered presentation is player-observable')
    .toEqual([visibleRestoredResult.presentation_serial]);
  expect(observedResultSerials).not.toContain(suppressedSerial);

  const restoredState = await bridgeState(page, secondOracle);
  expect(restoredState.chunk?.interaction_count).toBe(2);
  expect(restoredState.chunk?.second_pulse_production_restored).toBe(true);
  expect(restoredState.chunk?.second_serial_is_newer).toBe(true);
  expect(restoredState.chunk?.second_result_serial)
    .toBe(visibleRestoredResult.presentation_serial);
  expect(restoredState.chunk?.current_presentation).toMatchObject({
    presentation_serial: visibleRestoredResult.presentation_serial,
    result: 'success',
    visible: true,
  });
  expect(restoredState.chunk?.pulse_diagnostics?.result_render_node_count).toBeGreaterThan(0);
  expect(restoredState.chunk?.pulse_diagnostics?.result_screen_candidate_count).toBeGreaterThan(0);
  expect(restoredState.chunk?.pulse_diagnostics).toMatchObject({
    outline_active: true,
    mask_registered: true,
    outline_color_is_success_tint: true,
    seam_presented_result: true,
  });
  const secondTriggers = productionEventRecords(
    productionMessagesAfter(productionEvents, secondEventStart), 'trigger_interactable',
  );
  expect(secondTriggers,
    'the second physical pointer action triggers exactly one production interaction').toHaveLength(1);
  expect(runtimeFailures, 'the adversarial exported-Web contract emits no runtime errors').toEqual([]);
});
