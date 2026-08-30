# AxeHub API v1

REST API exposed by the NerdMiner firmware when the build includes
`AXEHUB_API_ENABLED=1`. The server listens on port **80** and serves the
AxeHub routes beneath `/api/axehub/v1`.

This API is meant for low-overhead board control and telemetry. It keeps the
main mining loop active while allowing safe inspection and configuration from a
local network client.

## Authentication / handshake

Every request MUST include the compat header. Requests without it return **404**.

```
X-AxeHub-Compat: 1
```

`POST` endpoints that accept a JSON body MUST also set
`Content-Type: application/json`.

Base URL: `http://<device-ip>/api/axehub/v1`

Example:
```bash
curl -H "X-AxeHub-Compat: 1" http://192.168.2.18/api/axehub/v1/ping
```

Standard success response shape:

```json
{"status":"ok"}
```

Standard error response shape:

```json
{"status":"error","msg":"<reason>"}
```

HTTP codes used: `200` OK, `400` bad request, `404` missing/invalid header,
`501` feature not supported, `503` feature unavailable.

---

## Endpoints

### `GET /ping`

Liveness and compatibility check. Returns a simple JSON object confirming the
server is alive and the AxeHub API version is active.

Example:
```bash
curl -H "X-AxeHub-Compat: 1" http://DEV/api/axehub/v1/ping
```

Example response:
```json
{"ok":true,"axehub_compat":"v1","firmware":"NerdMiner V1.8.7"}
```

### `GET /info`

Full telemetry snapshot. Returns a compact JSON with firmware, device,
network/pool, hashing, display, and system details needed for local monitoring.

Top-level keys include:
- `firmware` — name, version, axehub_compat, features, sw_worker_path
- `device` — mac, hostname, board, chip
- `hashing` — current_khs, average_1m_khs, average_5m_khs, hw_khs, sw_khs,
  shares_accepted, shares_rejected, reject_reasons, best_diff,
  best_session_diff, valid_blocks
- `pool` — `primary` + `fallback` (url, port, user, active, last_ping_ms, difficulty)
- `hardware` — temp_board_c, heap_free_bytes, uptime_s, wifi_rssi_dbm,
  cpu_freq_mhz, last_reset_reason
- `display` — tft_present, current_mode, available_modes, brightness,
  brightness_persisted, sleep_window, invert_colors

Example:
```bash
curl -H "X-AxeHub-Compat: 1" http://DEV/api/axehub/v1/info | jq
```

This endpoint is used for remote health checks, crash triage, and verifying that
board state stays stable while the miner remains active.

### `POST /pool/set`

Change primary pool. Immediately reconnects stratum.

Body:
```json
{"url":"pool.example.com","port":3333,"user":"bc1qxxx","pass":"x"}
```

All of `url`, `port`, `user` are required; `pass` optional (defaults to "x").

### `POST /pool/set_fallback`

Set or clear the fallback pool. Empty object `{}` clears it.

Body (set): same shape as `/pool/set`.
Body (clear): `{}`.

### `POST /pool/stats_api`

Override the URL used to fetch pool worker/difficulty stats for the bottom
section of the display. The wallet address is appended to the URL.

Body: `{"url":"http://lan.pool/api/client/"}` or `{}` to clear.

When cleared, the firmware auto-detects from known pools (public-pool.io,
pool.nerdminers.org, pool.sethforprivacy.com, pool.solomining.de, :2018 local).
For unknown pools it falls back to local on-device statistics.

### `POST /system/restart`

Reboots the device after ~800 ms. Returns `200 ok` before rebooting.

### `POST /system/reset_stats`

Wipes mining statistics in NVS (uptime, total Mhashes, shares accepted,
session best diff, etc.) and reboots after ~800 ms. Returns `200 ok` before
rebooting. Use to start a clean baseline measurement run.

No body.

### `POST /wifi/reset`

Clears the WiFi credentials and reboots into the setup AP (`NerdMinerAP`).

### `POST /webhook/set`

Configure outbound webhook target for event notifications.

Body:
```json
{"url":"https://hook.example.com/nerdminer",
 "share_above_diff":0.0}
```

Events pushed: `boot`, `pool_connect`, `pool_disconnect`, `share_accepted`,
`share_above_diff` (if threshold > 0). Empty `url` disables webhooks.

### `GET /display`

Returns current display state. The values vary by board model, but the response
always includes the current mode and the display size / brightness info.

```json
{
  "mode": 0,
  "num_modes": 4,
  "width": 240,
  "height": 135,
  "brightness": 259,
  "brightness_persisted": 80,
  "sleep_window": "disabled"
}
```

The field `brightness` is the live PWM value, while `brightness_persisted` is
what the board last saved to NVS.

When a sleep window is set, `sleep_window` is replaced with:
```json
{"sleep_start":"22:00","sleep_end":"06:00","sleep_in_window":false}
```

### `POST /display/mode`

Change current cyclic display screen.

