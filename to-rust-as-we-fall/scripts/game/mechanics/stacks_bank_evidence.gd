class_name StacksBankEvidence
extends RefCounted

## Shared causal vocabulary for the Stacks bank deduction.
##
## The target trace is known before the player samples a bank. Each bank then exposes the result
## of the same three probes, so the answer comes from comparing input traits with durable output—not
## from colour, brightness, an answer-bearing title, or a hidden "visited all three" checklist.

const BANK_IDS := ["bank_a", "bank_b", "bank_c"]
const TARGET_SIGNATURE := "NO SIGNER // VALID CRC"
const TARGET_PROBE := "unsigned_valid"
const RETAINED := "RETAINED"

const BANK_OBSERVATIONS := {
	"bank_a": {
		"signed_valid": "RETAINED",
		"unsigned_valid": "REJECTED",
		"unsigned_bad": "QUARANTINED",
	},
	"bank_b": {
		"signed_valid": "RETAINED",
		"unsigned_valid": "RETAINED",
		"unsigned_bad": "REJECTED",
	},
	"bank_c": {
		"signed_valid": "RETAINED",
		"unsigned_valid": "MIRRORED // 0 STORED",
		"unsigned_bad": "REJECTED",
	},
}


static func bank_title(bank_id: String) -> String:
	return "BANK %s" % bank_id.trim_prefix("bank_").to_upper()


static func target_text() -> String:
	return "CLEANED REPORT OMITS SOURCE\nRAW SUPPORT TRACE // %s\nWHICH BANK KEPT A DURABLE COPY?" \
		% TARGET_SIGNATURE


static func observation_text(bank_id: String) -> String:
	var observation: Dictionary = BANK_OBSERVATIONS.get(bank_id, {})
	if observation.is_empty():
		return "NO SAMPLE"
	return "%s PROBE\nSIGNED + VALID  > %s\nNO SIGN + VALID > %s\nNO SIGN + BAD   > %s" % [
		bank_title(bank_id),
		str(observation.get("signed_valid", "NO RESULT")),
		str(observation.get("unsigned_valid", "NO RESULT")),
		str(observation.get("unsigned_bad", "NO RESULT")),
	]


static func compact_observation(bank_id: String) -> String:
	var observation: Dictionary = BANK_OBSERVATIONS.get(bank_id, {})
	if observation.is_empty():
		return "No probe result."
	return "%s // signed+valid %s; no-sign+valid %s; no-sign+bad %s." % [
		bank_title(bank_id),
		str(observation.get("signed_valid", "unknown")).to_lower(),
		str(observation.get("unsigned_valid", "unknown")).to_lower(),
		str(observation.get("unsigned_bad", "unknown")).to_lower(),
	]


static func target_result(bank_id: String) -> String:
	var observation: Dictionary = BANK_OBSERVATIONS.get(bank_id, {})
	return str(observation.get(TARGET_PROBE, "NO RESULT"))


static func supports_target(bank_id: String) -> bool:
	return target_result(bank_id) == RETAINED


static func solution_bank() -> String:
	var solution := ""
	for bank_id_v in BANK_IDS:
		var bank_id := str(bank_id_v)
		if not supports_target(bank_id):
			continue
		if solution != "":
			return ""
		solution = bank_id
	return solution


static func contradiction_text(bank_id: String) -> String:
	return "PREDICTION FALSIFIED // %s reports NO SIGN + VALID as %s, not RETAINED." % [
		bank_title(bank_id), target_result(bank_id)
	]
