# Command Tracking & Assessment Pipeline

This document explains how CyberRangeCZ collects trainee command activity, what
the **Assessment**, **Command Timeline**, and **Command Analysis** tabs show,
and what conditions must all be met for them to work correctly.

---

## What Is Being Tracked?

CyberRangeCZ has a built-in audit pipeline that captures terminal commands typed
by trainees during an active sandbox run. The captured data feeds three
instructor-facing dashboards:

| Tab | What It Shows |
| ---- | ------------- |
| **Command Timeline** | Chronological log of every command typed during the session |
| **Command Analysis** | Whether captured commands match the `expected_commands` regex patterns defined in `training.json` |
| **Assessment** | Level-by-level completion status, score, and hint usage |

---

## How the Pipeline Works

```text
Trainee types command in Guacamole terminal
        │
        ▼
kypo-user-logger daemon (running inside Kali VM)
        │  captures keystrokes via Guacamole hooks
        ▼
CyberRangeCZ backend API
        │  matches against expected_commands regex patterns
        ▼
Command Timeline / Command Analysis / Assessment tabs (instructor view)
```

The key agent is the **`kypo-user-logger` daemon**, a service pre-installed
inside the Kali attacker VM that hooks into the Guacamole session and forwards
command logs to the backend in real time.

---

## Training Definition Configuration

To activate command tracking for a level, the following fields must be set in
`training.json` for each `TRAINING_LEVEL` object:

```json
{
  "commands_required": true,
  "expected_commands": [
    "nmap.*192\\.168\\.100\\..*",
    "ssh operator@192\\.168\\.20\\.20"
  ],
  "mitre_techniques": [
    { "id": "T1046", "name": "Network Service Discovery" },
    { "id": "T1021.004", "name": "Remote Services: SSH" }
  ]
}
```

- **`commands_required`** — Set to `true` to require command evidence for that
  level. Set to `false` for GUI-based levels (e.g. interacting inside Node-RED's
  browser interface).
- **`expected_commands`** — Array of Java-compatible regex strings matched
  against captured commands. Each pattern should be broad enough to catch
  realistic variations (e.g. different flags) while being specific enough to be
  meaningful.
- **`mitre_techniques`** — ATT&CK / ICS technique IDs displayed in the Command
  Analysis tab for pedagogical mapping.

### Current Configuration in Complex OT Sandbox

| Level | `commands_required` | Key Expected Commands | MITRE |
| ----- | ------------------- | -------------------- | ----- |
| 2 – SCADA Discovery | ✅ `true` | `nmap.*192.168.100.*` | T1046 |
| 3 – HMI Compromise | ❌ `false` | *(GUI-based, N/A)* | T1190 |
| 4 – Operator Secrets | ❌ `false` | *(GUI-based, N/A)* | T1552.001 |
| 5 – EWS Pivot | ✅ `true` | `nc -nlvp.*`, `ssh operator@…`, `nmap.*` | T1021.004, T1046 |
| 6 – Modbus Sabotage | ✅ `true` | `modbus.*192.168.20.10.*`, `cat.*/var/log/safety_override.*` | T0855, T0831 |

---

## Prerequisites Checklist

All five conditions must be met for the tabs to populate:

| # | Condition | Notes |
| - | --------- | ----- |
| 1 | `training.json` has `expected_commands` + `mitre_techniques` | ✅ Already configured |
| 2 | Training definition **re-imported** into the portal | Required after every `training.json` edit |
| 3 | A **new** sandbox run is started | Existing runs use the old definition snapshot |
| 4 | Trainee uses the **Guacamole web console** inside the portal | See limitations below |
| 5 | Logged in as a **trainee account** (not `crczp-admin`) | Admin accounts bypass the audit pipeline |

---

## Known Limitations

### ⚠️ Commands Must Be Typed in the Guacamole Console

The `kypo-user-logger` daemon only hooks into sessions established via the
**in-portal Guacamole terminal** (the "Open Console" button in the sandbox
view). It does **not** capture commands from:

- A local terminal SSHing directly into the Kali VM
- Vagrant SSH sessions (`vagrant ssh attacker-host`)
- Any terminal emulator running outside the portal

**Implication for screencasts / demos:** If you record a demo by SSHing directly
into the attacker VM from your laptop, the command timeline will be empty. You
must use the portal's console for any session you want tracked.

### ⚠️ Admin Account Is Not Audited

The built-in `crczp-admin` account is excluded from the trainee audit pipeline
by design. If you log into the portal as admin and run a sandbox, the Assessment
and Command tabs will remain empty regardless of what commands you type.

**Solution:** Create a dedicated trainee user in Keycloak and run the
demo/thesis evaluation with that account. See
[deploy-ot-scenario-portal.md](./deploy-ot-scenario-portal.md) for how to create
a trainee user.

### ⚠️ GUI-Based Levels Cannot Be Command-Tracked

Levels where the trainee interacts with a web-based interface (e.g. the Node-RED
flow editor) cannot produce shell command logs. The `kypo-user-logger` only
intercepts terminal keystrokes, not browser clicks or form inputs.

**Affected levels:** Level 3 (Node-RED RCE) and Level 4 (credential file read
via exec node). These levels are intentionally set to `commands_required: false`
and will not contribute to the Command Timeline.

### ⚠️ Definition Must Be Re-Imported After Every Change

The portal snapshots the training definition at import time. Editing
`training.json` on disk has no effect on any run until the definition is
explicitly re-uploaded through the portal UI.

**Workflow:**

1. Edit `training.json`
2. Portal → Training Definitions → select definition → Upload / Update
3. Start a new training run (old runs remain frozen on the old snapshot)

---

## Intended Use

The command tracking and assessment system is intended for **instructor
monitoring and pedagogical evaluation**, not real-time blocking. Specifically:

- **Instructors** can watch trainee progress in real time from the dashboard
  during a live exercise.
- **Post-session analysis** maps which commands were used to MITRE ATT&CK
  techniques, giving a structured record of the trainee's approach.
- **Scoring** is computed from level completion, hints used, and time taken —
  not from whether specific commands were matched.
- **Research data collection:** For thesis/research purposes, the command
  timeline provides an objective log of trainee behaviour that supplements
  self-reported questionnaires.

### What It Is NOT

- It is **not** a full EDR/SIEM solution. It only captures what is typed in the
  Guacamole console — it does not inspect network traffic, file writes, or
  process trees.
- It does **not block** trainees who skip expected commands. A trainee can
  answer the flag correctly without ever running `nmap`, and the system will
  still award full score — the command log simply won't show the "expected"
  pattern matched.

---

## Re-Import Procedure (Quick Reference)

4. In your browser, log in to the portal as `crczp-admin`.
5. Navigate to **Training Definitions** in the left sidebar.
6. Find the **Complex OT Sandbox** definition.
7. Click **Edit** → **Upload** and select
   `/opt/cyber-range/complex-ot-sandbox/training.json`.
8. Save/publish the new version.
9. Go to **Training Runs** and start a **new run** from the updated definition.
10. Share the access token/link with the trainee account.
