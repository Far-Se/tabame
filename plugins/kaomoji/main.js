"use strict";

const fs = require("fs");
const { spawn } = require("child_process");

const LIB = JSON.parse(fs.readFileSync("./lib.json", "utf8"));

function send(frame) {
  process.stdout.write(JSON.stringify(frame) + "\n");
}

function copy(text) {
  const p = spawn("cmd", ["/c", "clip"]);
  p.stdin.write(Buffer.from(text, "utf16le"));
  p.stdin.end();
}

function score(item, id, query) {
  if (!query) return 1;

  query = query.toLowerCase();

  let s = 0;

  if (id.toLowerCase() === query) s += 100;

  if (item.name.toLowerCase() === query) s += 100;

  if (id.toLowerCase().includes(query)) s += 50;

  if (item.name.toLowerCase().includes(query)) s += 50;

  if (item.category.toLowerCase().includes(query)) s += 20;

  if (item.entry.includes(query)) s += 10;

  for (const k of item.keywords || []) {
    const kw = k.toLowerCase();

    if (kw === query) s += 75;
    else if (kw.includes(query)) s += 40;
  }

  return s;
}

function render(rev, text) {
  const q = text.trim();

  const results = [];

  for (const [id, item] of Object.entries(LIB)) {
    const s = score(item, id, q);

    if (s > 0) {
      results.push({
        id,
        score: s,
        item,
      });
    }
  }

  results.sort((a, b) => b.score - a.score);

  send({
    type: "render",
    rev,
    view: "list",
    preview: {
      enabled: true,
    },
    emptyText: "No kaomoji found",
    items: results.slice(0, 100).map((r) => ({
      id: r.id,
      title: `${r.item.entry}`,
      subtitle: `${r.item.name} • ${r.item.category}`,
      icon: "emoji",
      accessories: r.item.keywords.map((k) => ({ text: k })),
      actions: [
        {
          id: "copy",
          title: "Copy",
          icon: "copy",
        },
      ],
      preview: {
        markdown: `# ${r.item.name}


\`\`\`
${r.item.entry}
\`\`\`

**Category:** ${r.item.category}

**Keywords**

${r.item.keywords.map((k) => "- " + k).join("\n")}`,
      },
    })),
  });
}

function handleAction(id, action) {
  const item = LIB[id];
  if (!item) return;

  if (action === "default" || action === "copy") {
    copy(item.entry);

    send({
      type: "render",
      rev: 0,
      view: "detail",
      detail: {
        markdown: `# Copied!

\`${item.entry}\`

**${item.name}**

The kaomoji has been copied to your clipboard.`,
      },
    });
  }
}

let buffer = "";

process.stdin.setEncoding("utf8");

process.stdin.on("data", (chunk) => {
  buffer += chunk;

  let index;

  while ((index = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, index).trim();
    buffer = buffer.slice(index + 1);

    if (!line) continue;

    let msg;

    try {
      msg = JSON.parse(line);
    } catch {
      continue;
    }

    switch (msg.type) {
      case "close":
        process.exit(0);

      case "init":
      case "query":
        render(msg.rev || 0, msg.text ?? msg.query ?? "");
        break;

      case "action":
        handleAction(msg.id, msg.action || "default");
        break;
    }
  }
});

process.stdin.on("end", () => process.exit(0));
