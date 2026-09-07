# Phase 1. Topic Mind Map
## Phase 1a. Topic Mind Map Generation

```
You are helping me build a mind map for studying web development, as part of a personal AI-assisted learning system.

TOPIC TO DECOMPOSE: [e.g. "React", "CSS Layout", "HTTP & Networking"]

MY CURRENT LEVEL: [e.g. "total beginner", "know the basics, shaky on advanced patterns", "comfortable but want to fill gaps"]

WHAT I ALREADY KNOW (skip or go light on these, if anything): [list, or "nothing yet"]

Your job: produce a detailed mind map / table of contents that breaks the topic down into all essential subtopics.

Rules:
1. **Breadth.** Cover every concept a learner would need to master, fundamentals through advanced.
2. **Be specific.** Prefer concrete over general.
3. **Ordering by dependency.** The structure must follow actual prerequisite relationships. A learner should encounter concepts only after the concepts required to understand them.
4. **Do not explain the concepts yet**
```

## Phase 1b. Gap Check (no needed)

```
You are auditing a study mind map for gaps, as a second-pass review — a separate critical read, not a continuation of writing it.

Below is a finished mind map for the topic "[TOPIC]".

Your job is ONLY to find what's missing — do not rewrite or reorganize existing nodes.

Check for:
1. **Bridge topics** — concepts that silently connect two sections but aren't listed anywhere (e.g. if "CSS specificity" and "CSS-in-JS" both exist but nothing covers how specificity behaves differently there, that's a gap).
2. **Broken dependency order** — any node that assumes knowledge from a node listed later.
3. **Missing prerequisites** — foundational concepts the map assumes without ever teaching (check especially the first 1–2 items of each major section).
4. **Shallow leaves** — nodes that claim breadth but are clearly compound topics hiding multiple sub-concepts a learner would get stuck on.
5. **Real-world gaps** — things practitioners hit constantly that a purely conceptual breakdown tends to skip (tooling quirks, browser inconsistencies, debugging workflow, etc.)

Output format:
- A flat list of proposed additions, each with: the new node text which existing section it belongs under, and a one-line reason it's needed.
- If you find no gaps in a category, state that explicitly rather than omitting the category — I want to know it was checked, not just skipped.
- Do not restate or summarize the existing map.

MIND MAP TO AUDIT:
[paste the finished mind map here]
```

---
# Phase 2. Subtopic Deep Dive (one at a time)
Purpose: Fill in the subtopic with all the relevant / valuable information that needs to be understood and acquired.

```
You are generating the core explanation for one subtopic in my AI-assisted learning system for web development.

SUBTOPIC: [exact name from mind-map.md, e.g. "useEffect dependency arrays"]
PARENT AREA: [e.g. "React Hooks"]
MY CURRENT LEVEL: [e.g. "beginner", "comfortable with JS but new to React"]
PREREQUISITES: [list of subtopics from mind-map.md I've already covered and should be assumed known, e.g. "useState", "JS closures", "component re-renders" — if none yet, write "none yet"]

First, decide what TYPE of subtopic this is. Prefer one of these, but use a different type if something else genuinely fits better:
- Conceptual (needs a mental model/analogy/why-it-exists)
- Syntax/API (needs canonical examples + edge cases)
- Applied/Project (needs a minimal working example + when to use it)
- Comparative (needs a side-by-side with decision criteria)
- Tooling/Workflow (needs setup steps, config, and common failure points)

Then generate the exploration content matching that type. Length should be exactly as long as this specific subtopic needs to be, no longer — a one-liner like `&&` for conditional rendering might need a couple sentences and one example; something like the event loop might need real depth. Let the subtopic's actual complexity decide, not a target.

Use PREREQUISITES actively: build on what I already know rather than re-explaining it. Where relevant, explicitly connect new material to a prerequisite (e.g., "since you already understand X, this extends it by...") instead of treating this as my first exposure to programming.
```

---
# Phase 3: Triage

````text
You are an expert technical editor and web development mentor. Read the text below and extract the most valuable ideas in it — the insights a working developer would actually want to remember, not surface-level facts.

## What counts as a "valuable idea"

Look for:

- Core principles or rules that explain _why_ something works the way it does
- Mental models, analogies, or metaphors that make a hard concept intuitive
- Common pitfalls, gotchas, or misconceptions the text corrects
- Practical techniques, patterns, or workarounds
- Design rationale — trade-offs, "the reason X works this way is..."
- Performance or architectural implications
- Counterintuitive or myth-busting claims — places where the text directly overturns a common assumption
- Rules of thumb or heuristics for making a quick decision
- Comparisons or trade-off breakdowns between two approaches, tools, or techniques
- Underlying mechanisms — explanations of "how this actually works under the hood"
- Historical or evolutionary context — why something changed, or was designed differently than an earlier alternative
- Terminology reframes — a definition that shifts how you think about a familiar term
- Security, accessibility, or compatibility implications
- Cause-and-effect relationships ("if you do X, Y happens, because...")

Skip: pure definitions, restated syntax, or anything without a practical "so what" for a developer.

## Categories

Sort each idea into exactly one of these (only add a new category if truly nothing fits):

- **Core Concept** — a fundamental rule or fact about how something works
- **Mental Model** — an analogy or way of visualizing the concept
- **Pitfall / Gotcha** — a mistake, misconception, or edge case to watch for
- **Technique / Pattern** — a reusable, practical approach
- **Design Rationale** — the "why" behind an architectural or API decision
- **Performance Note** — anything affecting speed, memory, or scalability
- **Heuristic / Rule of Thumb** — a quick decision-making guideline
- **Historical Context** — why something evolved, changed, or replaced an earlier approach

## Instructions

