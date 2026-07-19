#include "event_scheduler.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <chrono>

using namespace godot;

EventScheduler::EventScheduler() :
		_current_tick(0.0),
		_speed(1.0),
		_paused(false),
		_seq_counter(0),
		_next_handle(1),
		_live_count(0) {
}

EventScheduler::~EventScheduler() {
}

void EventScheduler::_bind_methods() {
	ClassDB::bind_method(D_METHOD("schedule_at", "tick", "callback", "tag", "priority"), &EventScheduler::schedule_at, DEFVAL(""), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("schedule_after", "delay", "callback", "tag", "priority"), &EventScheduler::schedule_after, DEFVAL(""), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("cancel", "handle"), &EventScheduler::cancel);
	ClassDB::bind_method(D_METHOD("cancel_tag", "tag"), &EventScheduler::cancel_tag);
	ClassDB::bind_method(D_METHOD("advance", "real_delta"), &EventScheduler::advance);
	ClassDB::bind_method(D_METHOD("advance_ticks", "ticks"), &EventScheduler::advance_ticks);
	ClassDB::bind_method(D_METHOD("set_profiling", "enabled"), &EventScheduler::set_profiling);
	ClassDB::bind_method(D_METHOD("get_profile"), &EventScheduler::get_profile);
	ClassDB::bind_method(D_METHOD("set_speed", "mult"), &EventScheduler::set_speed);
	ClassDB::bind_method(D_METHOD("get_speed"), &EventScheduler::get_speed);
	ClassDB::bind_method(D_METHOD("pause"), &EventScheduler::pause);
	ClassDB::bind_method(D_METHOD("resume"), &EventScheduler::resume);
	ClassDB::bind_method(D_METHOD("is_paused"), &EventScheduler::is_paused);
	ClassDB::bind_method(D_METHOD("get_current_tick"), &EventScheduler::get_current_tick);
	ClassDB::bind_method(D_METHOD("pending_count"), &EventScheduler::pending_count);
	ClassDB::bind_method(D_METHOD("pop_next"), &EventScheduler::pop_next);
	ClassDB::bind_method(D_METHOD("serialize"), &EventScheduler::serialize);
	ClassDB::bind_method(D_METHOD("deserialize", "data"), &EventScheduler::deserialize);
	ClassDB::bind_method(D_METHOD("clear"), &EventScheduler::clear);

	ADD_SIGNAL(MethodInfo("event_fired", PropertyInfo(Variant::STRING, "tag")));
}

int EventScheduler::schedule_at(double tick, const Callable &callback, const String &tag, int priority) {
	// Scene changes and fragment resets can invalidate a bound object before its event is
	// dispatched. Never enqueue an already-dead callable: native builds report an ordinary
	// invalid-call error, but WebAssembly can trap as a `null function` invocation.
	if (callback.is_null() || !callback.is_valid()) {
		UtilityFunctions::push_warning("EventScheduler refused an invalid callback for tag: " + tag);
		return 0;
	}

	int handle = _next_handle++;

	ScheduledEvent event;
	event.key = { tick, priority, _seq_counter++ };
	event.callback = callback;
	event.tag = tag;
	event.handle = handle;

	_heap.push(event);
	_live_handles.insert(handle);
	_live_count++;

	if (!tag.is_empty()) {
		std::string tag_key = tag.utf8().get_data();
		_tag_to_handles[tag_key].push_back(handle);
	}

	return handle;
}

int EventScheduler::schedule_after(double delay, const Callable &callback, const String &tag, int priority) {
	return schedule_at(_current_tick + delay, callback, tag, priority);
}

bool EventScheduler::cancel(int handle) {
	// A handle that already fired is no longer cancellable. Tracking live handles also
	// prevents stale tag entries from driving the public pending count below zero.
	if (!_live_handles.count(handle) || _cancelled.count(handle)) {
		return false;
	}
	_cancelled.insert(handle);
	_live_handles.erase(handle);
	_live_count--;
	return true;
}

int EventScheduler::cancel_tag(const String &tag) {
	std::string tag_key = tag.utf8().get_data();
	auto it = _tag_to_handles.find(tag_key);
	if (it == _tag_to_handles.end()) {
		return 0;
	}

	int removed = 0;
	for (int h : it->second) {
		if (_live_handles.count(h) && !_cancelled.count(h)) {
			_cancelled.insert(h);
			_live_handles.erase(h);
			_live_count--;
			removed++;
		}
	}
	_tag_to_handles.erase(it);
	return removed;
}

