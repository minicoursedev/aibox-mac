# AIBox Mac

**English** | [繁體中文](README.zh-TW.md)

The Mac component of AIBox: Bluetooth light notifications for Codex, with shake gestures to open conversations.

## Intended workflow

An AI response/turn ends → the Mac tells the BLE device to flash → the user shakes the device → the Mac brings Codex to the foreground and opens the corresponding conversation.

“Completion” means the current response/turn has ended. AIBox does not determine whether the entire task or request is complete.

## Get the source

```sh
git clone --recurse-submodules https://github.com/minicoursedev/aibox-mac.git
cd aibox-mac
```

For an existing checkout, run `git submodule update --init --recursive` first. `Sources/AIBoxCore/Remote` references the shared [aibox-remote](https://github.com/minicoursedev/aibox-remote) repository; SSH connection management remains in the Mac app.

## Run

The app uses Swift Package Manager and AppKit. It requires macOS 13 or later and Xcode/Swift development tools. Open `Package.swift` in Xcode to browse the project.

Run from this repository:

```sh
zsh scripts/build-app.sh
open build/AIBox.app
```

The app lives in the macOS menu bar as a box icon. Open it to see the latest 20 notifications; clicking one opens its Codex conversation through `codex://threads/<thread-id>`. Settings are organized into Sensors, Lights, Notifications, Device, and Codex tabs, initially showing Sensors. Device shows the actual BLE status and offers reconnection, device replacement, and unpairing.

## BLE and shake gestures

The microphone sensitivity slider ranges from 0 to 100: moving left requires a louder transient sound, while moving right increases sensitivity. The default of 50 preserves the original threshold; if it is too sensitive, try 20 and adjust for your environment. This is neither a volume percentage nor a decibel value. Zero is the lowest sensitivity; turn off sound detection to disable it. Settings are saved automatically, applied immediately, and reapplied on reconnect. The device firmware must support `M <sensitivity>`. See the [microphone sensitivity validation record](https://github.com/minicoursedev/aibox-spec/blob/main/mac-app/收音敏感度_驗證紀錄.md).

A white slider thumb overlays the sound meter on a shared 0–100 display scale. The fill shows the device's current input, with the setting and current level displayed on either side. The fill turns orange immediately when the level is at or above the thumb and green below it. Both dragging and incoming readings trigger a comparison; there is no color hold period or wait for a clap event.

The sound level updates every 0.1 seconds using the maximum peak in that interval. The display maps −90–0 dBFS to a relative 0–100 scale, not ambient decibels or a linear amplitude percentage. Streaming starts while the Sensors tab is visible and stops when switching tabs or closing Settings. Disconnecting or receiving no data for two seconds clears the old reading; disabling sound detection shows it as off. The color comparison helps adjust the slider; the device's notification trigger logic is unchanged.

Shake detection and sound detection independently enable notification actions from shaking and transient sounds such as claps. Both are enabled by default. Settings are sent immediately to a connected device and await acknowledgment; offline changes are saved and applied on reconnect. Notifications remain clickable when both are disabled. The normal shake switch does not disable the two-second startup shake used to reset pairing. This requires firmware supporting `S <motion><sound>`; the app prompts for an update if older firmware rejects the command.

On first launch, the Select AIBox window lists nearby devices. Choose one and click Identify this device. The device randomly flashes red, green, or blue, using its own random generator without sending the answer to the Mac. Select the physical color in the interface. Only after the device verifies the answer and stores the authorized key does the Mac save its identifier. The interface does not reveal the answer. An incorrect choice does not save or replace the selected device; identify it again or choose another.

Subsequent launches and reconnections search only for the remembered device, never another AIBox with the same name. The menu bar icon stays red until a device is selected, color verification is complete, and the connection is established. Use Select/replace box in Settings to choose again; canceling retains the previous selection. Pairing controls are in Settings rather than duplicated in the main menu. Notifications received during pairing are retained, identification lights take priority, and shaking does not open conversations. Successful verification synchronizes the latest notification lights and user settings.

When a paired device powers off, the Mac keeps searching beyond 30 seconds and reconnects when it returns. Connection, handshake, or transfer errors/timeouts clean up the old connection and retry the search after three seconds. The initial color-pairing search still stops after 30 seconds. Conditions requiring user action—unpairing, invalid pairing keys, or incompatible firmware/services—do not retry automatically.

CoreBluetooth and v5 firmware establish LE Secure Connections Just Works encryption and bonding before color verification. Normal restarts reuse existing keys without repeating color selection. Only keys that passed color verification may perform normal device control; matching a name or address does not authorize another key. Lost keys require pairing again. Allow the macOS system pairing prompt if it appears.

To pair with another host, choose Unpair box on the original Mac. After the device acknowledges clearing its pairing, the Mac forgets it and stops reconnecting. Alternatively, shake the device continuously for **two seconds during startup** to clear the old bond, disconnect, and restore the RGB cycling used for new-host color pairing. This startup gesture remains effective even if the old host has already reconnected; there is no need to shut down the original Mac first.

The first two seconds after IMU sampling begins provide a window to start the gesture. A gesture already in progress may continue beyond that window until two seconds accumulate. More than 300 ms without a motion peak resets the timer, allowing the low points of back-and-forth motion. Reset detection closes for that boot only after the initial window has elapsed, the host is connected, and no gesture is in progress. Later shakes then operate notifications normally. Reset remains available while the host connection is incomplete. BLE connection proceeds without being delayed for the gesture.

Just Works does not authenticate against a man-in-the-middle during initial pairing. Selecting one of three light colors confirms a physical device, but colors may coincide or be guessed; it is not equivalent to a six-digit authentication code. macOS manages BLE system keys. Unpairing in the app does not remove the device from the system Bluetooth list. If stale system keys prevent pairing, forget AIBox in system settings and retry. Upgrade both the Mac app and firmware to v5 together.

After a shake reset, reconnecting to the original Mac may produce a reset notification or a macOS error indicating that the device removed pairing information. The app explains how to clear the old pairing and offers Open Bluetooth Settings. Forget AIBox there, then return to the app, search again, identify the device, and confirm its color. Dismissing the prompt does not immediately retry the old pairing. Ordinary connection timeouts are not treated as a reason to forget the device.

The alternation interval controls how long each color is shown: 0.1–10 seconds in 0.1-second steps, defaulting to one second. Response-stop and approval-request lights share the interval; idle remains steady. The setting is saved automatically and synchronized on reconnect.

Default lights are steady blue when idle, alternating yellow/white for a response ending, and alternating red/white for an approval request, with each color lasting one second. Click a color swatch in Light Colors to customize one idle color and two colors each for response-stop and approval notifications. Colors are saved and synchronized on reconnect. Each shake event opens the **newest unopened notification**. Clicking a notification also marks it opened, so subsequent shakes skip it. A macOS failure to open a conversation does not consume the notification. After opening one, lights advance to the next notification or return to idle when all are opened. Shaking does nothing when none remain unopened.

The display, memory, and persistent notification history keep only the latest 20 entries in arrival order. Exceeding the limit removes the oldest entry and its opened state, including older unopened notifications. Continuous shaking may produce multiple events; each opens at most one notification. This is not recognition of a complete physical gesture.

See the [BLE protocol specification](https://github.com/minicoursedev/aibox-spec/blob/main/spec/aibox-box/BLE_通訊規格.md) for responsibilities, commands, initial parameters, and disconnect behavior.

## Receiving notifications

The build includes `AIBox.app/Contents/MacOS/aibox-notify`. Start the app first. The main entry point, `aibox-notify --hook`, reads official `Stop` and `PermissionRequest` JSON from stdin and preserves `session_id` and `turn_id`. Stop reads `last_assistant_message`; PermissionRequest reads `tool_name` and the optional `tool_input.description`. It also accepts `PreToolUse` for `request_user_input` and `request_user_input_async`, displaying `question`/`title` from `tool_input.questions` as an “Awaiting answer” notification. Other tools are ignored.

A `Stop` adds a notification and triggers lights only when `transcript_path` is a nonempty string. Missing, `null`, or empty values are acknowledged successfully without replacing existing notifications. `PermissionRequest` follows the approval-reminder setting independently of `transcript_path`.

Question reminders are enabled by default and saved independently as `aibox.acceptUserInputRequests`. Disabling them immediately stops new question notifications and their lights while preserving existing entries and raw payload records. The setting survives restarts. Question reminders use approval-request light colors; shaking or clicking only opens the conversation and never answers for the user. These reminders occur before a question tool starts, rather than tracking an ongoing waiting state. Codex may continue working during asynchronous questions, and answering does not automatically clear the reminder. Ordinary text questions and elicitation inside MCP tools are not covered.

Approval notifications show “Approval request · tool name · reason.” Clicking only opens the conversation; it neither approves nor rejects the request. The event occurs while preparing to request approval and does not establish an ongoing wait for human action. Only the newest notification per conversation is retained: a new approval request or Stop replaces that conversation's earlier notification within the shared 20-entry limit.

A successfully received Hook outputs only `{}`, with no permission decision, stop decision, or instruction to continue. `Stop` means the turn has entered stop handling; another hook may still request continuation. AIBox does not present it as completion of the entire task.

Debug data is saved to `~/Library/Application Support/AIBox/notification-payloads.json`. It retains the latest 20 arrivals, oldest to newest, across app restarts. Consecutive events from the same conversation are recorded separately, unlike the menu's per-conversation merging. Each entry contains `receivedAt` and the original UTF-8 `payload` string, preserving unparsed fields, full tool input, and whitespace. Reading the JSON restores the original payload. Only the current user can read and write the file. The helper forwards only supported, valid events. The app saves them before applying Stop filtering and notification settings, so filtered Stops and approval requests received while reminders are disabled retain their full payloads. Save failures report an error rather than successful receipt. Full payloads cannot be recovered retroactively for events received before this feature was added.

The legacy notify argument format remains available for compatibility and manual testing. AIBox does not automatically point Codex's notify setting to it.

Simulate a notification with:

```sh
build/AIBox.app/Contents/MacOS/aibox-notify '{"type":"agent-turn-complete","thread-id":"example-thread","turn-id":"example-turn","last-assistant-message":"Simulated notification: reception test"}'
```

The helper sends data to the app through a local Unix socket owned by the same user and succeeds only after the app acknowledges receipt. Legacy argument mode reports `accepted: true`; Hook mode outputs `{}`. This acknowledgment concerns app receipt, not delivery to the BLE device; the filters above may suppress adding an entry.

The notification list is saved in app preferences under `aibox.completionHistory`, updated whenever a notification arrives or is marked opened. It stores the content, conversation and turn IDs, arrival time, and opened state. Only the latest entry per conversation is retained, with both display and storage limited to 20 entries. On restart, the list is restored and lights follow the newest unopened notification, or idle if all are opened. Persistence applies from the version that introduced it: events are not replayed from debug payloads, and previously cleared notifications or opened states are not restored automatically.

## Configure Codex

Click the AIBox menu bar icon → Settings (`設定…`) → Configure Codex (`設定 Codex`). UI labels quoted in English here describe their meaning; they do not imply that the app interface is localized.

- Opening the window only reads settings and displays the user configuration path and current status.
- The setup button adds missing user-level `hooks.Stop`, `hooks.PermissionRequest`, and question-tool-specific `hooks.PreToolUse` handlers. Existing `notify`, other hooks, and trust state are preserved. SkyComputerUseClient is not modified.
- The full Hook command, event, and input data are then shown for the user to choose Trust and enable. Canceling leaves newly added Hooks untrusted/disabled rather than granting trust automatically.
- Trust is recorded only for AIBox Hooks the user confirms. Changes to the definition or configuration version require confirmation again. An identical existing command is not added twice.
- Setup and trust status are shown separately for response-stop, approval, and question reminders. “Configured” does not mean a real notification has arrived. Canceling trust review for a new Hook does not disable an existing Hook.

For the original development build location, the configuration is equivalent to the following. Your installation uses the actual path to your app:

```toml
[[hooks.Stop]]
[[hooks.Stop.hooks]]
type = "command"
command = "'/Users/lman/projects/aibox/aibox-mac/build/AIBox.app/Contents/MacOS/aibox-notify' --hook"

[[hooks.PermissionRequest]]
[[hooks.PermissionRequest.hooks]]
type = "command"
command = "'/Users/lman/projects/aibox/aibox-mac/build/AIBox.app/Contents/MacOS/aibox-notify' --hook"

[[hooks.PreToolUse]]
matcher = "^(request_user_input|request_user_input_async)$"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "'/Users/lman/projects/aibox/aibox-mac/build/AIBox.app/Contents/MacOS/aibox-notify' --hook"
```

Configuration requires the Codex desktop app providing the `codex` app-server. AIBox locates it through the application registered for `codex://`. No API key is required, and Codex is not restarted automatically. Open a new conversation after configuration. If the running Codex instance has not loaded the settings, restart it manually and test a new response. Keep AIBox running; click a recent notification to open its conversation.

Keep the app at a stable location. Moving it does not automatically remove old commands in this version. Remove or disable them in Codex's Hooks review interface, then configure the new path.

See [Hooks and notification clicks](https://github.com/minicoursedev/aibox-spec/blob/main/spec/aibox-mac/hooks_對話通知.md) for the current integration. The [notify invocation notes](https://github.com/minicoursedev/aibox-spec/blob/main/spec/aibox-mac/openai_notify_呼叫方式.md) document the official interface and historical implementation, not the current setup button's approach.

## Remote SSH notifications

In Settings → Remote (`遠端`), enter a host alias already present in your SSH configuration, such as `srv`, and choose Save and connect. This version manages one host, reuses SSH keys and known_hosts, rejects password prompts, and does not automatically trust unknown hosts. Complete key and host verification through a normal SSH login first.

The app creates a private `~/.codex/aibox` directory on the remote host and installs `notify.py`. SSH `-R` forwards its `notify.sock` to `/tmp/aibox-mac-<uid>/notify.sock` on the Mac. The remote host needs Python 3.8 or later and OpenSSH with Unix socket forwarding support. There is no public TCP listener, no transfer of the Mac's private key, and no SSH agent forwarding.

Initially, configure and trust the following command in **remote Codex** for `Stop`, `PermissionRequest`, and `PreToolUse` with matcher `^(request_user_input|request_user_input_async)$`. The app does not automatically rewrite remote Hook configuration or trust records.

```sh
python3 ~/.codex/aibox/notify.py
```

If the remote version uses the same `config.toml` Hook format as the local version, merge these entries into the existing configuration without duplicate registration. For other versions, use their Hook management flow to configure the same events and command:

```toml
[[hooks.Stop]]
[[hooks.Stop.hooks]]
type = "command"
command = "python3 ~/.codex/aibox/notify.py"

[[hooks.PermissionRequest]]
[[hooks.PermissionRequest.hooks]]
type = "command"
command = "python3 ~/.codex/aibox/notify.py"

[[hooks.PreToolUse]]
matcher = "^(request_user_input|request_user_input_async)$"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "python3 ~/.codex/aibox/notify.py"
```

After trusting and enabling the Hooks, open a new remote conversation. Original events flow through the app's existing notification handling, logging, and lights. Notifications still use `session_id` to open `codex://threads/...`. Opening remote conversation links correctly must be verified with the installed Codex version.

Disconnected connections retry after 2, 4, 8… seconds, capped at 30 seconds. Manual disconnect stops retries and disables automatic connection on the next launch; quitting the app closes the tunnel. Individual notifications give up after at most four seconds and output `{}`, without approving for the user or asking Codex to continue. Offline events are not replayed. An existing AIBox tunnel for the same remote account is not taken over; only stale sockets owned by that user are cleaned up.

“Connected” means only that the tunnel is established, not that remote Hooks are configured or physical lights have been verified.

## Tests

```sh
swift test
python3 Sources/AIBoxCore/Remote/tests/test_notify.py
```

Tests cover official hyphenated fields, multiline Chinese content, unrelated events, missing data, and ordering/counting of the latest 20 entries.

There are also clickable menu action tests and integration tests requiring an explicitly selected local Codex executable:

```sh
AIBOX_TEST_CODEX_EXECUTABLE=/Applications/ChatGPT.app/Contents/Resources/codex swift test
```

Integration tests use a temporary `CODEX_HOME` without writing to the active Codex configuration. Coverage includes response-stop and approval Hooks, configuration upgrades, preservation of notify/other Hooks/comments/trust, path quoting, states before and after trust, repeated setup, version conflicts, and invalid configuration files. Tests requiring the local Codex executable are skipped when the environment variable is unset.

The device repository is the sibling `aibox-firmware` directory in the complete workspace.

## Validation history

The following records describe the 2026-09-04 validation session, not a fresh verification of the current version.

PermissionRequest handling, BLE integration, and three light modes were implemented on 2026-09-04, with 42 tests passing, none skipped, and no failures. Configuration integration tests used official Codex RPC in an isolated directory; menu action tests used a substitute opener.

The build was installed at the fixed `build/AIBox.app` location and restarted with the user's agreement, clearing old records. A synthetic Stop → helper → AIBox → BLE lights → physical shake was exercised. The user confirmed that Codex came to the foreground and opened the correct conversation.

At that check, the active configuration still contained only Stop; PermissionRequest still required setup and trust review by the user. Existing notify settings were unchanged, and Codex was not restarted. The complete real Stop/PermissionRequest-to-device workflow was not verified in that session.

See the [light validation record](https://github.com/minicoursedev/aibox-spec/blob/main/mac-app/燈號_驗證紀錄.md), [Mac app implementation specification](https://github.com/minicoursedev/aibox-spec/blob/main/mac-app/README.md), [BLE v1 integration validation](https://github.com/minicoursedev/aibox-spec/blob/main/mac-app/BLE_串接驗證.md), and [earlier execution record](https://github.com/minicoursedev/aibox-spec/blob/main/spec/aibox-mac/執行與驗證紀錄.md). Detailed specification and validation documents are currently in Traditional Chinese.