1. Read the whole text first, including code snippets and diagrams — ideas are often embedded in them, not just the prose.
2. Extract every distinct idea you find. There is no maximum — capture as many or as few as the text actually supports, and don't stop early or force a "top N" selection. Merge only true near-duplicates; don't merge ideas just to keep the list shorter.
3. Write every idea in your own words. Do not copy sentences verbatim from the source.
4. For each idea, give: a short title, its category, a brief explanation, and a brief note on why it matters in practice. Keep the language tight and skip filler words, but let an idea run longer than usual if it genuinely needs the room to stay clear — don't force artificial brevity at the cost of clarity.
5. Order categories by how many ideas they contain (most first).
6. Omit any category header that has zero ideas — don't force a fit.
7. If two ideas seem to belong to the same category but represent genuinely different insights, keep them separate.

## Output format

Respond in Markdown using exactly this structure. The categorized ideas come first; the source reference is always the last line of the file:

```
## [Category]
- **[Idea title]** — [Brief explanation]. 
  **Why it matters:** [practical relevance].
```

## File Output Instructions (for agent use)

- Read the source text from `{{SOURCE_FILE_PATH}}`. If there's no file (pasted text only), use the `<source_text>` block below instead and skip the source line in the output.
- Save the extracted ideas to a new file named `{{source_filename}}-summary.md` — same name as the source file, just with `-summary` appended before the extension. `{{source_filename}}` = the source's filename without its extension (e.g. source `queues-and-callbacks.md` → output `queues-and-callbacks-summary.md`).
- Save it in the same directory as the source file. Don't create a new folder.

Source: @{{relative_path_to_source}}
````


# Phase 4: Teach back / Feynman Technique
## Phase 4a: Question Generation

````
Act as an expert learning strategist and senior technical mentor. Your goal is to help me deeply internalize a specific topic using the "Teach-Back" method, rooted in the Feynman Technique and constructivist learning principles.

Given a topic, generate questions that test real understanding — the way a good tutor would. Not recall, not trivia — reasoning.

## File output

- **File:** `{{source_filename}}-teach-back.md` — the source's filename without its extension, plus `-teach-back.md` (e.g. source `queues-and-callbacks.md` → file `queues-and-callbacks-teach-back.md`). Same directory as the source. Don't create a new folder.
- Number questions sequentially across the whole file, starting at 1.

## Format

```
### Question [n]
[Question text]

----
```

## Input
- **Source file:** 

````

## Phase 4b: Grading

````
Grade a teach-back answer to determine whether I actually understand the concept well enough to explain it to someone else — not whether I said something plausible.

Use the question, source material, ideas, and your general knowledge to determine what understanding the question actually requires.

## What counts as understanding

**Mechanism-level reasoning:** the actual causal or structural "why," stated concretely enough that it could predict what happens in a new, unseen case.

These do NOT count as understanding on their own, even when nothing in the answer is technically false:

- Confident tone
- Correct vocabulary or terminology without demonstrating what the terms mean or how they relate
- A restated definition
- Hedged language ("it depends," "generally," "sort of") standing in for a mechanism
- Restating the question back as if it were an answer

The Feynman technique exists to catch exactly this kind of fluent-sounding gap — be strict.

However:

- Do not require specific terminology or wording from the source.
- Do not require implementation details that are unnecessary for answering the question.
- Accept technically correct explanations that use different terminology, examples, or mental models from the source.
- Do not confuse minor imprecision with a lack of understanding.
- Judge whether the learner has the core mental model needed to answer this particular question, not whether they explained every aspect of the broader topic.
- Do not downgrade an answer merely because it is brief. A concise answer can demonstrate strong understanding.

## How to judge

First determine what the question is actually testing and what reasoning is necessary to answer it well.

Then compare the answer against the actual mechanism behind that concept.

Determine:

1. What does the learner clearly understand?
2. What reasoning or mechanism did they successfully demonstrate?
3. What important piece, if any, is missing or incorrect?
4. What type of gap is it?
5. What should happen next: move on, reinforce, or teach and retest?

Do not infer understanding that the learner has not demonstrated.

## Understanding

Choose exactly one:

- **Strong** — The learner demonstrates the relevant mechanism or mental model accurately and sufficiently. They could likely apply it to a new case.
- **Good** — The core mechanism is understood, but there is a minor imprecision, omission, or weakness that does not meaningfully undermine the mental model.
- **Partial** — The learner demonstrates some genuine understanding, but a meaningful part of the mechanism, relationship, or boundary is missing or unclear.
- **Wrong** — The answer contains a genuine misconception or incorrect causal/structural explanation.

## Gap type

If there is a meaningful weakness, choose the most important gap type:

- **Mechanism** — knows what happens but cannot explain why/how.
- **Relationship** — understands the individual concepts but not how they relate.
- **Boundary** — does not understand where the concept applies or stops applying.
- **Application** — understands the concept but cannot correctly apply it to the question.
- **Terminology** — the underlying idea is understood, but important terminology is being used incorrectly or ambiguously.
- **Completeness** — the core idea is understood but an important component needed for this question is missing.
- **Misconception** — has a specific incorrect mental model.
- **None** — no meaningful gap.

Do not label a minor wording issue as a gap.

## Next action

Choose exactly one:

- **Move on** — understanding is sufficient; no targeted remediation is needed.
- **Reinforce** — understanding is basically correct, but a brief clarification or additional example would be useful.
- **Teach + Retest** — there is a meaningful conceptual gap or misconception that should be addressed before moving on.

## Output

Return exactly:

```
<details> 
	<summary>Understanding: [Strong | Good | Partial | Wrong]</summary>
	Gap type: [Mechanism | Relationship | Boundary | Application | Terminology | Completeness | Misconception | None]<br>
	<br>
	What you understand:<br>
	[Describe the specific understanding demonstrated by the learner.]
	<br>
	What is missing:<br>
	[Describe the precise missing, weak, or incorrect part. Write "Nothing significant" if there is no meaningful gap.]
	<br>
	Next action: [Move on | Reinforce | Teach + Retest]
</details>
```

