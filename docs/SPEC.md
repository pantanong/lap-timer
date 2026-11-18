# Lap Timer App — Requirements (draft)

Reference app studied: LapTrophy 2.12.4 (feature reference only; no code, assets, or branding reused).

## 1. Vehicle types
- Car
- Go-kart
- Motorcycle (enables lean-angle features)
- Bicycle

Each vehicle profile is selectable per session; features adapt to the type
(e.g. lean angle only for 2-wheel vehicles).

## 2. Where it is used
- **Primary:** real race circuits (track database with predefined start/finish and sectors).
- **Also:** practice on public roads / around the neighborhood (app testing), and small
  go-kart tracks.
- **User-defined tracks:** user can set their own start/finish line (and sectors) on a map,
  or by "drop a line here" while standing/driving at the spot.
- Safety notice shown at first launch (track use only, obey the law).

## 3. Monetization
- **v1:** completely free — no ads, no subscription, all features unlocked.
- **Future-ready:** architecture keeps a single entitlement gate and an ad-service seam so a
  membership tier and/or ads can be added later without restructuring.

## 4. GPS source (user-selectable)
- Built-in phone GPS (~1 Hz typical).
- External 10 Hz GPS receiver over Bluetooth (e.g. NMEA over Bluetooth Classic SPP or BLE).
- Bluetooth sensors (details TBD).
- Lap detection algorithm must interpolate the line crossing between GPS fixes so 1 Hz
  and 10 Hz sources both give accurate times.

### 4.1 External GPS device (v1 target)
- User's device: **Dragy Pro** (Bluetooth LE GNSS performance meter, high update rate).
- Its BLE data protocol is not publicly documented → must verify on the real device
  (inspect services/characteristics with nRF Connect, capture a log) before implementing.
- Implement behind a `GpsSource` interface: `PhoneGpsSource`, `DragyGpsSource`, and later
  a generic `NmeaBleGpsSource` for other 10 Hz receivers (RaceBox, XGPS160, …).

### 4.2 Bluetooth sensors — NOT in v1 (keep in mind)
- Future: OBD-II (RPM, speed), heart-rate monitor, IMU (lean angle, G-force).
- v1 design keeps a generic "sensor channel" in the session data model so new channels
  can be recorded later without a schema rewrite.

## 5. Platforms & data
- **Platforms:** Android and iOS (Flutter, single codebase).
- **Data:** offline / on-device only in v1 (local database). No accounts, no online
  rankings, no live timing. Repository layer designed so a sync backend can be added later.

## 6. Code quality requirements
- Feature-first layered architecture (View → ViewModel/Notifier → Repository → Service),
  strict one-way dependencies, single source of truth per data type.
- Hardware/platform access (GPS, Bluetooth, files) behind interfaces so logic is testable
  without a device (e.g. replay a recorded GPS log to test lap detection).
- Every public class/function has a doc comment explaining **what it does and why**;
  in-body comments explain non-obvious logic (especially timing math).
- Unit tests for the lap-timing core.

## 7. Language
- English only for v1.
- All UI text externalized (Flutter gen-l10n) so Thai and others can be added later
  without touching screen code.

## 8. Additional features

### 8.1 Brake Point Coach
**Availability**
- Car, go-kart, motorcycle only. **Permanently unavailable for bicycle** (lap timing only).
  No developer override.

**Detection**
- Brake onset detected from deceleration (g), not a fixed km/h drop, so it works at any
  GPS rate: e.g. decel > threshold (default ~0.3 g, per vehicle type) sustained ≥ 0.3 s,
  then backtrack to the sample where speed first started falling.
- Positions stored as distance-along-lap from the start line; brake events from different
  laps within a matching window (~40 m) are clustered into the same "corner" automatically.
- Phone GPS: feature works but is flagged "approximate"; best with 10 Hz external GPS.
- Detection strategy is pluggable so a real brake signal (OBD/IMU) can replace it later.

**Learning**
- Configurable number of learning laps (default 3). Out-lap and incomplete laps excluded.
  User can invalidate laps and manually pick the reference lap.
