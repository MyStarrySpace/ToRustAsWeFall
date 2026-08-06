import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { appendFile, mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  canonicalHash,
  canonicalJson,
  classifyEvidence,
  deriveBasinPersonaGoal,
  inputSequenceProgressionReasons,
  observationProgressionReasons,
  TRACE_SCHEMA,
  validateDecisionRecord,
  validateRunMetadata,
} from './persona-decision-trace.mjs';

export const VALIDATION_SCHEMA = 'persona_strict_validation_v1';
export const INVOCATION_MANIFEST_SCHEMA = 'persona_strict_invocation_manifest_v1';
export const VALIDATION_CONTRACT_VERSION = 3;
export const VALIDATION_VALIDATOR_ID = 'playwright_persona_probe';

const EXPECTED_TESTS = new Map([
  ['DeanTakahashi records a real missed-rise Basin playthrough', 'dean_takahashi'],
  ['EazySpeezy records a legal Basin clear through real Web input', 'eazy_speezy'],
]);
const REQUIRED_NON_PERSONA_TESTS = [
  'Web persona trace refusal and input-ledger contract vectors',
  'Generated seed-5 Capbage HIDE roundtrip uses strict Web player observations',
  'Static Capbage-green source cannot self-attest a suppressed Web result pulse',
];
const REQUIRED_REPEATS = [0, 1];
const DISTILLATION_TIMEOUT_MS = 180_000;
const EXPECTED_FRAGMENT_NODES = new Map([
  ['dean_takahashi_rally_unmarked_visible_floor', 'dean_takahashi'],
  ['eazy_speezy_arm_visible_mid_console', 'eazy_speezy'],
  ['eazy_speezy_rally_full_party_to_visible_shelter', 'eazy_speezy'],
  ['eazy_speezy_rally_marked_deck_access', 'eazy_speezy'],
  ['eazy_speezy_use_visible_exit_shelter', 'eazy_speezy'],
  ['wait_for_visible_announced_mid_crossing', 'eazy_speezy'],
]);
const EXPECTED_GLOBAL_NODES = new Map([
  ['eazy_speezy_select_full_visible_roster', 'eazy_speezy'],
  ['hide_instructions_when_they_occlude_the_board', 'eazy_speezy'],
]);

