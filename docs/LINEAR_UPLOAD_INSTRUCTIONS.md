# How to Add the Consolidated Design Document to Linear

## Quick Steps

1. **Open Linear** and navigate to the ShammyTime project
2. **Create a new document** (or edit an existing one)
3. **Copy the content** from one of these files:
   - `docs/DESIGN_LINEAR_COMPACT.md` — **Recommended** (concise, scannable, Linear-optimized)
   - `docs/DESIGN_LINEAR.md` — Full version with more detail
   - `docs/DESIGN.md` — Complete technical version (for repo reference)

4. **Paste into Linear** document editor
5. **Title the document:** "ShammyTime — Consolidated Design Document"
6. **Link the document** to issue BUI-12 and any other relevant Pressure Visual issues

## Which Version to Use?

### For Linear: Use `DESIGN_LINEAR_COMPACT.md`

**Why?**
- Optimized for Linear's document format
- More scannable with tables and quick reference sections
- Emoji headers for better visual navigation
- Shorter sections that work better in Linear's UI
- All essential information included

### For Repository: Use `DESIGN.md`

**Why?**
- Complete technical reference
- More detailed explanations
- Better for code reviews and implementation
- Includes full pseudocode examples

## Keeping Documents in Sync

**When to Update:**
- Design decisions are made
- Research findings emerge
- Implementation changes
- Tuning parameters adjusted

**How to Keep in Sync:**
1. Update `docs/DESIGN.md` in the repo (source of truth)
2. Update Linear document to match
3. Commit changes: `git commit -m "docs: [description]"`
4. Reference the Linear document in issues for context

## Alternative: Use Linear API (Future)

If you want to automate this in the future, you can use the Linear API:

```bash
# Install Linear CLI
npm install -g @linear/cli

# Authenticate
linear login

# Create document via API
# (requires API key and GraphQL knowledge)
```

For now, manual copy-paste is the simplest approach.

---

**Note:** The consolidated document is already committed and pushed to the repo in the `cursor/BUI-12-pressure-design-document-6d9c` branch.