- **Method 1:** brake points taken from the fastest learning lap.
- **Method 2 (conditional deepest):** a later brake point from any lap replaces the reference
  for that corner only if, versus the reference: corner segment time is not slower, minimum
  corner speed and exit speed are not lower, and entry speed is similar. Glitch filtering
  applied. Points can move earlier again (no one-way ratchet).

**Alerts (in-session)**
- Two stages: **yellow = approaching**, **red = brake now**.
- Red is shown ahead of the stored point by a lead time (default ~0.7 s, converted to
  distance from current speed) to cover reaction time + GPS latency.
- Red stays until braking is detected (fallback timeout configurable).
- No audio in v1.

**Per-corner adjustment**
- Alert point = learned brake point + per-corner user offset (± metres) + global lead time.
- Post-session "Corners" screen: list + map; ± 5 m buttons or drag on map; per-corner
  lock (learning will not move it); reset to learned.
- Auto calibration suggestion: compare actual brake onset with the red alert per corner;
  if consistently off (e.g. ≥ 3 of last laps by > 8 m), suggest an offset — user accepts
  with one tap. Never applied silently.
- No adjustments while driving.

**Saving — named Brake Profiles**
- Corner adjustments + locks are saved as a **named profile**, e.g.
  "Bira – Civic – Dry – v2", tied to track × vehicle.
- Multiple profiles per track/vehicle allowed (dry/wet, different tyres, …);
  rename, duplicate, delete; one can be marked default.
- Starting a new session on that track/vehicle: choose a saved profile (default
  preselected) → learning laps skipped → alerts active from the first flying lap.
- Locked corners never change automatically; unlocked corners may still be refined by
  learning, but changes are only written to the profile when the user saves.

**Post-session feedback**
- Per corner: "braked N m earlier/later than reference"; map of brake points for all laps;
  speed-vs-distance chart of a lap vs best lap.

### 8.2 Pit Lane Mode (speed limit + minimum pit time)
**Setup (per track)**
- Pit Entry and Pit Exit are short **gate lines** (like the start/finish line), not single
  points, with a direction of travel — so driving past on the main straight (often only
  10–20 m away) never triggers pit mode.
- Capture by standing at the spot and tapping "Set Pit Entry/Exit here": GPS is averaged
  over ~10 s for accuracy (accuracy shown; external GPS preferred). Gate orientation
  taken from the pit lane path on the first drive-through, or adjusted on the map.
- Can also be placed/adjusted directly on the satellite map.

**Race Rule Sets** — rules belong to a named *race / championship*, not to the track.
The user picks the rule set when starting a session (track + vehicle + rule set + drivers).
Editable fields:
- Pit speed limit (default 60 km/h) and target speed (default 55 km/h).
- Minimum pit time Entry→Exit (default 1:00) + optional safety margin.
- Hold result after exit (default 10 s).
- Required pit stops (default 1). Shown on the normal screen as a **small** indicator
  ("Pit 0/1"), never a large element.
- Future (not v1): pit window rules (no pit in first/last X minutes) with countdown.

**In pit mode** (auto on crossing Pit Entry)
- Screen switches to: **current speed in very large digits** (green ≤ target, yellow
  between target and limit, red > limit) and a **pit timer** at the bottom counting from
  the Entry crossing (includes the stop).
- Timer shows time remaining to the minimum; turns green once the minimum is reached.
- (Proposed) Projected time at Pit Exit from current speed & remaining distance:
  "SLOW DOWN" / "OK".
- On crossing Pit Exit: final pit time frozen on screen for the hold time, then normal
  screen returns. Stop logged with entry/exit times, total time, max speed.
- Fallback if exit is missed (GPS gap): auto-close on returning to track / start line.
- Brake coach alerts suppressed in pit mode; pit laps excluded from best-lap and
  brake-learning statistics.

**Drivers & stints**
- Session has an ordered **driver roster** (1..n names), entered at session start.
- Data (laps, pit stops, brake stats) is attributed to the current driver's **stint**.
- At each pit stop the stint advances to the next driver in the roster
  (solo: same driver, stint number increments → "Nong(1)", "Nong(2)", …).