function runIdentity(run) {
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

function cohortIdentity(value) {
  return {
    execution_platform: String(value?.execution_platform ?? ''),
    fragment_id: String(value?.fragment_id ?? ''),
    persona: String(value?.persona ?? ''),
    repeat_index: Number(value?.repeat_index ?? -1),
  };
}

function cohortIdentityKey(value) {
  return canonicalJson(cohortIdentity(value));
}

function cohortMemberProofKey(value) {
  return `${cohortIdentityKey(value)}|${String(value?.run_id ?? '')}|${String(value?.trace_id ?? '')}`;
}

function sortedCohortIdentities(values) {
  return (values ?? []).filter((value) => value && typeof value === 'object')
    .map(cohortIdentity).sort((left, right) => cohortIdentityKey(left).localeCompare(cohortIdentityKey(right)));
}

function expectedValidationCohort(run) {
  if (run?.fragment_id !== 'basin_fill_proof' || !['native', 'web'].includes(run?.execution_platform)) {
    return [];
  }
  return sortedCohortIdentities(['dean_takahashi', 'eazy_speezy'].flatMap((persona) =>
    REQUIRED_REPEATS.map((repeat_index) => ({
      execution_platform: run.execution_platform,
      fragment_id: run.fragment_id,
      persona,
      repeat_index,
    }))));
}

function invocationMemberProof(document) {
  const run = document.run ?? {};
  const summary = document.summaryRecord?.summary ?? {};
  return {
    run_id: String(run.run_id ?? ''),
    trace_id: String(run.trace_id ?? ''),
    persona: String(run.persona ?? ''),
    fragment_id: String(run.fragment_id ?? ''),
    execution_platform: String(run.execution_platform ?? ''),
    repeat_index: Number(run.repeat_index ?? -1),
    content_fingerprint_schema: String(run.content_fingerprint_schema ?? ''),
    content_fingerprint: String(run.content_fingerprint ?? ''),
    gameplay_build_fingerprint_schema: String(run.gameplay_build_fingerprint_schema ?? ''),
    gameplay_build_fingerprint: String(run.gameplay_build_fingerprint ?? ''),
    summary_record_hash: String(document.summaryRecord?.record_hash ?? ''),
    decision_count: Number(document.decisionCount ?? 0),
    trace_complete: summary.trace_complete === true,
    persona_goal_reached: summary.persona_goal_reached === true,
  };
}

export function makeInvocationManifest(documents, invocationId, expectedMembers = []) {
  const failures = [];
  const members = [];
  let firstRun = {};
  for (const document of documents ?? []) {
    if (!document || typeof document !== 'object') {
      failures.push('cohort_document_not_an_object');
      continue;
    }
    if (Object.keys(firstRun).length === 0) firstRun = document.run ?? {};
    if ((document.issues?.length ?? 0) > 0) {
      failures.push(`cohort_document_invalid:${String(document.run?.trace_id ?? '')}`);
    }
    members.push(invocationMemberProof(document));
  }
  const expected = sortedCohortIdentities(
    expectedMembers.length > 0 ? expectedMembers : expectedValidationCohort(firstRun),
  );
  if (String(invocationId).trim() === '') failures.push('invocation_id_missing');
  const seen = new Set();
  const contentIdentities = new Set();
  const gameplayBuildIdentities = new Set();
  for (const member of members) {
    const key = cohortMemberProofKey(member);
    if (seen.has(key)) failures.push(`duplicate_cohort_member:${key}`);
    seen.add(key);
    if (!member.summary_record_hash) failures.push(`cohort_member_summary_hash_missing:${key}`);
    if (member.decision_count < 1) failures.push(`cohort_member_decisions_missing:${key}`);
    if (!member.trace_complete) failures.push(`cohort_member_trace_incomplete:${key}`);
    if (!member.persona_goal_reached) failures.push(`cohort_member_goal_unproven:${key}`);
    if (member.content_fingerprint_schema !== 'authored_fragment_resource_bytes_v1') {
      failures.push(`cohort_member_fingerprint_schema_invalid:${key}`);
    }
    if (!/^[a-f0-9]{64}$/.test(member.content_fingerprint)) {
      failures.push(`cohort_member_fingerprint_invalid:${key}`);
    }
    contentIdentities.add(
      `${member.content_fingerprint_schema}|${member.content_fingerprint}`,
    );
    if (member.gameplay_build_fingerprint_schema !== 'gameplay_build_resource_set_bytes_v1') {
      failures.push(`cohort_member_gameplay_build_fingerprint_schema_invalid:${key}`);
    }
    if (!/^[a-f0-9]{64}$/.test(member.gameplay_build_fingerprint)) {
      failures.push(`cohort_member_gameplay_build_fingerprint_invalid:${key}`);
    }
    gameplayBuildIdentities.add(
      `${member.gameplay_build_fingerprint_schema}|${member.gameplay_build_fingerprint}`,
    );
  }
  const actual = sortedCohortIdentities(members);
  if (canonicalJson(actual) !== canonicalJson(expected)) {
    failures.push('cohort_does_not_match_expected_persona_repeat_matrix');
  }
  if (contentIdentities.size !== 1) failures.push('cohort_content_identity_mismatch');
  if (gameplayBuildIdentities.size !== 1) {
    failures.push('cohort_gameplay_build_identity_mismatch');
  }
  const sortedMembers = [...members]
    .sort((left, right) => cohortMemberProofKey(left).localeCompare(cohortMemberProofKey(right)));
  const sortedFailures = [...failures].sort();
  return {
    schema: INVOCATION_MANIFEST_SCHEMA,
    invocation_id: invocationId,
    execution_platform: String(firstRun.execution_platform ?? ''),
    fragment_id: String(firstRun.fragment_id ?? ''),
    expected_members: expected,
    members: sortedMembers,
    cohort_size: sortedMembers.length,
    passed: sortedFailures.length === 0,
    failure_count: sortedFailures.length,
    failures: sortedFailures,
  };
}

export function deterministicInvocationId(documents, executionPlatform = 'web') {
  const platform = String(executionPlatform ?? '').trim().toLowerCase();
  const validatorId = platform === 'native'
    ? 'godot_windowed_persona_probe' : VALIDATION_VALIDATOR_ID;
  const cohort = (documents ?? []).filter((document) => document && typeof document === 'object')
    .map((document) => ({
      run: runIdentity(document.run ?? {}),
      summary_record_hash: String(document.summaryRecord?.record_hash ?? ''),
    }))
    .sort((left, right) => canonicalJson(left).localeCompare(canonicalJson(right)));
  return `${platform}_persona_probe:${canonicalHash({ validator_id: validatorId, cohort })}`;
}

function expectedInvocationKeys(tests) {
  return tests.map((entry) => `${entry.title}\u0000${entry.repeatEachIndex}`).sort();
}

export function isRequiredBasinInvocation(tests) {
  const expected = [
    ...EXPECTED_TESTS.keys(), ...REQUIRED_NON_PERSONA_TESTS,
  ].flatMap((title) =>
    REQUIRED_REPEATS.map((repeatEachIndex) => ({ title, repeatEachIndex })));
  // Release Web carries non-persona gameplay regressions in this spec. Require
  // their exact repeated matrix so a grep-filtered persona-only invocation can
  // never attest. They remain part of fullResult and can veto attestation, but
  // onTestEnd below excludes them from the exact 2x2 trace cohort identity.
  return canonicalJson(expectedInvocationKeys(tests))
    === canonicalJson(expectedInvocationKeys(expected));
}

export function parseTraceText(text) {
  return String(text).split(/\r?\n/).filter((line) => line.trim() !== '')
    .map((line) => JSON.parse(line));
}

function validateValidationReceipt(validation, run, decisionCount, summaryRecord) {
  const issues = [];
  for (const key of ['schema', 'contract_id', 'validator_id', 'execution_platform',
    'invocation_id', 'invocation_manifest_hash']) {
    if (typeof validation?.[key] !== 'string' || validation[key].trim() === '') {
      issues.push(`validation.${key} is required`);
    }
  }
  if (!Number.isInteger(validation?.contract_version)) {
    issues.push('validation.contract_version must be an integer');
  } else if (validation.contract_version !== VALIDATION_CONTRACT_VERSION) {
    issues.push('validation.contract_version is not current');
  }
  const expectedValidator = run?.execution_platform === 'native'
    ? 'godot_windowed_persona_probe' : VALIDATION_VALIDATOR_ID;
  if (validation?.validator_id !== expectedValidator) {
    issues.push('validation.validator_id is not current for the run platform');
  }
  const expectedContract = `${String(run?.execution_platform ?? '')}_${String(
    run?.fragment_id ?? '',
  )}_${String(run?.persona ?? '')}_v${VALIDATION_CONTRACT_VERSION}`;
  if (validation?.contract_id !== expectedContract) {
    issues.push('validation.contract_id is not current for the run');
  }
  if (typeof validation?.passed !== 'boolean') issues.push('validation.passed must be explicit');
  for (const key of ['check_count', 'failure_count', 'checked_decision_count', 'cohort_size']) {
    if (!Number.isInteger(validation?.[key]) || validation[key] < 0) {
      issues.push(`validation.${key} must be a non-negative integer`);
    }
  }
  if (typeof validation?.passed === 'boolean') {
    if (validation.passed) {
      if (validation.failure_count !== 0) issues.push('passed validation must have zero failures');
      if (validation.check_count < 1) issues.push('passed validation must report at least one check');
    } else if (validation.failure_count < 1) {
      issues.push('failed validation must report at least one failure');
    }
  }
  if (validation?.execution_platform !== run?.execution_platform) {
    issues.push('validation.execution_platform does not match the run');
  }
  if (validation?.checked_decision_count !== decisionCount) {
    issues.push('validation.checked_decision_count does not match the decisions');
  }
  const manifest = validation?.invocation_manifest;
  if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)
      || Object.keys(manifest).length === 0) {
    issues.push('validation.invocation_manifest is required');
    return issues.sort();
  }
  if (manifest.schema !== INVOCATION_MANIFEST_SCHEMA) {
    issues.push('validation invocation manifest schema is not current');
  }
  if (manifest.invocation_id !== validation.invocation_id) {
    issues.push('validation invocation manifest ID does not match');
  }
  if (validation.invocation_manifest_hash !== canonicalHash(manifest)) {
    issues.push('validation invocation manifest hash does not match');
  }
  if (!Array.isArray(manifest.members)) {
    issues.push('validation invocation manifest members must be an array');
  }
  if (!Array.isArray(manifest.expected_members)) {
    issues.push('validation invocation manifest expected_members must be an array');
  }
  if (manifest.cohort_size !== (manifest.members?.length ?? -1)) {
    issues.push('validation invocation manifest cohort_size does not match members');
  }
  const manifestContentIdentities = new Set();
  const manifestGameplayBuildIdentities = new Set();
  for (const candidate of manifest.members ?? []) {
    const schema = String(candidate?.content_fingerprint_schema ?? '');
    const fingerprint = String(candidate?.content_fingerprint ?? '');
    if (schema === 'authored_fragment_resource_bytes_v1'
        && /^[a-f0-9]{64}$/.test(fingerprint)) {
      manifestContentIdentities.add(`${schema}|${fingerprint}`);
    } else {
      issues.push('validation invocation manifest member content identity is invalid');
    }
    const buildSchema = String(candidate?.gameplay_build_fingerprint_schema ?? '');
    const buildFingerprint = String(candidate?.gameplay_build_fingerprint ?? '');
    if (buildSchema === 'gameplay_build_resource_set_bytes_v1'
        && /^[a-f0-9]{64}$/.test(buildFingerprint)) {
      manifestGameplayBuildIdentities.add(`${buildSchema}|${buildFingerprint}`);
    } else {
      issues.push('validation invocation manifest member gameplay build identity is invalid');
    }
  }
  if (manifestContentIdentities.size !== 1) {
    issues.push('validation invocation manifest content identity is not uniform');
  }
  if (manifestGameplayBuildIdentities.size !== 1) {
    issues.push('validation invocation manifest gameplay build identity is not uniform');
  }
  if (validation.cohort_size !== manifest.cohort_size) {
    issues.push('validation cohort_size does not match the invocation manifest');
  }
  if (typeof manifest.passed !== 'boolean') {
    issues.push('validation invocation manifest passed must be explicit');
  }
  if (!Array.isArray(manifest.failures)) {
    issues.push('validation invocation manifest failures must be an array');
  } else if (manifest.failure_count !== manifest.failures.length) {
    issues.push('validation invocation manifest failure_count does not match failures');
  }
  if (typeof manifest.passed === 'boolean') {
    if (manifest.passed && manifest.failure_count !== 0) {
      issues.push('passed invocation manifest must have zero failures');
    } else if (!manifest.passed && manifest.failure_count < 1) {
      issues.push('failed invocation manifest must report at least one failure');
    }
  }
  const member = validation.cohort_member;
  if (!member || typeof member !== 'object' || Array.isArray(member)) {
    issues.push('validation.cohort_member is required');
  } else {
    if (canonicalJson(cohortIdentity(member)) !== canonicalJson(cohortIdentity(run))
        || member.run_id !== run.run_id || member.trace_id !== run.trace_id
        || member.decision_count !== decisionCount) {
      issues.push('validation cohort member does not match this run');
    }
    if (member.summary_record_hash !== summaryRecord?.record_hash) {
      issues.push('validation cohort member summary hash does not match this run');
    }
    if (member.content_fingerprint_schema !== run.content_fingerprint_schema
        || member.content_fingerprint !== run.content_fingerprint) {
      issues.push('validation cohort member content identity does not match this run');
    }
    if (member.gameplay_build_fingerprint_schema !== run.gameplay_build_fingerprint_schema
        || member.gameplay_build_fingerprint !== run.gameplay_build_fingerprint) {
      issues.push('validation cohort member gameplay build identity does not match this run');
    }
    if (member.trace_complete !== (summaryRecord?.summary?.trace_complete === true)
        || member.persona_goal_reached !== (summaryRecord?.summary?.persona_goal_reached === true)) {
      issues.push('validation cohort member summary verdict does not match this run');
    }
    if ((manifest.members ?? []).filter((candidate) =>
      canonicalJson(candidate) === canonicalJson(member)).length !== 1) {
      issues.push('validation cohort member must appear exactly once in manifest');
    }
  }
  if (manifest.passed === true) {
    if (canonicalJson(manifest.expected_members) !== canonicalJson(expectedValidationCohort(run))) {
      issues.push('validation invocation manifest expected matrix is not current');
    }
    if (manifest.failure_count !== 0 || !Array.isArray(manifest.failures)
        || manifest.failures.length !== 0) {
      issues.push('passed invocation manifest contains failures');
    }
  } else if (validation.passed === true) {
    issues.push('a passed validation cannot bind a failed invocation manifest');
  }
  return [...new Set(issues)].sort();
}

