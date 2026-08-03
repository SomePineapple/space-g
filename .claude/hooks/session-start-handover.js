const fs = require('fs');
const path = require('path');

const root = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const files = ['handover.md', 'docs/gotchas.md'];

const sections = files
  .map((f) => {
    const full = path.join(root, f);
    try {
      return `--- ${f} ---\n${fs.readFileSync(full, 'utf8')}`;
    } catch {
      return null;
    }
  })
  .filter(Boolean);

const additionalContext = sections.join('\n\n');

process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext,
    },
  })
);