- While stopped in pit mode (speed < ~3 km/h, GPS noise tolerance), the big speed digits
  are replaced by the **next driver's name + stint**, e.g. "Nong(2)"; pit timer keeps
  running at the bottom. Speed display returns once speed > the **resume-speed threshold
  (default 20 km/h, configurable)**.
- While stopped, a **large "Same driver" button** is shown: tapping it keeps the current
  driver (stint number still increments). If not tapped, the next driver in the roster
  takes over.
- Stint boundaries and driver assignment can be corrected after the session.
- Results viewable per driver and per stint.

**End of race in pit**
- Pit-mode screen has an **"End session"** button (long-press to avoid accidental taps)
  that closes pit mode and the session together.

### 8.3 Sectors (v1, Phase 1)
- Sector lines are short directional gates (same crossing logic as start/finish).
- **Sector layouts** are named and saved per track, e.g. "Buriram (3 Sectors)",
  "Buriram (5 Sectors)"; duplicate a layout and add/move lines; one default per track.
  2–10 sectors. Layout chosen at session start; old sessions can be re-computed with a
  different layout from the stored raw GPS.
- No built-in official sector coordinates: user places lines on the satellite map or by
  standing at the spot (optionally from an organiser's track map).
- Live display (landscape): running lap time; one box per sector — running time in the
  current sector, completed sectors keep their time + delta (green = faster, red = slower);
  boxes reset at the start/finish line. At lap end: lap time + delta vs best lap, held briefly.
- Delta reference: user toggle — **Best lap** (best lap's sectors; default) or
  **Best sector** (best individual sector of any lap). Predicted lap time shown.
- ≥ 7 sectors: compact boxes + enlarged last completed sector.
- **No laps table on the live screen** (too small to read while driving) — the space is
  given to large sector boxes. Laps table with best per column highlighted lives in the
  session summary. Optimal lap = sum of best sectors.
- Warning when sector lines are too close together (short sectors amplify GPS error).

### 8.4 Testing approach
1. Automated unit tests on synthetic GPS tracks with known brake points.
2. Built-in **Replay / Simulator mode** (dev builds): replay a recorded or synthetic GPS
   log through the real pipeline in real time — alerts visible at a desk.
3. Low-speed real tests in an empty lot / quiet area (car or kart with a
   separate driver and a passenger watching the screen).
4. Accuracy benchmark against official transponder timing at a kart track and against the
   Dragy's own app.
5. Every session records raw GPS so any problem can be replayed afterwards.

## Open questions
- Dragy Pro BLE protocol: confirm on the physical device.

## 9. v1 Delivery Plan (phases)
| Phase | Scope | Testable result |
|---|---|---|
| 0 Foundations | Flutter project, architecture skeleton, theme, l10n (EN), local DB, `GpsSource` interface + phone GPS, raw GPS recording, Replay/Simulator mode | App runs on Android & iOS; can record and replay a GPS log |
| 1 Core lap timer + sectors | Vehicles, custom tracks (start/finish by standing or on map), lap detection with crossing interpolation, named sector layouts, live timing screen with sector deltas, session history | Real lap times on a test loop / kart track |
| 1b Dragy probe (parallel) | Inspect Dragy Pro BLE data with nRF Connect, capture samples | Go / no-go on Dragy integration |
| 2 Pit Lane Mode | Pit entry/exit gates, race rule sets, pit speed + timer screens, exit result hold, drivers & stints, Same driver, End session | Full pit workflow in Replay and on track |
| 3 Brake Point Coach | Brake detection, learning laps, Method 1 + conditional Method 2, yellow/red alerts, Corners screen, named profiles, calibration suggestions | Coach working in Replay, then on track |
| 4 External GPS | Dragy Pro source (if protocol readable), GPS source picker | 25 Hz data driving the whole app |
| 5 Polish & release prep | Session summary & charts, CSV/GPX export, design/QA pass, store builds | Release candidate |