export function inspectTraceRecords(records, expected = {}) {
  const issues = [];
  let previousHash = '';
  let run = null;
  let summaryRecord = null;
  let decisionCount = 0;
  let sawValidation = false;
  let validationRecord = null;
  const decisions = [];

  for (const [index, record] of records.entries()) {
    const line = index + 1;
    if (record?.schema !== TRACE_SCHEMA) issues.push(`line ${line} has the wrong trace schema`);
    if (record?.previous_hash !== previousHash) issues.push(`line ${line} breaks the hash chain`);
    const payload = { ...record };
    delete payload.record_hash;
    if (!record?.record_hash || record.record_hash !== canonicalHash(payload)) {
      issues.push(`line ${line} has an invalid record hash`);
    }
    previousHash = String(record?.record_hash ?? '');

    if (record?.record_type === 'run') {
      if (index !== 0 || run !== null) issues.push(`line ${line} has a misplaced run header`);
      run = record.run ?? null;
      issues.push(...validateRunMetadata(run).map((issue) => `line ${line}: ${issue}`));
    } else if (record?.record_type === 'decision') {
      if (run === null || summaryRecord !== null || sawValidation) {
        issues.push(`line ${line} has a decision outside the run body`);
      }
      if (run && canonicalJson(record.run) !== canonicalJson(runIdentity(run))) {
        issues.push(`line ${line} decision identity does not match the run header`);
      }
      if (record.decision_index !== decisionCount) {
        issues.push(`line ${line} has a noncontiguous decision index`);
      }
      issues.push(...validateDecisionRecord(record).map((issue) => `line ${line}: ${issue}`));
      issues.push(...inputSequenceProgressionReasons(decisions, record)
        .map((issue) => `line ${line}: ${issue}`));
      issues.push(...observationProgressionReasons(decisions, record)
        .map((issue) => `line ${line}: ${issue}`));
      const evidence = classifyEvidence(record);
      if (canonicalJson(record.evidence) !== canonicalJson(evidence)) {
        issues.push(`line ${line} has self-declared evidence classification`);
      }
      if (evidence.eligible_for_learning !== true) {
        issues.push(`line ${line} is not eligible player evidence`);
      }
      decisions.push(record);
      decisionCount += 1;
    } else if (record?.record_type === 'summary') {
      if (run === null || summaryRecord !== null || sawValidation) {
        issues.push(`line ${line} has a misplaced summary`);
      }
      if (run && canonicalJson(record.run) !== canonicalJson(runIdentity(run))) {
        issues.push(`line ${line} summary identity does not match the run header`);
      }
      summaryRecord = record;
    } else if (record?.record_type === 'validation') {
      if (summaryRecord === null) issues.push(`line ${line} precedes the summary`);
      sawValidation = true;
      validationRecord = record;
      if (run && canonicalJson(record.run) !== canonicalJson(runIdentity(run))) {
        issues.push(`line ${line} validation identity does not match the run header`);
      }
      if (record.summary_record_hash !== summaryRecord?.record_hash) {
        issues.push(`line ${line} validation does not bind the run summary`);
      }
      issues.push(...validateValidationReceipt(record.validation, run, decisionCount, summaryRecord)
        .map((issue) => `line ${line}: ${issue}`));
    } else {
      issues.push(`line ${line} has unknown record_type ${String(record?.record_type)}`);
    }
  }

  if (run === null) issues.push('trace has no run header');
  if (summaryRecord === null) issues.push('trace has no summary');
  if (run !== null) {
    const expectedPlatform = String(expected.executionPlatform ?? 'web');
    if (run.execution_platform !== expectedPlatform) {
      issues.push(`run platform is not ${expectedPlatform}`);
    }
    if (run.fragment_id !== 'basin_fill_proof') issues.push('run fragment is not basin_fill_proof');
    if (expected.persona && run.persona !== expected.persona) {
      issues.push(`run persona ${String(run.persona)} does not match ${expected.persona}`);
    }
    if (Number.isInteger(expected.repeatEachIndex)) {
      if (run.seed !== expected.repeatEachIndex) issues.push('run seed does not match repeat index');
      if (run.repeat_index !== expected.repeatEachIndex) {
        issues.push('run repeat_index does not match repeat identity');
      }
      const expectedSuffix = `${expectedPlatform}_${expected.repeatEachIndex}_${expected.repeatEachIndex}`;
      if (!String(run.run_id ?? '').endsWith(expectedSuffix)) {
        issues.push('run id does not match repeat identity');
      }
    }
  }
  if (expected.requirePassedValidation === true) {
    if (validationRecord === null) {
      issues.push('trace has no final validation receipt');
    } else if (validationRecord.validation?.passed !== true
        || validationRecord.validation?.failure_count !== 0
        || validationRecord.validation?.check_count < 1) {
      issues.push('final validation receipt is not green');
    }
  }
  if (summaryRecord !== null && run !== null) {
    if (canonicalJson(summaryRecord.run) !== canonicalJson(runIdentity(run))) {
      issues.push('summary identity does not match the run header');
    }
    if (summaryRecord.decision_count !== decisionCount) {
      issues.push('summary decision count does not match the trace');
    }
    const goal = deriveBasinPersonaGoal(run, decisions);
    const ineligible = decisions.filter((record) =>
      classifyEvidence(record).eligible_for_learning !== true).map((record) => record.decision_index);
    if (summaryRecord.summary?.persona_goal_reached !== goal.reached
        || canonicalJson(summaryRecord.summary?.goal_evidence) !== canonicalJson(goal.evidence)) {
      issues.push('summary persona goal is not derived from persisted observations');
    }
    if (summaryRecord.summary?.trace_complete === true
        && (!goal.reached || ineligible.length > 0)) {
      issues.push('summary trace_complete does not fail closed');
    }
    if (summaryRecord.summary?.trace_complete !== true) issues.push('summary is not trace-complete');
    if (summaryRecord.summary?.evidence_failures !== 0) {
      issues.push('summary contains evidence failures');
    }
    if (!Array.isArray(summaryRecord.summary?.ineligible_decision_indices)
        || canonicalJson(summaryRecord.summary.ineligible_decision_indices)
          !== canonicalJson(ineligible)) {
      issues.push('summary contains ineligible decision indices');
    }
  }

  return {
    issues: [...new Set(issues)].sort(),
    run,
    summaryRecord,
    decisions,
    decisionCount,
    previousHash,
    validationRecord,
  };
}