void EventScheduler::advance(double real_delta) {
	if (_paused) {
		return;
	}
	double delta_ticks = real_delta * _speed * TICKS_PER_SECOND;
	advance_ticks(delta_ticks);
}

void EventScheduler::advance_ticks(double ticks) {
	if (_paused) {
		return;
	}
	double target = _current_tick + ticks;

	while (!_heap.empty()) {
		const ScheduledEvent &top = _heap.top();
		if (top.key.tick > target) {
			break;
		}

		// Copy and pop (top reference invalidated by pop)
		ScheduledEvent event = top;
		_heap.pop();

		// Lazy deletion: skip cancelled events
		if (_cancelled.count(event.handle)) {
			_cancelled.erase(event.handle);
			if (_profiling) {
				auto &slot = _profile[std::string("(cancelled_pop)/") + event.tag.utf8().get_data()];
				slot.first += 1;
			}
			continue;
		}

		_live_handles.erase(event.handle);
		_live_count--;
		_current_tick = event.key.tick;
		if (event.callback.is_null() || !event.callback.is_valid()) {
			UtilityFunctions::push_warning("EventScheduler skipped an invalidated callback for tag: " + event.tag);
			continue;
		}
		if (_profiling) {
			auto t0 = std::chrono::steady_clock::now();
			event.callback.call();
			auto usec = std::chrono::duration_cast<std::chrono::microseconds>(
					std::chrono::steady_clock::now() - t0).count();
			String key_s = event.tag + String("/") + String(event.callback.get_method());
			std::string key = key_s.utf8().get_data();
			auto &slot = _profile[key];
			slot.first += 1;
			slot.second += usec;
		} else {
			event.callback.call();
		}

		if (!event.tag.is_empty()) {
			emit_signal("event_fired", event.tag);
		}
	}

	_current_tick = target;
}

void EventScheduler::set_profiling(bool enabled) {
	_profiling = enabled;
	_profile.clear();
}

Dictionary EventScheduler::get_profile() const {
	Dictionary out;
	for (const auto &kv : _profile) {
		Array pair;
		pair.push_back((int64_t)kv.second.first);
		pair.push_back((double)kv.second.second / 1000.0);
		out[String(kv.first.c_str())] = pair;
	}
	return out;
}

Dictionary EventScheduler::pop_next() {
	while (!_heap.empty()) {
		ScheduledEvent event = _heap.top();
		_heap.pop();

		if (_cancelled.count(event.handle)) {
			_cancelled.erase(event.handle);
			continue;
		}

		_live_handles.erase(event.handle);
		_live_count--;
		if (event.callback.is_null() || !event.callback.is_valid()) {
			UtilityFunctions::push_warning("EventScheduler skipped an invalidated callback for tag: " + event.tag);
			continue;
		}
		double delta = event.key.tick - _current_tick;
		_current_tick = event.key.tick;
		event.callback.call();

		if (!event.tag.is_empty()) {
			emit_signal("event_fired", event.tag);
		}

		Dictionary result;
		result["tick"] = event.key.tick;
		result["tag"] = event.tag;
		result["delta"] = delta;
		return result;
	}
	return Dictionary();
}

void EventScheduler::set_speed(double mult) {
	_speed = mult > 0.0 ? mult : 0.0;
}

double EventScheduler::get_speed() const {
	return _speed;
}

void EventScheduler::pause() {
	_paused = true;
}

void EventScheduler::resume() {
	_paused = false;
}

bool EventScheduler::is_paused() const {
	return _paused;
}

double EventScheduler::get_current_tick() const {
	return _current_tick;
}

int EventScheduler::pending_count() const {
	return _live_count;
}

Dictionary EventScheduler::serialize() const {
	Dictionary data;
	data["current_tick"] = _current_tick;
	data["speed"] = _speed;
	data["paused"] = _paused;
	return data;
}

void EventScheduler::deserialize(const Dictionary &data) {
	_current_tick = data.get("current_tick", 0.0);
	_speed = data.get("speed", 1.0);
	_paused = data.get("paused", false);
}

void EventScheduler::clear() {
	// Clear the priority queue (no .clear() method)
	while (!_heap.empty()) {
		_heap.pop();
	}
	_cancelled.clear();
	_live_handles.clear();
	_tag_to_handles.clear();
	_live_count = 0;
}