Be specific. Do not write generic feedback such as "this is incomplete" or "you need more detail." Identify the exact mental-model gap.

Do not praise the learner unnecessarily. The purpose of the evaluation is accurate diagnosis.

## File handling

- The teach-back file contains the questions and my answers, insert the collapsible grading block immediately after each answers – before the next `### Question` heading, not at the end of the file.
- Skip any question with no answer yet.
- Skip any question that already has a grading block beneath its answer — don't re-grade or duplicate.
- Save the changes back into the same file, in place. Don't create a new file, and don't touch the question text or answers themselves.
- Once done, don't reprint the graded file in the response — just confirm briefly how many answers were graded.
  
## Inputs
Teach-back answers: {{teachbackanswers}}
````

## Phase 4c: Reinforcing

````
Given a graded teach-back file, generate a fresh set of questions targeting only the weak spots — skip anything already Strong. Add the questions back into the file.
````

## Phase 4d: Regrading

---
# Phase 5: Edge Case / "What If" Drilling

Purpose: Teach-back checks whether I can _state_ the concept. This checks whether I can _apply_ it — probing corner cases the source content doesn't spell out directly, but that follow from combining rules it does state (e.g. "what happens if you delete a non-configurable property?" / "what if you `Object.freeze` a nested object?").

## Phase 5a: Edge Case Question Generation

```
You are generating edge-case / "what if" questions for one subtopic, in my
AI-assisted learning system for web development.

SUBTOPIC: {{subtopic_name}}

SOURCE CONTENT:
{{phase_2_content}}

Your job: construct corner-case scenarios that aren't directly answered in the source content, but whose answer follows logically from combining two or more ideas from the source content. This tests whether I actually internalized the underlying model, not just the examples given.

Rules:
1. **Favor intersections.** Best edge cases sit at the boundary of two rules or two features interacting (e.g. rule A + rule B applied to the same objec at once) — these are where real bugs happen and where shallow understanding breaks first.
2. **Prioritize by stakes, not obscurity.** Pick edge cases that matter in practice (things that would actually surprise someone writing real code) over trivia-tier corner cases nobody hits.
3. **Target [soft spot] and T4 (Heuristic/Gotcha) content first**, if triage (Phase 4a) has already been run for this subtopic — gotchas are exactly where edge-case reasoning tends to fail. Fall back to reasoning directly from the core explanation if no triage exists yet.
4. **Right amount, not maximum amount.** 3-6 questions, scaled to how many genuinely distinct rule-intersections exist in this subtopic. Don't pad with near-duplicate scenarios.
5. **No answers yet.** Output only the questions — no model answers or grading criteria.

Output format: numbered list of questions
```

## Phase 5b: Edge Case Grading

```
You are grading my edge-case / "what if" answers against the source content for one subtopic.

SUBTOPIC: {{subtopic_name}}

SOURCE CONTENT (core explanation + any elaborations):
{{phase_2_content}} + {{phase_3_elaborations}}

QUESTIONS AND MY ANSWERS:
{{qa_pairs}}

The source content does NOT state the answers to these questions directly — each correct answer follows only from combining rules the source DOES state. So your job has three parts:

1. **Reconstruct the correct answer** by combining the relevant rules from the source content yourself, checking your own derivation before grading.
2. **Grade the derivation, not just the destination.** The purpose of edge-case drilling is testing whether I internalized the underlying model, not whether I can name the right output. A correct-sounding conclusion reached for the wrong reasons is still a miss — grade the reasoning chain, not just the final result.
3. **Catch fluent-sounding wrongness.** Be strict about answers that wave at the right keywords, copy an example from the source without adapting it to the scenario, or commit a rule-application error mid-chain (e.g. applying rule A where rule B governs, or failing to notice two rules interacting). This is where shallow understanding conceals itself.

For each question output:

---
**Q[N] Result:** ✅ Solid / ⚠️ Partial (name the gap) / ❌ Missed
**What was right:** [brief]
**What was missing or wrong:** [specific — quote the rule(s) from the source content the answer misapplied, skipped, or combined incorrectly, and state the correct derivation]
**Suggested action:** [None / Re-read: "[section]" / Run a mini elaboration now]
---

If an answer invents premises — assumes behavior the source content never implies, rather than deriving it from the stated rules — flag it as a wrong turn, not a bonus. The questions were designed to be answerable from the source content alone.

```

---
# Phase 6. Exercise
## Phase 6a: Exercise Generation Prompt

```
You are generating exercises from an ALREADY-TRIAGED claim list for one subtopic.
Do not re-triage — the tiers below are final and approved by the user.

## Input

**Subtopic name:** {{subtopic_name}}

**Source content (for grounding exercises only):**
{{phase_2_content}} + {{phase_3_elaborations}}

**Triaged claims (Phase 4a output, possibly user-edited):**
{{triage_output}}

## Task — generate one exercise per claim, per tier rules

**T1 (Core concept):**
- Coding exercise that would fail if the concept isn't understood
- Includes a trap catching the specific common misconception

**T2 (Pattern / Decision):**
- Realistic goal, asks for a designed solution
- Does NOT specify which APIs to use
- Evaluated on trade-offs considered, not just correctness

**T3 (Usable API):**
- Tests WHEN to use the API, not its signature
- Scenario-based, asks to pick the right tool + justify

**T4 (Heuristic / Gotcha):**
- "Spot the bug" or "what will this output and why"
- Specifically targets the misconception described

**T5 (Context / Trivia):**
- Skip entirely

**Grounding rule:** every exercise must be answerable using ONLY the source content.
If an exercise would require outside knowledge, discard and regenerate it.

## Output format

### Exercise N: [Title]
**Tests:** [Tier] — [concept name]
**Task:** [Task]
**Expected behavior:** [output or behavior description]
**Grading criteria:** [what a correct answer must demonstrate — internal use only]
```