export function makeValidationReceipt(document, invocationId, {
  passed, checkCount, failureCount, invocationManifest,
}) {
  const run = document.run;
  return {
    schema: VALIDATION_SCHEMA,
    contract_id: `web_${run.fragment_id}_${run.persona}_v${VALIDATION_CONTRACT_VERSION}`,
    contract_version: VALIDATION_CONTRACT_VERSION,
    validator_id: VALIDATION_VALIDATOR_ID,
    execution_platform: 'web',
    invocation_id: invocationId,
    passed: Boolean(passed),
    check_count: Math.max(0, Number(checkCount) || 0),
    failure_count: Math.max(0, Number(failureCount) || 0),
    checked_decision_count: document.decisionCount,
    invocation_manifest: invocationManifest,
    invocation_manifest_hash: canonicalHash(invocationManifest),
    cohort_size: Number(invocationManifest?.cohort_size ?? 0),
    cohort_member: invocationMemberProof(document),
  };
}

export function makeValidationRecord(records, document, receipt) {
  const record = {
    schema: TRACE_SCHEMA,
    record_type: 'validation',
    run: runIdentity(document.run),
    summary_record_hash: document.summaryRecord.record_hash,
    validation: receipt,
    previous_hash: records.at(-1).record_hash,
  };
  record.record_hash = canonicalHash(record);
  return record;
}

async function readTrace(pathname, expected) {
  const records = parseTraceText(await readFile(pathname, 'utf8'));
  return { pathname: path.resolve(pathname), records, ...inspectTraceRecords(records, expected) };
}

async function appendReceipt(document, receipt) {
  const record = makeValidationRecord(document.records, document, receipt);
  await appendFile(document.pathname, `${canonicalJson(record)}\n`, 'utf8');
  const verified = await readTrace(document.pathname, {});
  if (verified.issues.length > 0 || verified.previousHash !== record.record_hash) {
    throw new Error(`appended validation failed verification for ${document.pathname}: ${verified.issues.join('; ')}`);
  }
  return { document: verified, record };
}

function artifactFileName(run) {
  const suffix = String(run.run_id ?? '').match(/web_(\d+)_(\-?\d+)$/);
  if (!suffix) return '';
  return `${run.persona}__${run.fragment_id}__web_${suffix[1]}_${suffix[2]}.jsonl`;
}

function traceCopies(attachmentPath, run) {
  const attachment = path.resolve(attachmentPath);
  const parent = path.dirname(attachment);
  const testOutput = path.basename(parent).toLowerCase() === 'attachments'
    ? path.dirname(parent) : parent;
  const primary = path.join(testOutput, artifactFileName(run));
  return [...new Map([
    [attachment.toLowerCase(), { pathname: attachment, primary: false }],
    [primary.toLowerCase(), { pathname: primary, primary: true }],
  ]).values()];
}

function runChild(command, args, { cwd, timeoutMs }) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd, env: process.env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
    child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error(`distillation preview timed out after ${timeoutMs} ms\n${stdout}\n${stderr}`));
    }, timeoutMs);
    child.on('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      if (code === 0) resolve({ stdout, stderr });
      else reject(new Error(`distillation preview exited ${code}\n${stdout}\n${stderr}`));
    });
  });
}

