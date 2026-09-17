# CyberRangeCZ Scenario Schemas: Linear vs. Adaptive Training

This document analyzes the structural and functional differences between the
**Linear Training Schema** (used in `complex-ot-sandbox`) and the
**Adaptive Training Schema** (used in `library-junior-hacker-adaptive`).

---

## 1. High-Level Comparison

| Feature | Linear Training (`complex-ot-sandbox`) | Adaptive Training (`library-junior-hacker-adaptive`) |
| :--- | :--- | :--- |
| **Top-Level Array** | `levels` | `phases` |
| **Path Progression** | Sequential / Fixed (`order` 0 &rarr; 1 &rarr; 2) | Dynamic / Conditional (based on performance and answers) |
| **Task Count per Step** | Exactly **one task** per level | **Multiple tasks** of varying difficulty per phase |
| **Difficulty Scaling** | Static (same steps for all trainees) | Adaptive (hints and tasks scale based on skill level) |
| **Initial Assessment** | None (or simple text info) | Pre-game adaptive `QUESTIONNAIRE` (RFQ questions) |
| **Branching Logic** | Not supported | Supported via `phase_relations` and `decision_matrix` |

---

## 2. Structural JSON Diffs

### 2.1 Linear Level Schema (`levels`)
In a linear training scenario, the `levels` array contains sequential
dictionary objects representing independent steps. Each step corresponds to
a single, static task.

```json
{
  "levels": [
    {
      "title": "IDMZ: Access the Industrial DMZ Jump Host",
      "level_type": "TRAINING_LEVEL",
      "order": 2,
      "estimated_duration": 10,
      "answer": "FLAG{IDMZ_JUMP_ACCESSED}",
      "content": "### The Situation\n\nYour initial...",
      "solution": "1. Run a port scan...",
      "max_score": 100,
      "hints": [
        {
          "title": "DMZ Host Discovery",
          "content": "Use nmap...",
          "hint_penalty": 10,
          "order": 0
        }
      ],
      "incorrect_answer_limit": 10,
      "commands_required": true
    }
  ]
}
```

### 2.2 Adaptive Phase Schema (`phases`)
In an adaptive training scenario, the `phases` array represents high-level
game phases. A phase contains a nested array of **multiple tasks** (which act
as difficulty variants) and evaluation matrices.

```json
{
  "phases": [
    {
      "title": "Getting to know the environment",
      "phase_type": "TRAINING",
      "order": 3,
      "estimated_duration": 3,
      "allowed_commands": 10,
      "allowed_wrong_answers": 5,
      "tasks": [
        {
          "title": "Getting to know the environment",
          "order": 0,
          "content": "The master handed you a laptop... Look around...",
          "answer": "wordlist.txt",
          "solution": "user@attacker:~# ls ...",
          "incorrect_answer_limit": 5
        },
        {
          "title": "Getting to know the environment (Helper Version)",
          "order": 1,
          "content": "The master handed you a laptop... Use ls...",
          "answer": "wordlist.txt"
        }
      ],
      "decision_matrix": [
        {
          "order": 0,
          "questionnaire_answered": 1.0,
          "keyword_used": 0.0,
          "completed_in_time": 0.0,
          "solution_displayed": 0.0,
          "wrong_answers": 0.0
        }
      ]
    }
  ]
}
```

---

## 3. Key Adaptive Components

### 3.1 Adaptive Pre-Game Questionnaire & `phase_relations`
Adaptive trainings begin with a questionnaire phase. Based on the trainee's
answers, the platform dynamically routes them to specific phases using the
`phase_relations` block:

```json
"questionnaire_type": "ADAPTIVE",
"phase_relations": [
  {
    "order": 0,
    "question_orders": [7],   // References Question Order ID
    "phase_order": 3,         // Target Phase to jump to if answered correctly
    "success_rate": 100
  }
]
```
This enables bypassing introductory levels for experienced users (skipping
straight to advanced phases).

### 3.2 Difficulty Task Variants (`tasks` array)
Instead of a single text description, a `TRAINING` phase holds multiple
alternative tasks (usually ordered by difficulty). The platform monitors
trainee struggles (e.g., wrong submissions or idle time) and can dynamically
downgrade the task to an easier version with extra hints or instructions
(e.g., swapping Task `order: 0` for Task `order: 1`).

### 3.3 Dynamic Decision Matrix (`decision_matrix`)
The `decision_matrix` configures the weights used by the adaptive scoring
engine to assess trainee progress:
* `questionnaire_answered`: Weight of pre-game questionnaire responses.
* `wrong_answers`: Penalty factor for incorrect answer submissions.
* `completed_in_time`: Scoring modifier for completing tasks under the
  estimated duration limits.
* `solution_displayed`: Heavy penalty weight if the trainee explicitly
  reveals the solution.
  