## Phase 6c: Grading Prompt (Tiered)

```
You are grading ONE answer against the source content and grading criteria for a tiered exercise. Do not accept answers correct "in general" but not actually supported by the source material — grade against the content, not general knowledge.

## Input

**Exercise:** {{exercise.task}}
**Tier:** {{exercise.tier}} — {{exercise.concept_name}}
**Grading criteria:** {{exercise.grading_criteria}}
**Source content:** 
{{phase_2_content}}
**User's answer:** {{user_answer}}

## Grading approach by tier

- **T1:** correctness is binary-ish — did they avoid the trap and understand *why*, not
  just produce working output?
- **T2:** grade the trade-offs articulated, not just whether the solution works. Note
  which considerations they missed.
- **T3:** grade the justification for *when* to use the tool, not just correct usage.
- **T4:** grade whether they identified the actual misconception, not just fixed the bug.

## Your task

1. Judge correctness per the tier-specific approach above.
2. Cite the specific part of the source content that confirms the correct answer and offer to run a mini elaboration on this specific point now.

## Output format

Present the result as:

---

**Result:** ✅ Correct / ⚠️ Partially correct / ❌ Incorrect

**Feedback:**
[Feedback, tier-appropriate — see grading approach above]

**Source citation:**
[The specific part of the source content that confirms the correct answer]

**Recurring gap:** [Only shown if true] ⚠️ This is a soft spot that's now failed twice — worth sitting with this one rather than moving on.

**Suggested action:** [None / Re-read: "[section name]" / Run a mini elaboration on this now?]

---
```

---
# Phase 7. Anki Cards
Purpose: Convert the triaged claims (Phase 6a output) into a comprehensive, atomic flashcard list for long-term retention in Anki. Cards are generated from the triage output — never from raw content — so completeness and traceability are inherited from the triage pass.

## Phase 7a. Card Generation

```
You are generating Anki flashcards from an ALREADY-TRIAGED claim list for one subtopic, in my AI-assisted learning system for web development.

## Input

**Subtopic name:** {{subtopic_name}}

**Triaged claims (Phase 6a output, possibly user-edited):**
{{triage_output}}

**Source content (for grounding cards only):**
{{phase_2_content}} + {{phase_3_elaborations}}

**Known soft spots / recurring gaps (optional, from Phases 4b / 6c):**
{{soft_spots}}

## Task — one card per claim, card type determined by tier

**T1 (Core concept):** mechanism card. Front asks for the *why* or the breaking point — "Why does X happen?", "What would break if you removed X?" — never "What is X".

**T2 (Pattern / Decision):** decision card. Front presents a situation or a pair — "A vs B — when do you reach for which?" — back gives the decision criteria, not just the choice.

**T3 (Usable API):** "when to reach for it" card. Front is a scenario, back is the tool + one-line justification. Use cloze deletion ({{c1::...}}) for anything that must be recalled precisely rather than recognized.

**T4 (Heuristic / Gotcha):** gotcha card. Front shows the failing code or the wrong belief, back states the misconception and the correction. No plain rule-recitation ("remember to X").

**T5 (Context / Trivia):** skip entirely.

## Rules

1. **Atomicity.** One testable fact per card. If a claim bundles two independent facts, split it into two cards.
2. **Minimum information.** Shortest card that still tests the claim. Backs are 1–2 sentences — no restating the front, no essays.
3. **Front hygiene.** The front must not give away the answer. If the front contains a term, the back must add information beyond restating it.
4. **Grounding.** Every back must be answerable using ONLY the source content. If a card requires outside knowledge, discard and regenerate it.
5. **No hedging.** Backs are definitive. If something is conditional, state the condition — never bare "it depends."
6. **Traceability.** End each back with the claim's source quote, in the form [src: "<quote from the triage table>"]. This doubles as the re-read anchor the graders suggest when a card fails.
7. **Tagging.** Tags: `WebDev::<Topic>::<ParentArea>` (topical hierarchy), `subtopic::<subtopic_name>`, `T<n>` (claim tier), and `soft_spot` when the claim matches a known soft spot or recurring gap from the input.

## Output format

TSV, one card per line, tab-separated: `front<TAB>back<TAB>tags` (tags space-separated). No headers, no commentary — the list imports directly into Anki.
```

