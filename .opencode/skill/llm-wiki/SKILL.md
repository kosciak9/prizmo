---
name: llm-wiki
description: "Use when maintaining Prizmo's knowledge-base/ LLM wiki. Triggers: knowledge-base, wiki, raw ingest, battle logs, codebase-driven wiki updates, TCG engine handoffs, north-star docs, query/archive/lint wiki, 'add to wiki', or 'what do I know about'."
---

# Prizmo LLM Wiki

Maintain Prizmo's persistent LLM-readable knowledge base. The human and coding agents use the wiki to compound project knowledge across research, product direction, TCG engine work, UI playtest handoffs, battle-log fixtures, and codebase changes.

Core ideas from Karpathy:

- "The LLM writes and maintains the wiki; the human reads and asks questions."
- "The wiki is a persistent, compounding artifact."

Prizmo-specific rule: the knowledge base root is **`knowledge-base/`**. Never create repo-root `raw/` or `wiki/` directories in this project.

## Architecture

Three layers, all under `knowledge-base/`:

**`knowledge-base/raw/`** — Immutable source material. You read, cite, and add new source captures here. Do not rewrite existing raw source content except for narrow metadata/link repairs during lint. Organized by topic subdirectories, for example `knowledge-base/raw/engine/`.

**`knowledge-base/wiki/`** — Compiled knowledge articles. You have full ownership. Organized by one-level topic subdirectories: `knowledge-base/wiki/<topic>/<article>.md`. Contains two special files:

- `knowledge-base/wiki/index.md` — Global index. One row per article, grouped by topic, with link + summary + Updated date.
- `knowledge-base/wiki/log.md` — Newest-first operation log.

**`knowledge-base/battle-logs/`** — Prizmo-specific PTCGL battle log artifacts and parser outputs. Original markdown logs are source artifacts and should not be rewritten. Parsed JSON files live under `knowledge-base/battle-logs/parsed/` and may be regenerated only during explicit parser/fixture work. `wiki/index.md` does not list individual battle-log files.

**`SKILL.md`** (this file) — Schema layer. Defines structure and workflow rules.

Templates live in `references/` relative to this file. Read them when you need the exact format for raw files, articles, codebase updates, handoffs, archive pages, or the index.

### Initialization

Triggers only on the first Ingest. Check whether `knowledge-base/raw/` and `knowledge-base/wiki/` exist. Create only what is missing; never overwrite existing files:

- `knowledge-base/raw/` directory (with `.gitkeep`)
- `knowledge-base/wiki/` directory (with `.gitkeep`)
- `knowledge-base/wiki/index.md` — heading `# Knowledge Base Index`, empty body
- `knowledge-base/wiki/log.md` — heading `# Wiki Log`, empty body

If Query or Lint cannot find the wiki structure, tell the user: "Run an ingest first to initialize the wiki." Do not auto-create.

---

## Ingest

Fetch an external or pasted source into `knowledge-base/raw/`, then compile it into `knowledge-base/wiki/`. Always both steps, no exceptions.

### Fetch (`knowledge-base/raw/`)

1. Get the source content using whatever web or file tools your environment provides. If nothing can reach the source, ask the user to paste it directly.

2. Pick a topic directory. Check existing `knowledge-base/raw/` subdirectories first; reuse one if the topic is close enough. Create a new subdirectory only for genuinely distinct topics.

3. Save as `knowledge-base/raw/<topic>/YYYY-MM-DD-descriptive-slug.md`.
   - Use the published date when known; otherwise use the collected date.
   - Slug from source title, kebab-case, max 60 characters.
   - If a file with the same name already exists, append a numeric suffix, for example `descriptive-slug-2.md`.
   - Include metadata header: source URL, collected date, published date.
   - Preserve original text. Clean formatting noise. Do not rewrite opinions.

   See `references/raw-template.md` for the exact format.

### Compile (`knowledge-base/wiki/`)

Determine where the new content belongs:

- **Same core thesis as existing article** → Merge into that article. Add the new source to Sources/Raw. Update affected sections.
- **New concept** → Create a new article in the most relevant topic directory. Name the file after the concept, not the raw file.
- **Spans multiple topics** → Place in the most relevant directory. Add See Also cross-references to related articles elsewhere.

These are not mutually exclusive. A single source may warrant merging into one article while also creating a separate article for a distinct concept it introduces. In all cases, check for factual conflicts: if the new source contradicts existing content, annotate the disagreement with source attribution. When merging, note the conflict within the merged article. When the conflicting content lives in separate articles, note it in both and cross-link them.

See `references/article-template.md` for article format. Key points:

- Sources field: author, organization, publication name, or project source + date/context, semicolon-separated.
- Raw field: markdown links to `knowledge-base/raw/` files, semicolon-separated, or an explicit `N/A — ...` reason for codebase/handoff articles.
- Relative paths from `knowledge-base/wiki/<topic>/` to raw files use `../../raw/<topic>/<file>.md`.
- Relative paths from `knowledge-base/wiki/<topic>/` to battle logs use `../../battle-logs/<file>.md` or `../../battle-logs/parsed/<file>.json`.