export function validateDistillationPreview(preview, primaryDocuments, invocationId) {
  const issues = [];
  if (!preview || typeof preview !== 'object' || Array.isArray(preview)) {
    return ['distillation preview is not an object'];
  }
  if (preview.schema !== 'persona_decision_library_v3') {
    issues.push('distillation preview schema is not persona_decision_library_v3');
  }
  if (preview.distillation?.minimum_support !== 2) {
    issues.push('distillation preview minimum support is not the strict repeated-run threshold');
  }
  const documents = primaryDocuments ?? [];
  const currentTraceIds = new Set(documents.map((document) => String(document?.run?.trace_id ?? ''))
    .filter(Boolean));
  const currentRunIds = new Set(documents.map((document) => String(document?.run?.run_id ?? ''))
    .filter(Boolean));
  if (currentTraceIds.size !== 4 || currentRunIds.size !== 4) {
    issues.push('distillation preview validator did not receive four unique current traces');
  }
  for (const rejection of preview.rejected_evidence ?? []) {
    if (currentTraceIds.has(String(rejection?.trace_id ?? ''))
        || currentRunIds.has(String(rejection?.run_id ?? ''))) {
      issues.push(`current trace was rejected by GDScript distillation:${String(
        rejection?.trace_id ?? rejection?.run_id ?? '',
      )}:${String(rejection?.reason ?? '')}`);
    }
  }

  const nodes = Array.isArray(preview.nodes) ? preview.nodes : [];
  if (!Array.isArray(preview.nodes)) issues.push('distillation preview nodes must be an array');
  const nodeById = new Map(nodes
    .filter((node) => node && typeof node === 'object' && !Array.isArray(node))
    .map((node) => [String(node.id ?? ''), node]));
  const expectedNodeIds = new Set([
    ...EXPECTED_FRAGMENT_NODES.keys(), ...EXPECTED_GLOBAL_NODES.keys(),
  ]);
  const nodesWithCurrentProvenance = new Set();
  for (const node of nodes) {
    for (const source of node?.evidence?.provenance ?? []) {
      if (currentTraceIds.has(String(source?.trace_id ?? ''))) {
        nodesWithCurrentProvenance.add(String(node.id ?? ''));
      }
    }
  }
  const unexpectedCurrentNodes = [...nodesWithCurrentProvenance]
    .filter((nodeId) => !expectedNodeIds.has(nodeId)).sort();
  if (unexpectedCurrentNodes.length > 0) {
    issues.push(`current invocation distilled unexpected policy nodes:${unexpectedCurrentNodes.join(',')}`);
  }

  const validateNode = (nodeId, persona, scope) => {
    const node = nodeById.get(nodeId);
    if (!node) {
      issues.push(`distillation preview is missing expected node:${nodeId}`);
      return;
    }
    if (node?.policy?.scope !== scope) {
      issues.push(`distillation node scope mismatch:${nodeId}:${String(node?.policy?.scope ?? '')}`);
    }
    const allProvenance = Array.isArray(node?.evidence?.provenance)
      ? node.evidence.provenance : [];
    const currentProvenance = allProvenance.filter((source) =>
      currentTraceIds.has(String(source?.trace_id ?? '')));
    const documentByTraceId = new Map(documents.map((document) => [
      String(document?.run?.trace_id ?? ''), document,
    ]));
    const expectedPersonaTraces = documents
      .filter((document) => document?.run?.persona === persona)
      .map((document) => String(document.run.trace_id)).sort();
    const actualPersonaTraces = currentProvenance
      .map((source) => String(source?.trace_id ?? '')).sort();
    if (canonicalJson(actualPersonaTraces) !== canonicalJson(expectedPersonaTraces)) {
      issues.push(`distillation node does not carry both exact current persona traces:${nodeId}`);
    }
    const repeatIndices = currentProvenance
      .map((source) => Number(source?.repeat_index ?? -1)).sort((a, b) => a - b);
    if (canonicalJson(repeatIndices) !== canonicalJson(REQUIRED_REPEATS)) {
      issues.push(`distillation node does not carry repeats 0 and 1:${nodeId}`);
    }
    if (currentProvenance.some((source) =>
      source?.validation_invocation_id !== invocationId
        || source?.execution_platform !== 'web'
        || source?.fragment_id !== 'basin_fill_proof'
        || source?.persona !== persona
        || source?.verdict !== 'supports'
        || source?.invocation_manifest_passed !== true
        || source?.invocation_manifest_failure_count !== 0
        || source?.invocation_cohort_size !== 4
        || source?.gameplay_build_fingerprint_schema
          !== documentByTraceId.get(String(source?.trace_id ?? ''))?.run
            ?.gameplay_build_fingerprint_schema
        || source?.gameplay_build_fingerprint
          !== documentByTraceId.get(String(source?.trace_id ?? ''))?.run
            ?.gameplay_build_fingerprint)) {
      issues.push(`distillation node current provenance is not strict and supporting:${nodeId}`);
    }
    if (scope === 'fragment') {
      if (node.status !== 'validated' || node.eligible_for_automation !== true) {
        issues.push(`repeated fragment node is not automation-eligible:${nodeId}`);
      }
    } else if (node.status !== 'candidate' || node.eligible_for_automation !== false
        || node?.evidence?.distinct_content_count !== 1) {
      issues.push(`single-content global node did not remain a one-content candidate:${nodeId}`);
    }
  };

  for (const [nodeId, persona] of EXPECTED_FRAGMENT_NODES) {
    validateNode(nodeId, persona, 'fragment');
  }
  for (const [nodeId, persona] of EXPECTED_GLOBAL_NODES) {
    validateNode(nodeId, persona, 'global');
  }
  return [...new Set(issues)].sort();
}

async function runDistillationPreview(primaryDocuments, invocationId) {
  const godot = String(process.env.TRAWF_GODOT_PATH ?? '').trim();
  const powershell = String(process.env.TRAWF_POWERSHELL_PATH ?? '').trim();
  const gateLauncher = String(process.env.TRAWF_TEST_GATE_LAUNCHER ?? '').trim();
  const gateArtifactDirectory = String(
    process.env.TRAWF_GATE_ARTIFACT_DIRECTORY ?? '',
  ).trim();
  const project = path.resolve(String(process.env.TRAWF_PROJECT_PATH ?? '').trim());
  if (!godot) throw new Error('TRAWF_GODOT_PATH is required for strict GDScript trace validation');
  if (!powershell || !gateLauncher || !gateArtifactDirectory) {
    throw new Error(
      'strict GDScript trace validation requires the tracked contained-Godot launcher environment',
    );
  }
  if (!process.env.TRAWF_PROJECT_PATH) {
    throw new Error('TRAWF_PROJECT_PATH is required for strict GDScript trace validation');
  }
  const artifactRoot = path.resolve(process.env.TRAWF_PLAYWRIGHT_OUTPUT_DIR
    ?? path.join(project, '..', '.test-gate', 'playwright'));
  await mkdir(artifactRoot, { recursive: true });
  const outputPath = path.join(artifactRoot, `persona-decision-library.${invocationId}.preview.json`);
  const requestPath = path.join(artifactRoot, `persona-distillation-request.${invocationId}.json`);
  await writeFile(requestPath, `${JSON.stringify({
    schema: 'persona_distillation_request_v1',
    traces: primaryDocuments.map((document) => path.resolve(document.pathname)),
    output: path.resolve(outputPath),
  })}\n`, { encoding: 'utf8', flag: 'wx' });
  const args = [
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', path.resolve(gateLauncher),
    '-GodotPath', path.resolve(godot),
    '-ProjectPath', project,
    '-ArtifactDirectory', path.resolve(gateArtifactDirectory),
    '-PersonaDistillationRequest', path.resolve(requestPath),
  ];
  const result = await runChild(
    path.resolve(powershell), args, { cwd: project, timeoutMs: DISTILLATION_TIMEOUT_MS },
  );
  const previewText = await readFile(outputPath, 'utf8');
  let preview;
  try {
    preview = JSON.parse(previewText);
  } catch (error) {
    throw new Error(`GDScript distillation preview is not valid JSON: ${error.message}`);
  }
  const previewIssues = validateDistillationPreview(preview, primaryDocuments, invocationId);
  if (previewIssues.length > 0) {
    throw new Error(`GDScript distillation preview rejected the current cohort: ${previewIssues.join('; ')}`);
  }
  return { outputPath, preview, ...result };
}

async function writeArtifactManifest(primaryDocuments, invocationManifest, preview, invocationId) {
  const artifactRoot = path.resolve(process.env.TRAWF_PLAYWRIGHT_OUTPUT_DIR
    ?? path.dirname(primaryDocuments[0].pathname));
  await mkdir(artifactRoot, { recursive: true });
  const traces = [];
  for (const document of primaryDocuments) {
    const bytes = await readFile(document.pathname);
    traces.push({
      ...invocationMemberProof(document),
      path: document.pathname,
      validation_record_hash: document.previousHash,
      file_sha256: createHash('sha256').update(bytes).digest('hex'),
    });
  }
  traces.sort((left, right) => cohortMemberProofKey(left).localeCompare(cohortMemberProofKey(right)));
  const artifact = {
    schema: 'persona_web_trace_artifact_manifest_v1',
    invocation_id: invocationId,
    invocation_manifest: invocationManifest,
    invocation_manifest_hash: canonicalHash(invocationManifest),
    distillation_preview: preview.outputPath,
    traces,
  };
  const pathname = path.join(artifactRoot, 'persona-trace-manifest.json');
  await writeFile(pathname, `${JSON.stringify(artifact, null, 2)}\n`, 'utf8');
  return pathname;
}