```
# Generate Spaced-Repetition Cards

You are generating spaced-repetition cards from my notes.

Your goal is **not to turn the notes into flashcards exhaustively**.

Your goal is to identify the **smallest set of high-value knowledge worth retaining** and create effective retrieval prompts for that knowledge.

> **Don't make cards for information. Make cards for knowledge I want my future self to be able to retrieve and use.**

## 1. Select valuable knowledge

First, privately identify the important knowledge in the notes.

Prioritize things that are:

- important for understanding the topic
    
- useful for future reasoning or application
    
- easy to forget
    
- foundational to other knowledge
    
- important for avoiding misconceptions
    

Do not create cards for incidental details, redundant information, obvious implications, or information that is only useful in the immediate context.

**Prefer fewer strong cards over exhaustive coverage.**

## 2. Design the right retrieval task

For each important knowledge unit, determine what I should be able to retrieve from memory.

Choose the simplest card type that tests it effectively:

- **Fact / Definition** — retrieve a specific piece of knowledge
    
- **Distinction** — distinguish between easily confused concepts
    
- **Relationship** — explain how concepts relate
    
- **Mechanism / Causal** — explain how or why something happens
    
- **Prediction** — predict what happens in a situation
    
- **Application** — use knowledge in a concrete situation
    
- **Procedure** — recall an important sequence or decision process
    
- **Principle** — state or apply a general rule
    
- **Misconception** — distinguish a tempting incorrect model from the correct one
    

Prefer **understanding, explanation, prediction, and application** when the source supports them. Do not force these formats onto simple facts.

## 3. Make each card effective

Every card should:

- test **one coherent retrieval target**
    
- have a precise, unambiguous question
    
- require genuine recall rather than recognition
    
- be answerable without the surrounding notes
    
- provide enough context without revealing the answer
    
- have a concise but sufficient answer
    
- test knowledge that is meaningfully different from other cards
    

Avoid:

- broad prompts such as "Explain everything about X"
    
- long list-recall questions unless the list itself is important
    
- trivial facts
    
- questions containing their own answers
    
- redundant cards
    
- artificial difficulty
    

Do not split a concept if doing so destroys an important relationship.

## 4. Stay within the source

Base the cards on the supplied notes.

You may reorganize and rephrase the material to create better retrieval prompts, but do not introduce outside knowledge.

If the source is ambiguous or incomplete, preserve that limitation rather than inventing an answer.

## 5. Final quality check

Before including a card, privately ask:

- Is this worth remembering?
    
- Is the retrieval target clear?
    
- Does answering require actual recall?
    
- Is the card appropriately difficult?
    
- Is it non-redundant?
    
- Is the answer supported by the source?
    

Reject cards that fail these criteria.

## Output

|#|Type|Front|Back|
|---|---|---|---|
|1|Mechanism|...|...|
|2|Distinction|...|...|

After the table, briefly provide:

### Coverage

The major knowledge areas represented.

### Intentionally omitted

Important source material that was deliberately not turned into cards and why.

Do not generate cards to meet a quota.

**Optimize for long-term learning value, not card count.**

---

## Source notes

{{notes}}
```

`````
# Generate Spaced-Repetition Cards

You are generating spaced-repetition cards from my notes.

Your goal is **not to turn the notes into flashcards exhaustively**.

Your goal is to identify the **smallest set of high-value knowledge worth retaining** and create effective retrieval prompts for that knowledge.

> **Don't make cards for information. Make cards for knowledge I want my future self to be able to retrieve and use.**

## 1. Select valuable knowledge

First, privately identify the important knowledge in the notes.

Prioritize things that are:

- important for understanding the topic 
- useful for future reasoning or application
- easy to forget
- foundational to other knowledge
- important for avoiding misconceptions

Do not create cards for incidental details, redundant information, obvious implications, or information that is only useful in the immediate context.

**Prefer fewer strong cards over exhaustive coverage.**

## 2. Design the right retrieval task

For each important knowledge unit, determine what I should be able to retrieve from memory.

Choose the simplest card type that tests it effectively:

- **Fact / Definition** — retrieve a specific piece of knowledge
- **Distinction** — distinguish between easily confused concepts
- **Relationship** — explain how concepts relate
- **Mechanism / Causal** — explain how or why something happens
- **Prediction** — predict what happens in a situation
- **Application** — use knowledge in a concrete situation
- **Procedure** — recall an important sequence or decision process
- **Principle** — state or apply a general rule
- **Misconception** — distinguish a tempting incorrect model from the correct one

Prefer **understanding, explanation, prediction, and application** when the source supports them. Do not force these formats onto simple facts.

## 3. Make each card effective

Every card should:

- test **one coherent retrieval target**
- have a precise, unambiguous question
- require genuine recall rather than recognition
- be answerable without the surrounding notes
- provide enough context without revealing the answer
- have a concise but sufficient answer
- test knowledge that is meaningfully different from other cards

Avoid:

- broad prompts such as "Explain everything about X"
- long list-recall questions unless the list itself is important
- trivial facts
- questions containing their own answers
- redundant cards
- artificial difficulty

Do not split a concept if doing so destroys an important relationship.

## 4. Place cards next to the knowledge they test

**Do not put all cards in a separate section at the end.**

Preserve the structure and ordering of the source notes as much as possible.

When a piece of knowledge deserves a card, place the card **immediately after the smallest relevant passage that contains or explains that knowledge**.

This creates a:

> knowledge → card → knowledge → card

structure.

Do not place a card after an entire large section if the knowledge it tests appears much earlier.

If several consecutive passages contribute to one coherent knowledge unit, place the card after the final relevant passage.

If a card tests an idea synthesized from multiple distant parts of the notes, place it at the point where that idea is best established.

Cards should not interrupt a sentence, code block, table, or other structure in a way that makes the source difficult to read.

## 5. Card formatting

Every card **MUST** use exactly this format:

```anki
id: 7b1f3e8a-2c4d-4f5e-9a6b-8c7d0e1f2a3b
[front]
front question
[/front]
[back]
back answer
[/back]
```

Formatting rules:

- The opening fence **MUST** be exactly ````anki
- `id:` **MUST** be present
- Every `id` **MUST** be a newly generated random UUID-format identifier
- `[front]` and `[/front]` **MUST** surround the question
- `[back]` and `[/back]` **MUST** surround the answer
- The closing fence **MUST** be exactly ````
- Do not add `Type`, `#`, tables, or other metadata to cards
- Do not reuse IDs
- Do not modify the card format

## 6. Final quality check

Before including a card, privately ask:

- Is this worth remembering?
- Is the retrieval target clear?
- Does answering require actual recall?
- Is the card appropriately difficult?
- Is it non-redundant?
- Is the answer supported by the source?

Reject cards that fail these criteria.

## Output

Return the **source notes with the generated cards inserted next to the knowledge they test**.

Preserve the original notes as much as possible.

Do not create a separate "Cards" section.

Do not generate cards to meet a quota.

**Optimize for long-term learning value, not card count.**

---

## Source notes

{{notes}}
`````

`````
# Generate Spaced-Repetition Cards

You are generating spaced-repetition cards from my notes.

Your goal is **not to turn the notes into flashcards exhaustively**.