### Cascade Updates

After the primary article, check for ripple effects:

1. Scan articles in the same topic directory for content affected by the new source.
2. Scan `knowledge-base/wiki/index.md` entries in other topics for articles covering related concepts.
3. Update every article whose content is materially affected. Each updated file gets its Updated date refreshed.

Archive pages are never cascade-updated (they are point-in-time snapshots).

### Post-Ingest

Update `knowledge-base/wiki/index.md`: add or update entries for every touched article. When adding a new topic section, include a one-line description. The Updated date reflects when the article's knowledge content last changed, not the file system timestamp. See `references/index-template.md` for format.

Append a newest-first entry to `knowledge-base/wiki/log.md`, immediately after the title and blank line:

```markdown
## [YYYY-MM-DD] ingest | <primary article title>
- Updated: <cascade-updated article title>
- Updated: <another cascade-updated article title>
```

Omit `- Updated:` lines when no cascade updates occur.

---

## Codebase Updates

Use this workflow after implementation work when durable project knowledge changes. Examples:

- architecture or product direction changed;
- TCG engine behavior, supported mechanics, persistence, UI flow, or validation state changed;
- a north-star, handoff, or known limitation changed;
- battle-log parser/fixture behavior changed;
- the user explicitly asks to update the wiki/log after coding work.

Do **not** create raw files for ordinary codebase changes. The source is the project codebase, local validation, and the current conversation/task. Use raw files only for external/pasted source captures.

Steps:

1. Read `knowledge-base/wiki/index.md` to locate likely affected articles.
2. Prefer updating an existing article over creating a new one.
3. If the change is a transient execution state, update the relevant operational handoff page instead of a durable concept article.
4. If no external raw source exists, use one of:
   - `- Sources: Project codebase; local validation`
   - `- Sources: Project codebase; local validation; wiki log`
   - `- Raw: N/A — codebase update`
   - `- Raw: N/A — operational handoff`
5. Refresh the article's `- Updated:` date when knowledge content changes.
6. Update `knowledge-base/wiki/index.md` if an article was added, renamed, or its summary/date materially changed.
7. Add a newest-first codebase log entry to `knowledge-base/wiki/log.md`.

For the exact format, see `references/codebase-update-template.md`.

### Codebase Log Entry

For implementation-driven wiki updates, use this newest-first format immediately after `# Wiki Log` and the following blank line:

```markdown
## [YYYY-MM-DD] iteration <N> | <short title>
- Task attempted: <what changed or what was attempted>
- Files changed: <project and wiki files touched, or "wiki/log only">
- Validation: <tests/checks/manual verification, or why validation was not run>
- Remaining/blocking notes: <follow-up, current state, or blockers>
```

If there is no iteration number, use a descriptive operation label instead, for example:

```markdown
## [YYYY-MM-DD] codebase update | <short title>
```

Do not rewrite old log entries except for narrow factual corrections.

---

## Operational Handoffs and North Stars

Operational handoff pages are allowed and first-class in Prizmo's wiki. They track high-churn working state that future coding agents need, such as the current TCG playtest game, browser validation status, recommended next action, or active blockers.

Use this header:

```markdown
# <Title>

- Updated: YYYY-MM-DD
- Sources: Project codebase; local validation; wiki log
- Raw: N/A — operational handoff
```

Rules:

- Every handoff page must be listed in `knowledge-base/wiki/index.md`.
- Handoff pages may be updated frequently and may be long.
- `## See Also` is optional for high-churn handoff pages.
- Durable concept, architecture, and north-star pages should have `## See Also` links unless genuinely standalone.
- If a north-star page supersedes an older one, mark the old one as historical and cross-link both ways.

For the exact format, see `references/handoff-template.md`.

---

## Battle Logs

Use `knowledge-base/battle-logs/` for Prizmo-specific PTCGL battle logs and parsed fixture output.

Rules:

- Original battle-log markdown files are source artifacts: read and cite them, do not rewrite them.
- Parsed JSON under `knowledge-base/battle-logs/parsed/` may be regenerated only during explicit parser/fixture work.
- Wiki articles may cite battle logs with relative links such as `../../battle-logs/20260527150611.md`.
- Wiki articles may cite parsed JSON with relative links such as `../../battle-logs/parsed/20260527150611.json`.
- `knowledge-base/wiki/index.md` indexes wiki articles only, not raw files or battle-log artifacts.
- If a battle log materially changes compiled knowledge, update the relevant wiki article and log the operation.

---

## Query

Search the wiki and answer questions. Examples of triggers:

- "What do I know about X?"
- "Summarize everything related to Y"
- "Compare A and B based on my wiki"

### Steps