async function recursiveJsonlPaths(root) {
  const result = [];
  const visit = async (directory) => {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const pathname = path.join(directory, entry.name);
      if (entry.isDirectory()) await visit(pathname);
      else if (entry.isFile() && entry.name.toLowerCase().endsWith('.jsonl')) {
        result.push(path.resolve(pathname));
      }
    }
  };
  await visit(path.resolve(root));
  return result.sort((left, right) => left.localeCompare(right));
}

export async function buildNativeArtifactManifest(nativeUserDataRoot, outputPath) {
  const tracePaths = await recursiveJsonlPaths(nativeUserDataRoot);
  if (tracePaths.length !== 4) {
    throw new Error(`Native persona artifact root contains ${tracePaths.length} JSONL files, expected 4`);
  }
  const documents = [];
  for (const pathname of tracePaths) {
    const document = await readTrace(pathname, {
      executionPlatform: 'native', requirePassedValidation: true,
    });
    if (document.issues.length > 0) {
      throw new Error(`Native persona trace is invalid: ${pathname}: ${document.issues.join('; ')}`);
    }
    const repeatIndex = Number(document.run?.repeat_index ?? -1);
    const expectedSuffix = `native_${repeatIndex}_${repeatIndex}`;
    if (![0, 1].includes(repeatIndex) || document.run?.seed !== repeatIndex
        || !String(document.run?.run_id ?? '').endsWith(expectedSuffix)) {
      throw new Error(`Native persona repeat identity is invalid: ${pathname}`);
    }
    documents.push(document);
  }
  documents.sort((left, right) => cohortMemberProofKey(left.run)
    .localeCompare(cohortMemberProofKey(right.run)));
  const invocationIds = new Set(documents.map((document) => String(
    document.validationRecord?.validation?.invocation_id ?? '',
  )));
  if (invocationIds.size !== 1 || ![...invocationIds][0]) {
    throw new Error('Native persona traces do not share one final validation invocation');
  }
  const invocationId = [...invocationIds][0];
  const recomputedManifest = makeInvocationManifest(documents, invocationId);
  if (recomputedManifest.passed !== true) {
    throw new Error(`Native persona cohort manifest fails closed: ${recomputedManifest.failures.join('; ')}`);
  }
  const manifestHashes = new Set();
  for (const document of documents) {
    const validation = document.validationRecord.validation;
    const boundManifest = validation.invocation_manifest;
    const boundHash = String(validation.invocation_manifest_hash ?? '');
    if (canonicalJson(boundManifest) !== canonicalJson(recomputedManifest)
        || boundHash !== canonicalHash(recomputedManifest)) {
      throw new Error(`Native final validation does not bind the recomputed cohort: ${document.pathname}`);
    }
    manifestHashes.add(boundHash);
  }
  if (manifestHashes.size !== 1) {
    throw new Error('Native persona traces do not share one invocation manifest hash');
  }
  const traces = [];
  for (const document of documents) {
    const bytes = await readFile(document.pathname);
    traces.push({
      ...invocationMemberProof(document),
      path: document.pathname,
      validation_record_hash: document.previousHash,
      file_sha256: createHash('sha256').update(bytes).digest('hex'),
    });
  }
  const artifact = {
    schema: 'persona_native_trace_artifact_manifest_v1',
    invocation_id: invocationId,
    invocation_manifest: recomputedManifest,
    invocation_manifest_hash: canonicalHash(recomputedManifest),
    traces,
  };
  await mkdir(path.dirname(path.resolve(outputPath)), { recursive: true });
  await writeFile(path.resolve(outputPath), `${JSON.stringify(artifact, null, 2)}\n`, 'utf8');
  return artifact;
}

function validateArtifactManifest(artifact, schema, executionPlatform, issues) {
  if (!artifact || typeof artifact !== 'object' || Array.isArray(artifact)) {
    issues.push(`${executionPlatform}_artifact_not_an_object`);
    return [];
  }
  if (artifact.schema !== schema) issues.push(`${executionPlatform}_artifact_schema_invalid`);
  const manifest = artifact.invocation_manifest;
  if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)) {
    issues.push(`${executionPlatform}_invocation_manifest_missing`);
  } else {
    if (manifest.passed !== true || manifest.failure_count !== 0
        || !Array.isArray(manifest.failures) || manifest.failures.length !== 0) {
      issues.push(`${executionPlatform}_invocation_manifest_not_green`);
    }
    if (manifest.execution_platform !== executionPlatform || manifest.cohort_size !== 4) {
      issues.push(`${executionPlatform}_invocation_manifest_cohort_invalid`);
    }
    if (artifact.invocation_id !== manifest.invocation_id
        || artifact.invocation_manifest_hash !== canonicalHash(manifest)) {
      issues.push(`${executionPlatform}_invocation_manifest_binding_invalid`);
    }
  }
  const traces = Array.isArray(artifact.traces) ? artifact.traces : [];
  if (traces.length !== 4) issues.push(`${executionPlatform}_artifact_trace_count_invalid`);
  const identities = sortedCohortIdentities(traces);
  const expected = sortedCohortIdentities(['dean_takahashi', 'eazy_speezy'].flatMap((persona) =>
    REQUIRED_REPEATS.map((repeat_index) => ({
      execution_platform: executionPlatform,
      fragment_id: 'basin_fill_proof',
      persona,
      repeat_index,
    }))));
  if (canonicalJson(identities) !== canonicalJson(expected)) {
    issues.push(`${executionPlatform}_artifact_persona_repeat_matrix_invalid`);
  }
  const proofMembers = manifest?.members ?? [];
  for (const trace of traces) {
    if (typeof trace?.path !== 'string' || trace.path.trim() === '') {
      issues.push(`${executionPlatform}_artifact_trace_path_missing`);
    }
    if (!/^[a-f0-9]{64}$/.test(String(trace?.file_sha256 ?? ''))) {
      issues.push(`${executionPlatform}_artifact_trace_digest_invalid`);
    }
    if ((proofMembers ?? []).filter((member) =>
      canonicalJson(member) === canonicalJson(invocationMemberProof({
        run: trace,
        summaryRecord: {
          record_hash: trace.summary_record_hash,
          summary: {
            trace_complete: trace.trace_complete,
            persona_goal_reached: trace.persona_goal_reached,
          },
        },
        decisionCount: trace.decision_count,
      }))).length !== 1) {
      issues.push(`${executionPlatform}_artifact_trace_not_bound_to_invocation_manifest`);
    }
  }
  return traces;
}

