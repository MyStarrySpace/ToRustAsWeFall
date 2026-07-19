#ifndef EVENT_SCHEDULER_H
#define EVENT_SCHEDULER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>
#include <functional>
#include <queue>
#include <unordered_map>
#include <unordered_set>
#include <vector>

using namespace godot;

class EventScheduler : public RefCounted {
	GDCLASS(EventScheduler, RefCounted);

public:
	EventScheduler();
	~EventScheduler();

	// Scheduling
	int schedule_at(double tick, const Callable &callback, const String &tag = "", int priority = 0);
	int schedule_after(double delay, const Callable &callback, const String &tag = "", int priority = 0);

	// Cancellation
	bool cancel(int handle);
	int cancel_tag(const String &tag);

	// Time advancement
	void advance(double real_delta);
	void advance_ticks(double ticks);

	// Diagnostic per-callback profiling (perf hunts): times every dispatched callback,
	// keyed "tag/method". Off by default; enabling clears the accumulator.
	void set_profiling(bool enabled);
	godot::Dictionary get_profile() const;

	// Speed control
	void set_speed(double mult);
	double get_speed() const;

	// Pause control
	void pause();
	void resume();
	bool is_paused() const;

	// Queries
	double get_current_tick() const;
	int pending_count() const;

	// Pop-through: fire the next event regardless of current tick.
	// Returns Dictionary with "tick", "tag", "delta" (time since previous tick).
	// Returns empty Dictionary if no events pending.
	Dictionary pop_next();

	// Serialization (tick/speed/paused only — Callables aren't serializable)
	Dictionary serialize() const;
	void deserialize(const Dictionary &data);

	// Clear all pending events
	void clear();

protected:
	static void _bind_methods();

private:
	static constexpr double TICKS_PER_SECOND = 1.0;

	struct EventKey {
		double tick;
		int priority;
		uint64_t seq;

		bool operator>(const EventKey &other) const {
			if (tick != other.tick)
				return tick > other.tick;
			if (priority != other.priority)
				return priority > other.priority;
			return seq > other.seq;
		}
	};

	struct ScheduledEvent {
		EventKey key;
		Callable callback;
		String tag;
		int handle;
	};

	struct EventComparator {
		bool operator()(const ScheduledEvent &a, const ScheduledEvent &b) const {
			return a.key > b.key;
		}
	};

	double _current_tick;
	double _speed;
	bool _paused;

	std::priority_queue<ScheduledEvent, std::vector<ScheduledEvent>, EventComparator> _heap;
	std::unordered_set<int> _cancelled;
	std::unordered_set<int> _live_handles;
	std::unordered_map<std::string, std::vector<int>> _tag_to_handles;

	uint64_t _seq_counter;
	int _next_handle;
	int _live_count;
	bool _profiling = false;
	std::unordered_map<std::string, std::pair<long long, long long>> _profile; // key -> (count, usec)
};

#endif // EVENT_SCHEDULER_H