Your goal is to identify as many **high-value knowledge units worth retaining** as you reasonably can, and create effective retrieval prompts for them.

> **Don't make cards for information. Make cards for knowledge I want my future self to be able to retrieve and use.**

## 1. Select valuable knowledge

Privately identify the important knowledge in the notes.

Prioritize things that are:

- important for understanding the topic
- useful for future reasoning or application
- easy to forget
- foundational to other knowledge
- important for avoiding misconceptions

Do not create cards for incidental details, redundant information, obvious implications, or information that is only useful in the immediate context.

Aim for **high coverage of genuinely useful knowledge**, while avoiding low-value cards.

## 2. Design the right retrieval task

For each important knowledge unit, determine what I should be able to retrieve from memory.

Choose the simplest card type that tests it effectively:

- **Fact / Definition** — retrieve a specific piece of knowledge
- **Distinction** — distinguish between easily confused concepts
- **Relationship** — explain how concepts relate
- **Mechanism / Causal** — explain how or why something happens
- **Prediction** — predict what happens in a situation
- **Application** — use knowledge in a concrete situation
- **Procedure** — recall an important sequence or decision process
- **Principle** — state or apply a general rule
- **Misconception** — distinguish a tempting incorrect model from the correct one

Prefer **understanding, explanation, prediction, and application** when the material supports them. Do not force these formats onto simple facts.

## 3. Make each card effective

Every card should:

- test **one coherent retrieval target**
- have a precise, unambiguous question
- require genuine recall rather than recognition
- be answerable without the surrounding notes
- provide enough context without revealing the answer
- have a **short, focused answer**
- test knowledge that is meaningfully different from other cards

Avoid:

- broad prompts such as "Explain everything about X"
- long list-recall questions unless the list itself is important
- trivial facts
- questions containing their own answers
- redundant cards
- artificial difficulty
- yes or no questions

Do not split a concept if doing so destroys an important relationship.

## 4. Keep answers short

Answers should contain the **minimum information needed to answer the question correctly**.

Prefer:
- a concise definition
- a short explanation
- a few key points when necessary

Do not write essays, extended explanations, or repeat the source material unnecessarily.

The purpose of the back is to **verify and reinforce the recalled answer**, not to reproduce the notes.

## 5. Place cards directly into the source

**Do not simply list the generated cards in your response.**

Edit the source file and insert each card directly into the notes, immediately after the smallest relevant passage that contains or explains the knowledge being tested.

Preserve the original structure and ordering of the notes as much as possible.

For example:

```text
A closure is a function together with its surrounding lexical environment.

[ANKI CARD]

This allows the function to access variables from its outer scope...
```

If several consecutive passages contribute to one coherent knowledge unit, place the card after the final relevant passage.

If a card tests an idea synthesized from multiple distant parts of the notes, place it where that idea is best established.

Do not interrupt sentences, code blocks, tables, or other structures in a way that damages readability.

## 6. Card formatting

Every card **MUST** use exactly this format:

```anki
id: 7b1f3e8a-2c4d-4f5e-9a6b-8c7d0e1f2a3b
[front]
front question
[/front]
[back]
back answer
[/back]
```

Formatting rules:

- The opening fence **MUST** be exactly ````anki
- `id:` **MUST** be present
- Every `id` **MUST** be a newly generated random UUID-format identifier
- `[front]` and `[/front]` **MUST** surround the question
- `[back]` and `[/back]` **MUST** surround the answer
- The closing fence **MUST** be exactly ````
- Do not add `Type`, `#`, or other metadata to cards
- Do not reuse IDs

## 7. Generation, not evaluation

This is the **card-generation pass**.

Your job is to generate as many **genuinely useful, high-quality cards** as the material supports.

Do **not** perform a separate quality-filtering or elimination pass.

Do not deliberately reduce the number of cards because some may be borderline.

A separate process will later evaluate the cards and remove weak, redundant, trivial, or otherwise unsuitable cards.

Focus this pass on **discovering valuable retrieval opportunities throughout the material**.

## 8. Final output

The primary output is the **modified source file with the cards inserted into it**.

Do not reproduce the entire modified file in the response.

After editing the file, briefly report:

- number of cards generated
- any notable areas where cards were added
- any issues encountered while editing the file
  
## 9. Source files


`````

`````
# Generate Spaced-Repetition Cards

You are generating spaced-repetition cards from my notes.

Your goal is **not to turn the notes into flashcards exhaustively**.

Your goal is to identify the **high-value knowledge worth retaining** and create effective retrieval prompts for that knowledge.

> **Don't make cards for information. Make cards for knowledge I want my future self to be able to retrieve and use.**

## 1. Select valuable knowledge

Privately identify the important knowledge in the notes.

Prioritize things that are:

- important for understanding the topic
- useful for future reasoning or application
- easy to forget
- foundational to other knowledge
- important for avoiding misconceptions

Do not create cards for incidental details, redundant information, obvious implications, or information that is only useful in the immediate context.

Generate **all cards that are genuinely worth having**, but do not generate cards merely to increase coverage or card count.

## 2. Design the right retrieval task

For each important knowledge unit, determine what I should be able to retrieve from memory.

Choose the simplest card type that tests it effectively:

- **Fact / Definition** — retrieve a specific piece of knowledge
- **Distinction** — distinguish between easily confused concepts
- **Relationship** — explain how concepts relate
- **Mechanism / Causal** — explain how or why something happens
- **Prediction** — predict what happens in a situation
- **Application** — use knowledge in a concrete situation
- **Procedure** — recall an important sequence or decision process
- **Principle** — state or apply a general rule
- **Misconception** — distinguish a tempting incorrect model from the correct one

Prefer **understanding, explanation, prediction, and application** when the material supports them. Do not force these formats onto simple facts.

## 3. Make each card effective

Every card should:

- test **one coherent retrieval target**
- have a precise, unambiguous question
- require genuine recall rather than recognition
- be answerable without the surrounding notes
- provide enough context without revealing the answer
- have a **short, focused answer**
- test knowledge that is meaningfully different from other cards
- be useful enough to justify its existence

Avoid:

- broad prompts such as "Explain everything about X"
- long list-recall questions unless the list itself is important
- trivial facts
- questions containing their own answers
- redundant cards
- artificial difficulty
- cards whose answer is obvious from the wording
- cards that depend on remembering where the information appeared in the notes

Do not split a concept if doing so destroys an important relationship.

## 4. Keep answers short

Answers should contain the **minimum information needed to answer the question correctly**.

Prefer:

- one or two sentences
- a concise definition
- a short explanation
- a few key points when genuinely necessary

Do not write essays or reproduce the source material.

The back should **verify and reinforce the recalled knowledge**, not teach the entire topic again.

## 5. Create different retrieval angles when useful

A knowledge unit can justify more than one card when the cards test **meaningfully different kinds of retrieval**.

For example, it may be useful to separately test:

- remembering a principle
- explaining why it works
- applying it to a situation
- predicting its consequences

Do not create multiple cards merely by rewording the same question.

## 6. Write cards to a separate file

**Do not modify the source file.**

Create a separate file named:

`{{source_file_name}}-anki.md`

The file should contain the generated cards.

Preserve the **ordering and conceptual proximity of the source** when deciding the order of cards in the Anki file.

Cards testing knowledge introduced earlier in the source should generally appear earlier in the Anki file.

## 7. Card formatting

Every card **MUST** use exactly this format:

```anki
id: 7b1f3e8a-2c4d-4f5e-9a6b-8c7d0e1f2a3b
[front]
front question
[/front]
[back]
back answer
[/back]
```

Formatting rules:

- The opening fence **MUST** be exactly ` ```anki `
- `id:` **MUST** be present
- Every `id` **MUST** be a newly generated random UUID-format identifier
- `[front]` and `[/front]` **MUST** surround the question
- `[back]` and `[/back]` **MUST** surround the answer
- The closing fence **MUST** be exactly ` ``` `
- Do not add `Type`, `#`, or other metadata to cards
- Do not reuse IDs

## 8. Quality control

Before writing each card, privately evaluate it.

A card should pass all of these tests:

### Value

Would remembering this actually be useful?

### Focus

Does it test one coherent retrieval target?

### Precision

Is it clear exactly what I should retrieve?

### Retrieval

Does answering require genuine recall rather than recognition?

### Tractability

Can I realistically answer it from memory?

### Independence

Does it make sense without the surrounding notes?

### Brevity

Is the answer as short as possible while remaining correct?

### Non-redundancy

Does it test something meaningfully different from the other cards?

### Durability

Is this knowledge likely to remain useful beyond the immediate learning session?

If a candidate card fails these tests, **do not include it**.

## 9. Final objective

Generate **all genuinely valuable cards supported by the material**, while maintaining a high quality bar.

Optimize for:

> **the smallest useful retrieval prompts that will help my future self remember and use the important knowledge.**

## 10. Output

Create or update:

`{{source_file_name}}-anki.md`

Do not reproduce the cards in the chat response.

After completing the file, briefly report the number of cards generated.

## 11. Source files
`````

**Good sources**

`````
You are generating spaced-repetition cards from my notes.

Your job is to identify the as many **high-value knowledge units worth retaining long-term** as you reasonably can and turn it into effective retrieval prompts.

Do not simply extract facts from the notes.

> **Don't make cards for information. Make cards for knowledge I want my future self to be able to retrieve and use.**

## What deserves a card?

Before creating a card, privately ask:

> **If I forgot this tomorrow, would remembering it make me meaningfully better at understanding, reasoning about, or using this subject?**

Create a card only if the answer is yes.

Prioritize:

- core concepts and mental models
- important distinctions
- causal relationships and mechanisms
- principles and rules
- knowledge that enables prediction
- knowledge that enables application or decision-making
- important constraints and conditions
- misconceptions that are important to avoid

Do **not** create cards simply because something is:

- mentioned in the notes
- emphasized with formatting
- an interesting fact
- a historical detail
- an analogy or metaphor
- an example used to explain something
- part of a list or taxonomy

These may sometimes deserve cards, but only when the underlying knowledge itself is valuable to retain.

## Test understanding, not note recall

Prefer questions that require me to **reconstruct knowledge** rather than reproduce the wording or structure of the notes.

## One retrieval target

Each card should test **one coherent piece of knowledge**.

Do not combine several facts into one large question.

Avoid questions that ask me to:

- reproduce an entire framework
- enumerate long lists
- recall multiple unrelated facts
- reproduce the structure of the notes
- explain an entire topic
- yes or no questions

If several facts are valuable independently, create separate focused cards.

If the relationship between several facts is the important knowledge, test the relationship instead.

## Don't test teaching devices

The source may use:

- analogies
- metaphors
- examples
- stories
- historical context
- diagrams
- explanations written for teaching purposes

Do not create cards asking me to remember these teaching devices.

Instead, extract the **underlying concept they were used to teach**, if that concept is worth retaining.

## Answers

Keep answers **short and precise**.

The answer should contain enough information to verify the recall, but should not reproduce the explanation from the notes.

## Quality bar

Before including a card, privately check:

1. **Value** — Is this genuinely worth remembering?
2. **Understanding** — Does it test the underlying knowledge rather than note wording?
3. **Focus** — Does it test one coherent retrieval target?
4. **Retrieval** — Does it require genuine recall?
5. **Clarity** — Is it clear exactly what I should answer?
6. **Difficulty** — Is it challenging enough to require recall, but reasonably answerable?
7. **Independence** — Does it make sense without the surrounding notes?
8. **Non-redundancy** — Does it test something meaningfully different from existing cards?