export async function validateCombinedDistillationPreview(
  nativeArtifact, webArtifact, preview,
) {
  const issues = [];
  const nativeTraces = validateArtifactManifest(
    nativeArtifact, 'persona_native_trace_artifact_manifest_v1', 'native', issues,
  );
  const webTraces = validateArtifactManifest(
    webArtifact, 'persona_web_trace_artifact_manifest_v1', 'web', issues,
  );
  const traces = [...nativeTraces, ...webTraces];
  const traceById = new Map(traces.map((trace) => [String(trace?.trace_id ?? ''), trace]));
  const traceIds = traces.map((trace) => String(trace?.trace_id ?? '')).filter(Boolean);
  const currentTraceIds = new Set(traceIds);
  if (traces.length !== 8 || currentTraceIds.size !== 8) {
    issues.push('combined_artifacts_do_not_identify_exactly_eight_unique_primary_traces');
  }
  const contentIdentities = new Set(traces.map((trace) =>
    `${String(trace?.content_fingerprint_schema ?? '')}|${String(trace?.content_fingerprint ?? '')}`));
  if (contentIdentities.size !== 1 || ![...contentIdentities][0]?.startsWith(
    'authored_fragment_resource_bytes_v1|',
  )) {
    issues.push('combined_artifacts_content_identity_mismatch');
  }
  const gameplayBuildIdentities = new Set(traces.map((trace) =>
    `${String(trace?.gameplay_build_fingerprint_schema ?? '')}|${String(
      trace?.gameplay_build_fingerprint ?? '',
    )}`));
  if (gameplayBuildIdentities.size !== 1 || ![...gameplayBuildIdentities][0]?.startsWith(
    'gameplay_build_resource_set_bytes_v1|',
  )) {
    issues.push('combined_artifacts_gameplay_build_identity_mismatch');
  }
  for (const trace of traces) {
    try {
      const bytes = await readFile(path.resolve(trace.path));
      if (createHash('sha256').update(bytes).digest('hex') !== trace.file_sha256) {
        issues.push(`artifact_trace_digest_mismatch:${trace.trace_id}`);
      }
    } catch (error) {
      issues.push(`artifact_trace_unreadable:${trace.trace_id}:${error.message}`);
    }
  }
  if (!preview || typeof preview !== 'object' || Array.isArray(preview)) {
    issues.push('combined_preview_not_an_object');
    return [...new Set(issues)].sort();
  }
  if (preview.schema !== 'persona_decision_library_v3') {
    issues.push('combined_preview_schema_invalid');
  }
  if (preview.distillation?.minimum_support !== 2) {
    issues.push('combined_preview_minimum_support_invalid');
  }
  for (const rejection of preview.rejected_evidence ?? []) {
    const identity = String(rejection?.trace_id ?? rejection?.run_id ?? '');
    if (currentTraceIds.has(String(rejection?.trace_id ?? ''))
        || currentTraceIds.has(String(rejection?.run_id ?? ''))) {
      issues.push(`combined_current_trace_rejected:${identity}:${String(rejection?.reason ?? '')}`);
    }
  }
  const nodes = Array.isArray(preview.nodes) ? preview.nodes : [];
  if (!Array.isArray(preview.nodes)) issues.push('combined_preview_nodes_not_array');
  const nodeById = new Map(nodes.map((node) => [String(node?.id ?? ''), node]));
  const expectedNodeIds = new Set([
    ...EXPECTED_FRAGMENT_NODES.keys(), ...EXPECTED_GLOBAL_NODES.keys(),
  ]);
  for (const node of nodes) {
    if ((node?.evidence?.provenance ?? []).some((source) =>
      currentTraceIds.has(String(source?.trace_id ?? '')))
        && !expectedNodeIds.has(String(node?.id ?? ''))) {
      issues.push(`combined_unexpected_current_policy_node:${String(node?.id ?? '')}`);
    }
  }
  const validateNode = (nodeId, persona, scope) => {
    const node = nodeById.get(nodeId);
    if (!node) {
      issues.push(`combined_expected_node_missing:${nodeId}`);
      return;
    }
    if (node?.policy?.scope !== scope) issues.push(`combined_node_scope_mismatch:${nodeId}`);
    const expectedTraceIds = traces.filter((trace) => trace.persona === persona)
      .map((trace) => String(trace.trace_id)).sort();
    const currentProvenance = (node?.evidence?.provenance ?? []).filter((source) =>
      currentTraceIds.has(String(source?.trace_id ?? '')));
    const actualTraceIds = currentProvenance.map((source) => String(source.trace_id)).sort();
    if (canonicalJson(actualTraceIds) !== canonicalJson(expectedTraceIds)) {
      issues.push(`combined_node_exact_current_provenance_mismatch:${nodeId}`);
    }
    const platformCounts = { native: 0, web: 0 };
    for (const source of currentProvenance) {
      const platform = String(source?.execution_platform ?? '');
      if (Object.hasOwn(platformCounts, platform)) platformCounts[platform] += 1;
      const artifact = platform === 'native' ? nativeArtifact : webArtifact;
      if (source?.persona !== persona || source?.fragment_id !== 'basin_fill_proof'
          || source?.verdict !== 'supports' || source?.trace_integrity_verified !== true
          || source?.trace_complete !== true || source?.persona_goal_reached !== true
          || source?.validation_passed !== true || source?.validation_failure_count !== 0
          || source?.validation_check_count < 1 || source?.invocation_manifest_passed !== true
          || source?.invocation_manifest_failure_count !== 0
          || source?.invocation_cohort_size !== 4
          || source?.validation_invocation_id !== artifact?.invocation_id
          || source?.invocation_manifest_hash !== artifact?.invocation_manifest_hash
          || source?.gameplay_build_fingerprint_schema
            !== traceById.get(String(source?.trace_id ?? ''))?.gameplay_build_fingerprint_schema
          || source?.gameplay_build_fingerprint
            !== traceById.get(String(source?.trace_id ?? ''))?.gameplay_build_fingerprint) {
        issues.push(`combined_node_provenance_not_strict_support:${nodeId}:${source?.trace_id}`);
      }
    }
    if (platformCounts.native !== 2 || platformCounts.web !== 2) {
      issues.push(`combined_node_platform_support_mismatch:${nodeId}`);
    }
    if (scope === 'fragment') {
      if (node.status !== 'validated' || node.eligible_for_automation !== true) {
        issues.push(`combined_fragment_node_not_automation_eligible:${nodeId}`);
      }
    } else if (node.status !== 'candidate' || node.eligible_for_automation !== false
        || node?.evidence?.distinct_content_count !== 1) {
      issues.push(`combined_global_node_not_one_content_candidate:${nodeId}`);
    }
  };
  for (const [nodeId, persona] of EXPECTED_FRAGMENT_NODES) {
    validateNode(nodeId, persona, 'fragment');
  }
  for (const [nodeId, persona] of EXPECTED_GLOBAL_NODES) {
    validateNode(nodeId, persona, 'global');
  }
  return [...new Set(issues)].sort();
}

async function runReporterCli(argv) {
  const [command, ...args] = argv;
  if (command === '--build-native-manifest' && args.length === 2) {
    await buildNativeArtifactManifest(args[0], args[1]);
    return;
  }
  if (command === '--validate-combined' && args.length === 4) {
    const [nativePath, webPath, previewPath, reportPath] = args.map((value) => path.resolve(value));
    const [nativeArtifact, webArtifact, preview] = await Promise.all([
      readFile(nativePath, 'utf8').then(JSON.parse),
      readFile(webPath, 'utf8').then(JSON.parse),
      readFile(previewPath, 'utf8').then(JSON.parse),
    ]);
    const issues = await validateCombinedDistillationPreview(
      nativeArtifact, webArtifact, preview,
    );
    const report = {
      schema: 'persona_cross_platform_validation_v1',
      passed: issues.length === 0,
      issue_count: issues.length,
      issues,
      native_manifest: nativePath,
      web_manifest: webPath,
      combined_preview: previewPath,
    };
    await mkdir(path.dirname(reportPath), { recursive: true });
    await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
    if (issues.length > 0) throw new Error(issues.join('; '));
    return;
  }
  throw new Error('usage: --build-native-manifest <native-user-data-root> <output> | '
    + '--validate-combined <native-manifest> <web-manifest> <preview> <report>');
}