Body (absolute):
```json
{"mode": 1}
```

Body (relative):
```json
{"action": "next"}    // or "prev", "backlight_toggle"
```

Returns `{"status":"ok","mode":<new_mode>}`.

### `POST /display/brightness`

Set TFT backlight state.

On the LilyGo T-Display V1, the backlight is a simple GPIO toggle: `0` turns it
off and any non-zero value turns it on. There is no true PWM dimming on this
board. For other boards that support PWM, `0–255` still applies normally.

Body:
```json
{"value": 255, "persist": true}
```

`value`: 0–255 (immediate effect; on V1, `0` = off, `>0` = on). `persist`
(optional, default false) — saves to NVS so it survives reboot.

Returns `{"status":"ok","value":255,"persisted":true}`.

### `POST /display/invert`

Toggle TFT colour inversion at runtime — fixes the white-background look
on opposite-polarity CYD 2.8/2.4 panels (some sellers/batches ship the
TFT with reversed default polarity even though the model name is the
same).

Body:
```json
{"on": true}
```

Returns `{"status":"ok","invert_colors":true}`. Persisted to NVS, applied
to the live framebuffer immediately (no reboot needed). Current state is
also exposed as `display.invert_colors` in the `GET /info` payload.

### `POST /display/sleep_window`

Turn the backlight off during a time-of-day window. Supports wrap-around
(e.g. 22:00–06:00). Uses NTP-derived time.

Body (set): `{"start":"22:00","end":"06:00"}`
Body (clear): `{}`

Time format: `"HH:MM"` (24-hour). `start == end` rejected.

The firmware polls every 5 s and transitions backlight on/off when crossing
the window boundary. `sleep_in_window` in `/display` reflects current state.

### `POST /buzzer/test`

Plays a 3-note confirmation melody on the buzzer output (CYD: GPIO26).

No body.

### `POST /buzzer/tone`

Play a single tone.

Body:
```json
{"freq": 440, "duration_ms": 300}
```

Range: `freq` 30–20000 Hz, `duration_ms` 1–10000 ms. Tone plays asynchronously
(response returns immediately).

### `GET /coin`

Current coin/chain configuration for network-data polling.

```json
{
  "ticker": "BTC",
  "height_url": "",
  "difficulty_url": "",
  "price_url": "",
  "global_hash_url": "",
  "pool_stats_url": ""
}
```

### `POST /coin`

Set the network-data ticker. Bitcoin is the only supported chain for the current
firmware builds.

Body:
```json
{"ticker": "BTC"}
```

Supported ticker:

| ticker | defaults |
|---|---|
| `BTC`    | mempool.space + coingecko `bitcoin` |

Changing ticker forces a fresh fetch of price/height/hashrate. The board clears
stale values so the next screen refresh reflects the active network configuration
without leaving old remote data on the display.

### Operational notes

- V1 boards are shipped with the external market / global network fetches muted to
  avoid the heap-pressure reboot loop seen during display redraw + background HTTP
  fetch overlap.
- The `/info` telemetry endpoint is safe to poll on the V1 target and is the
  recommended health/diagnostic endpoint for local monitoring.
- The compat header is enforced globally; all request examples above must include
  `X-AxeHub-Compat: 1`.


---

## Example client (Python)

```python
import requests

BASE = "http://<device-ip>/api/axehub/v1"
H = {"X-AxeHub-Compat": "1", "Content-Type": "application/json"}

# basics
requests.get(f"{BASE}/ping", headers=H).json()
info = requests.get(f"{BASE}/info", headers=H).json()

# confirm the Bitcoin network-data source
requests.post(f"{BASE}/coin", headers=H, json={"ticker": "BTC"}).json()

# set pool
requests.post(f"{BASE}/pool/set", headers=H,
    json={"url": "pool.local", "port": 3333, "user": "bc1qxxx", "pass": "x"})

# dim display + schedule night sleep
requests.post(f"{BASE}/display/brightness", headers=H,
    json={"value": 80, "persist": True})
requests.post(f"{BASE}/display/sleep_window", headers=H,
    json={"start": "22:00", "end": "06:00"})

# fix opposite-polarity TFT panel (white background instead of dark)
requests.post(f"{BASE}/display/invert", headers=H, json={"on": True})

# play a tone
requests.post(f"{BASE}/buzzer/tone", headers=H,
    json={"freq": 1000, "duration_ms": 200})
```

---

## Example client (JavaScript)

```javascript
const BASE = "http://<device-ip>/api/axehub/v1";
const H = {"X-AxeHub-Compat": "1", "Content-Type": "application/json"};

const get  = (p)    => fetch(`${BASE}${p}`, {headers: H}).then(r => r.json());
const post = (p, b) => fetch(`${BASE}${p}`, {method:"POST", headers: H, body: JSON.stringify(b)}).then(r => r.json());

await get("/info");
await post("/coin", {ticker: "BTC"});
await post("/display/mode", {action: "next"});
```