If a candidate fails any important criterion, **do not create the card**.

Do not optimize for card count.

## Source and output file

Use the source notes as the material from which to identify valuable knowledge.

You may reorganize, connect, and rephrase ideas when necessary to create a better retrieval prompt.

Create a separate file:

`{{source_file_name}}-anki.md`

Do not modify the source file.

Preserve the conceptual ordering of the source when ordering the cards.

## Card format

Every card MUST use exactly this format:

````anki
[front]
front question
[/front]
[back]
back answer
[/back]
````

Rules:
- The opening fence **MUST** be exactly ````anki
- Do not add card types or other metadata.
- Do not add commentary inside cards.
- `[front]` and `[/front]` **MUST** surround the question
- `[back]` and `[/back]` **MUST** surround the answer
- The closing fence **MUST** be exactly ````
- Keep the front and back concise.

## Final objective

Generate **all cards that are genuinely valuable**, but be selective.

The goal is not to memorize the notes.

The goal is to build a small collection of prompts that repeatedly reinforce the **important mental models, relationships, principles, mechanisms, and usable knowledge** from the material.

Create the cards in `{{source_file_name}}-anki.md`.

Do not reproduce the cards in the chat response.

After completing the file, briefly report the number of cards generated.
`````

**Good one**

`````
You are generating spaced-repetition cards from my notes.

Your goal is **not to turn the notes into flashcards exhaustively**.

Your goal is to identify the **smallest set of high-value knowledge worth retaining** and create effective retrieval prompts for that knowledge.

> **Don't make cards for information. Make cards for knowledge I want my future self to be able to retrieve and use.**

## 1. Select valuable knowledge

First, privately identify the important knowledge in the notes.

Prioritize things that are:

* important for understanding the topic
* useful for future reasoning or application
* easy to forget
* foundational to other knowledge
* important for avoiding misconceptions

Do not create cards for incidental details, redundant information, obvious implications, or information that is only useful in the immediate context.

**Prefer fewer strong cards over exhaustive coverage.**

## 2. Design the right retrieval task

For each important knowledge unit, determine what I should be able to retrieve from memory.

Choose the simplest card type that tests it effectively:

* **Fact / Definition** — retrieve a specific piece of knowledge
* **Distinction** — distinguish between easily confused concepts
* **Relationship** — explain how concepts relate
* **Mechanism / Causal** — explain how or why something happens
* **Prediction** — predict what happens in a situation
* **Application** — use knowledge in a concrete situation
* **Procedure** — recall an important sequence or decision process
* **Principle** — state or apply a general rule
* **Misconception** — distinguish a tempting incorrect model from the correct one

Prefer **understanding, explanation, prediction, and application** when the source supports them. Do not force these formats onto simple facts.

## 3. Make each card effective

Every card should:

* test **one coherent retrieval target**
* have a precise, unambiguous question
* require genuine recall rather than recognition
* be answerable without the surrounding notes
* provide enough context without revealing the answer
* have a concise but sufficient answer
* test knowledge that is meaningfully different from other cards

Avoid:

* broad prompts such as "Explain everything about X"
* long list-recall questions unless the list itself is important
* trivial facts
* questions containing their own answers
* redundant cards
* artificial difficulty
* yes or no questions

Do not split a concept if doing so destroys an important relationship.

## 4. Final quality check

Before including a card, privately ask:

* Is this worth remembering?
* Is the retrieval target clear?
* Does answering require actual recall?
* Is the card appropriately difficult?
* Is it non-redundant?
* Is the answer supported by the source?

Reject cards that fail these criteria.

## Output

Every card MUST use exactly this format:

````anki
[front]
front question
[/front]
[back]
back answer
[/back]
````

Rules:
- The opening fence **MUST** be exactly ````anki
- Do not add card types or other metadata.
- Do not add commentary inside cards.
- `[front]` and `[/front]` **MUST** surround the question
- `[back]` and `[/back]` **MUST** surround the answer
- The closing fence **MUST** be exactly ````
- Keep the front and back concise.

## Source notes

{{notes}}

`````

## Phase 7b. Card Audit

```
You are auditing a generated Anki card list for one subtopic, as a second-pass review — a separate critical read, not a continuation of card writing.

Below is the card list for the subtopic "[SUBTOPIC]", generated from its triaged claims (Phase 7a output). The underlying triage and source content are authoritative: the cards must test exactly those claims, no more, no less.

Your job is ONLY to find problems. Do not rewrite passing cards, do not add new cards.

Check for:
1. **Fat cards** — cards bundling two or more independent facts. Mark for SPLIT and specify the resulting cards.
2. **Front leaks** — the front gives away its answer (the back merely restates the front's wording, or the question's phrasing contains the answer).
3. **Outside-knowledge cards** — backs requiring facts not present in the source content.
4. **Not grounded in triage** — cards testing claims not in the triage list, or contradicting one.
5. **Near-duplicates** — two cards testing the same fact from adjacent claims. Mark for MERGE and name the survivor.
6. **Min-info violations & hedging** — backs longer than needed, restating the question, or "it depends" without a stated condition.
7. **Tier mismatch** — card type that doesn't fit its claim's tier (e.g. a T4 gotcha written as rule-recitation, or a T2 decision card whose answer is a single tool with no decision criteria).
8. **Tag errors** — wrong tier tag, missing `soft_spot`, or tags that don't match the card's content.

Output format:
- A flat list of actions, each: card number, action (KEEP / SPLIT / MERGE / FIX / DROP), one-line reason, and corrected card text only for actions that require writing (SPLIT / MERGE / FIX).
- For every check category that passed with no issues, state that explicitly — I want to know it was checked, not skipped.
- Do not restate or summarize the card list.

CARD LIST TO AUDIT:
[paste the Phase 7a output here]
```