export default class PersonaValidationReporter {
  constructor() {
    this.requiredInvocation = false;
    this.results = [];
    this.invocationId = '';
  }

  onBegin(_config, suite) {
    const tests = suite.allTests().map((entry) => ({
      title: entry.title,
      repeatEachIndex: entry.repeatEachIndex,
    }));
    this.requiredInvocation = isRequiredBasinInvocation(tests);
    if (!this.requiredInvocation) {
      console.log('[PERSONA-VALIDATION] Partial/ad-hoc Web invocation: traces will remain unattested.');
    }
  }

  onTestEnd(testCase, result) {
    if (this.requiredInvocation && EXPECTED_TESTS.has(testCase.title)) {
      this.results.push({ testCase, result });
    }
  }

  async onEnd(fullResult) {
    if (!this.requiredInvocation) return undefined;
    const resultFailures = this.results.filter(({ result }) => result.status !== 'passed').length;
    const discoveryIssues = [];
    const copies = [];
    const primaryByRun = new Map();

    if (this.results.length !== EXPECTED_TESTS.size * REQUIRED_REPEATS.length) {
      discoveryIssues.push(`received ${this.results.length} test results, expected 4`);
    }
    for (const { testCase, result } of this.results) {
      const expectedPersona = EXPECTED_TESTS.get(testCase.title);
      const attachments = result.attachments.filter((attachment) =>
        attachment.contentType === 'application/x-ndjson' && attachment.path);
      if (result.status === 'passed' && attachments.length !== 1) {
        discoveryIssues.push(`${testCase.title} repeat ${testCase.repeatEachIndex} has ${attachments.length} trace attachments`);
        continue;
      }
      for (const attachment of attachments) {
        let attached;
        try {
          attached = await readTrace(attachment.path, {
            persona: expectedPersona, repeatEachIndex: testCase.repeatEachIndex,
          });
        } catch (error) {
          discoveryIssues.push(`cannot read ${attachment.path}: ${error.message}`);
          continue;
        }
        if (attached.issues.length > 0) {
          discoveryIssues.push(`${attachment.path}: ${attached.issues.join('; ')}`);
          continue;
        }
        for (const candidate of traceCopies(attachment.path, attached.run)) {
          try {
            const copy = await readTrace(candidate.pathname, {
              persona: expectedPersona, repeatEachIndex: testCase.repeatEachIndex,
            });
            if (copy.issues.length > 0) {
              discoveryIssues.push(`${candidate.pathname}: ${copy.issues.join('; ')}`);
            } else if (copy.summaryRecord.record_hash !== attached.summaryRecord.record_hash) {
              discoveryIssues.push(`${candidate.pathname}: attachment and primary summaries differ`);
            } else {
              copies.push(copy);
              if (candidate.primary) primaryByRun.set(copy.run.run_id, copy);
            }
          } catch (error) {
            discoveryIssues.push(`cannot read ${candidate.pathname}: ${error.message}`);
          }
        }
      }
    }

    const uniqueCopies = [...new Map(copies.map((document) =>
      [document.pathname.toLowerCase(), document])).values()];
    const primaryDocuments = [...primaryByRun.values()]
      .sort((left, right) => cohortMemberProofKey(left.run).localeCompare(cohortMemberProofKey(right.run)));
    if (uniqueCopies.length !== 8) discoveryIssues.push(`found ${uniqueCopies.length} stored trace copies, expected 8`);
    if (primaryDocuments.length !== 4) discoveryIssues.push(`found ${primaryDocuments.length} primary traces, expected 4`);
    this.invocationId = deterministicInvocationId(primaryDocuments, 'web');
    const invocationManifest = makeInvocationManifest(primaryDocuments, this.invocationId);
    if (invocationManifest.passed !== true) {
      discoveryIssues.push(...invocationManifest.failures.map((failure) => `invocation_manifest:${failure}`));
    }

    let invocationPassed = fullResult.status === 'passed' && resultFailures === 0
      && discoveryIssues.length === 0;
    let failureCount = invocationPassed ? 0 : Math.max(1, resultFailures + discoveryIssues.length);
    const appendedGreen = [];

    try {
      for (const document of uniqueCopies) {
        const appended = await appendReceipt(document, makeValidationReceipt(
          document, this.invocationId, {
            passed: invocationPassed,
            checkCount: this.results.length + (invocationPassed ? 1 : 0),
            failureCount,
            invocationManifest,
          },
        ));
        if (invocationPassed) appendedGreen.push(appended.document);
      }
    } catch (error) {
      discoveryIssues.push(error.message);
      invocationPassed = false;
      failureCount = Math.max(1, failureCount, discoveryIssues.length);
    }

    let preview = null;
    let manifestPath = '';
    if (invocationPassed && appendedGreen.length === 8) {
      try {
        const greenByPath = new Map(appendedGreen.map((document) =>
          [document.pathname.toLowerCase(), document]));
        const greenPrimaries = primaryDocuments.map((document) =>
          greenByPath.get(document.pathname.toLowerCase()));
        preview = await runDistillationPreview(greenPrimaries, this.invocationId);
        manifestPath = await writeArtifactManifest(
          greenPrimaries, invocationManifest, preview, this.invocationId,
        );
      } catch (error) {
        discoveryIssues.push(error.message);
        invocationPassed = false;
        failureCount = Math.max(1, failureCount, discoveryIssues.length);
      }
    }

    if (!invocationPassed && appendedGreen.length > 0) {
      for (const green of appendedGreen) {
        try {
          await appendReceipt(green, makeValidationReceipt(green, this.invocationId, {
            passed: false,
            checkCount: this.results.length + 1,
            failureCount,
            invocationManifest,
          }));
        } catch (error) {
          discoveryIssues.push(`revocation failed for ${green.pathname}: ${error.message}`);
        }
      }
    }

    if (invocationPassed && preview && manifestPath) {
      console.log(`[PERSONA-VALIDATION] PASS ${this.invocationId}: attested 4 traces (8 copies); strict preview ${preview.outputPath}; manifest ${manifestPath}.`);
      return undefined;
    }
    console.error(`[PERSONA-VALIDATION] FAIL ${this.invocationId}: ${[
      ...discoveryIssues,
      `suite_status=${fullResult.status}`,
      `test_failures=${resultFailures}`,
    ].join('; ')}`);
    if (fullResult.status === 'passed') return { status: 'failed' };
    return undefined;
  }
}

if (process.argv[1]
    && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  runReporterCli(process.argv.slice(2)).catch((error) => {
    console.error(`[PERSONA-CROSS-PLATFORM] ${error.stack ?? error.message}`);
    process.exitCode = 1;
  });
}