1. Read `knowledge-base/wiki/index.md` to locate relevant articles.
2. Read those articles and synthesize an answer.
3. Prefer wiki content over your own training knowledge. Cite sources with markdown links: `[Article Title](knowledge-base/wiki/topic/article.md)` (project-root-relative paths for in-conversation citations; within wiki files, use paths relative to the current file).
4. Output the answer in the conversation. Do not write files unless asked.

### Archiving

When the user explicitly asks to archive or save the answer to the wiki:

1. Write the answer as a new wiki page. See `references/archive-template.md`. When converting conversation citations to the archive page, rewrite project-root-relative paths (e.g., `knowledge-base/wiki/topic/article.md`) to file-relative paths (e.g., `../topic/article.md` or `article.md` for same-directory).
   - Sources: markdown links to the wiki articles cited in the answer.
   - Raw: `N/A — archived query answer`.
   - File name reflects the query topic, e.g., `transformer-architectures-overview.md`.
   - Place in the most relevant topic directory.
2. Always create a new page. Never merge into existing articles (archive content is a synthesized answer, not raw material).
3. Update `knowledge-base/wiki/index.md`. Prefix the Summary with `[Archived]`.
4. Append a newest-first entry to `knowledge-base/wiki/log.md`:

   ```markdown
   ## [YYYY-MM-DD] query | Archived: <page title>
   ```

---

## Lint

Quality checks on the wiki. Two categories with different authority levels.

### Deterministic Checks (auto-fix)

Fix these automatically:

**Index consistency** — compare `knowledge-base/wiki/index.md` against actual article files under `knowledge-base/wiki/<topic>/*.md`, excluding `index.md` and `log.md`:

- File exists but missing from index → add entry with `(no summary)` placeholder. For Updated, use the article's metadata Updated date if present; otherwise fall back to file's last modified date.
- Index entry points to nonexistent file → mark as `[MISSING]` in the index. Do not delete the entry; let the user decide.

**Metadata consistency** — every wiki article should have:

- `- Updated: YYYY-MM-DD`
- `- Sources: ...`
- `- Raw: ...`

`- Raw:` may be markdown links to source files, `N/A — codebase update`, `N/A — operational handoff`, or `N/A — archived query answer`.

**Internal links** — for every markdown link in wiki article files (body text and Sources metadata), excluding Raw field links (validated separately) and excluding `index.md`/`log.md` (handled above):

- Target does not exist → search `knowledge-base/wiki/` for a file with the same name elsewhere.
  - Exactly one match → fix the path.
  - Zero or multiple matches → report to the user.

**Raw references** — every markdown link in a Raw field must point to an existing `knowledge-base/raw/` file, `knowledge-base/battle-logs/` file, or `knowledge-base/battle-logs/parsed/` file:

- Target does not exist → search the relevant source tree for a file with the same name elsewhere.
  - Exactly one match → fix the path.
  - Zero or multiple matches → report to the user.

**See Also** — within each topic directory:

- Add obviously missing cross-references between related durable articles.
- Remove links to deleted files.
- Do not force `## See Also` onto high-churn operational handoff pages.

### Heuristic Checks (report only)

These rely on your judgment. Report findings without auto-fixing:

- Factual contradictions across articles
- Outdated claims superseded by newer sources or newer code
- Missing conflict annotations where sources disagree
- Orphan pages with no inbound links from other wiki articles, except intentional handoff/archive pages
- Missing cross-topic references
- Concepts frequently mentioned but lacking a dedicated page
- Archive pages whose cited source articles have been substantially updated since archival
- Handoff pages that are stale relative to current code, database state, or validation status

### Post-Lint

Append a newest-first entry to `knowledge-base/wiki/log.md`:

```markdown
## [YYYY-MM-DD] lint | <N> issues found, <M> auto-fixed
```

---

## Conventions

- Standard markdown with relative links throughout.
- `knowledge-base/wiki/` supports one level of topic subdirectories only. No deeper article nesting.
- `knowledge-base/raw/` is organized by one-level topic directories unless a specific source capture needs otherwise.
- `knowledge-base/battle-logs/parsed/` is the one accepted nested source-artifact directory.
- Today's date for log entries, Collected dates, Archived dates, and codebase/handoff Updated dates. For external sources, Published dates come from the source; use `Unknown` when unavailable.
- Updated dates reflect when the article's knowledge content last changed, not the file system timestamp.
- Inside wiki files, all markdown links use paths relative to the current file.
- In conversation output, use project-root-relative paths, for example `knowledge-base/wiki/engine/card-engine-authoring-models.md`.
- Ingest updates both `knowledge-base/wiki/index.md` and `knowledge-base/wiki/log.md`.
- Codebase updates update `knowledge-base/wiki/log.md` and any affected wiki/index entries.
- Archive (from Query) updates both `knowledge-base/wiki/index.md` and `knowledge-base/wiki/log.md`.
- Lint updates `knowledge-base/wiki/log.md` and only changes `knowledge-base/wiki/index.md` when auto-fixing index entries.
- Plain queries do not write any files.
