extends RefCounted
## Only accepted ordinary motion frames train this bounded monotonic watchdog.
const CAPACITY := 64
const NOMINAL_GAP_USEC := 1000000.0 / 20.0
var gaps: Array[float] = []
var last_usec := -1
var bars := 4
var min_wait := NOMINAL_GAP_USEC * 2.0
var max_wait := NOMINAL_GAP_USEC * 8.0

func clear() -> void:
	gaps.clear()
	last_usec = -1
	bars = 4
	min_wait = NOMINAL_GAP_USEC * 2.0
	max_wait = NOMINAL_GAP_USEC * 8.0

func accepted(now_usec: int) -> void:
	if last_usec >= 0:
		var gap := float(now_usec - last_usec)
		# Stalls/degraded gaps cannot teach the watchdog to tolerate silence.
		# TCP batches are not a faster simulation cadence: the stream is
		# capped at 20 Hz; exclude sub-cadence burst deliveries from learning.
		if bars == 4 and gap >= NOMINAL_GAP_USEC * 0.5 and gap <= min_wait:
			gaps.append(gap)
			if gaps.size() > CAPACITY: gaps.pop_front()
			var sorted := gaps.duplicate()
			sorted.sort()
			var median: float = maxf(NOMINAL_GAP_USEC, sorted[sorted.size() / 2])
			var high: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.9))]
			min_wait = minf(NOMINAL_GAP_USEC * 4.0, minf(median * 4.0, maxf(median * 2.0, high * 1.5)))
			max_wait = minf(NOMINAL_GAP_USEC * 16.0, maxf(min_wait * 2.0, median * 8.0))
	last_usec = now_usec
	bars = 4

func poll(now_usec: int) -> int:
	if last_usec < 0: return bars
	var p := clampf((float(now_usec - last_usec) - min_wait) / (max_wait - min_wait), 0.0, 1.0)
	bars = clampi(ceili(4.0 * (1.0 - p)), 0, 4)
	return bars
