"use strict";

// A comprehensive list of characters with searchable tags
const symbols = [
  // Dots & Circles
  { char: "•", name: "Bullet", tags: "dot point black circle bullet" },
  {
    char: "·",
    name: "Middle Dot",
    tags: "dot point middle interpunct centered",
  },
  { char: ".", name: "Full Stop", tags: "dot point period stop" },
  { char: "○", name: "White Circle", tags: "dot circle white empty large" },
  { char: "◦", name: "White Bullet", tags: "dot circle white small bullet" },
  {
    char: "¤",
    name: "Currency Sign",
    tags: "dot circle currency money general",
  },
  {
    char: "⁍",
    name: "Right Pointing Index",
    tags: "dot arrow pointer right index",
  },
  {
    char: "⁌",
    name: "Left Pointing Index",
    tags: "dot arrow pointer left index",
  },
  { char: "⚫", name: "Black Circle", tags: "dot circle black large filled" },
  { char: "⚪", name: "White Circle", tags: "dot circle white large medium" },
  {
    char: "◘",
    name: "Inverse Bullet",
    tags: "dot circle inverse bullet white",
  },
  { char: "■", name: "Black Square", tags: "square black block dot filled" },
  {
    char: "◙",
    name: "Inverse White Circle",
    tags: "dot circle inverse white bullet",
  },

  // Math
  { char: "±", name: "Plus Minus", tags: "math plus minus plusminus" },
  { char: "½", name: "One Half", tags: "math fraction half 1/2" },
  { char: "⅓", name: "One Third", tags: "math fraction third 1/3" },
  { char: "¼", name: "One Quarter", tags: "math fraction quarter fourth 1/4" },
  { char: "×", name: "Multiplication", tags: "math multiply times cross x" },
  { char: "÷", name: "Division", tags: "math divide division obelus" },
  { char: "≠", name: "Not Equal", tags: "math equal not different" },
  {
    char: "≈",
    name: "Almost Equal",
    tags: "math equal almost approximate tilde",
  },
  { char: "≤", name: "Less Than or Equal", tags: "math less equal leq" },
  { char: "≥", name: "Greater Than or Equal", tags: "math greater equal geq" },
  { char: "∞", name: "Infinity", tags: "math infinity infinite loop" },
  { char: "√", name: "Square Root", tags: "math sqrt root square check" },
  { char: "∑", name: "Summation", tags: "math sum sigma addition" },
  { char: "∫", name: "Integral", tags: "math integral calculus" },
  { char: "π", name: "Pi", tags: "math pi greek 3.14" },
  { char: "Δ", name: "Delta", tags: "math delta triangle change greek" },
  {
    char: "∇",
    name: "Nabla",
    tags: "math nabla gradient del upside down triangle",
  },
  {
    char: "∂",
    name: "Partial Differential",
    tags: "math partial derivative differential curly d",
  },
  {
    char: "∝",
    name: "Proportional To",
    tags: "math proportional prop infinite",
  },
  { char: "∠", name: "Angle", tags: "math angle geometry" },
  { char: "∥", name: "Parallel To", tags: "math parallel lines geometry" },
  {
    char: "∴",
    name: "Therefore",
    tags: "math therefore dots logic because three",
  },
  {
    char: "∵",
    name: "Because",
    tags: "math because dots logic therefore upside down",
  },
  { char: "ƒ", name: "Function", tags: "math function f hook" },
  { char: "µ", name: "Micro", tags: "math micro mu greek" },

  // Arrows & Punctuation
  { char: "→", name: "Rightwards Arrow", tags: "arrow right pointer" },
  { char: "←", name: "Leftwards Arrow", tags: "arrow left pointer back" },
  { char: "↑", name: "Upwards Arrow", tags: "arrow up pointer" },
  { char: "↓", name: "Downwards Arrow", tags: "arrow down pointer" },
  { char: "↔", name: "Left Right Arrow", tags: "arrow left right horizontal" },
  { char: "↪", name: "Rightwards Hook Arrow", tags: "arrow right hook return" },
  {
    char: "↩",
    name: "Leftwards Hook Arrow",
    tags: "arrow left hook return enter",
  },
  {
    char: "⇒",
    name: "Rightwards Double Arrow",
    tags: "arrow right double implies",
  },
  {
    char: "⇐",
    name: "Leftwards Double Arrow",
    tags: "arrow left double implies",
  },
  {
    char: "«",
    name: "Left Angle Quote",
    tags: "punctuation quote guillemet left arrow",
  },
  {
    char: "»",
    name: "Right Angle Quote",
    tags: "punctuation quote guillemet right arrow",
  },
  {
    char: "¿",
    name: "Inverted Question Mark",
    tags: "punctuation question inverted spanish upside down",
  },
  {
    char: "¡",
    name: "Inverted Exclamation Mark",
    tags: "punctuation exclamation inverted spanish upside down",
  },
  {
    char: "‹",
    name: "Single Left Angle Quote",
    tags: "punctuation quote guillemet single left",
  },
  {
    char: "›",
    name: "Single Right Angle Quote",
    tags: "punctuation quote guillemet single right",
  },
  {
    char: "‘",
    name: "Left Single Quote",
    tags: "punctuation quote single left smart",
  },
  {
    char: "’",
    name: "Right Single Quote",
    tags: "punctuation quote single right smart apostrophe",
  },
  {
    char: "“",
    name: "Left Double Quote",
    tags: "punctuation quote double left smart",
  },
  {
    char: "”",
    name: "Right Double Quote",
    tags: "punctuation quote double right smart",
  },
  { char: "—", name: "Em Dash", tags: "punctuation dash em long" },
  { char: "–", name: "En Dash", tags: "punctuation dash en short" },
  { char: "…", name: "Ellipsis", tags: "punctuation ellipsis dots three" },
  { char: "†", name: "Dagger", tags: "punctuation dagger cross obelisk" },
  {
    char: "‡",
    name: "Double Dagger",
    tags: "punctuation dagger double diesis",
  },
  { char: "°", name: "Degree", tags: "punctuation degree temperature circle" },
  { char: "′", name: "Prime", tags: "punctuation prime minute feet" },
  {
    char: "″",
    name: "Double Prime",
    tags: "punctuation prime double minute second inches",
  },
  { char: "§", name: "Section", tags: "punctuation section legal s" },
  { char: "¶", name: "Pilcrow", tags: "punctuation paragraph pilcrow p" },

  // Language Specific
  { char: "ß", name: "Sharp S", tags: "language german sharp s eszett" },
  { char: "æ", name: "AE Ligature", tags: "language latin ae ligature" },
  {
    char: "Æ",
    name: "AE Ligature Uppercase",
    tags: "language latin ae ligature uppercase",
  },
  { char: "œ", name: "OE Ligature", tags: "language latin oe ligature" },
  {
    char: "Œ",
    name: "OE Ligature Uppercase",
    tags: "language latin oe ligature uppercase",
  },
  { char: "ø", name: "Slashed O", tags: "language norwegian danish o slash" },
  {
    char: "Ø",
    name: "Slashed O Uppercase",
    tags: "language norwegian danish o slash uppercase",
  },
  {
    char: "å",
    name: "A with Ring",
    tags: "language swedish norwegian danish a ring",
  },
  {
    char: "Å",
    name: "A with Ring Uppercase",
    tags: "language swedish norwegian danish a ring uppercase",
  },
  { char: "ç", name: "C with Cedilla", tags: "language french c cedilla" },
  {
    char: "Ç",
    name: "C with Cedilla Uppercase",
    tags: "language french c cedilla uppercase",
  },
  { char: "ñ", name: "N with Tilde", tags: "language spanish n tilde enye" },
  {
    char: "Ñ",
    name: "N with Tilde Uppercase",
    tags: "language spanish n tilde enye uppercase",
  },
  {
    char: "ü",
    name: "U with Umlaut",
    tags: "language german u umlaut diaeresis",
  },
  {
    char: "Ü",
    name: "U with Umlaut Uppercase",
    tags: "language german u umlaut diaeresis uppercase",
  },
  { char: "é", name: "E with Acute", tags: "language french e acute accent" },
  {
    char: "É",
    name: "E with Acute Uppercase",
    tags: "language french e acute accent uppercase",
  },
  { char: "è", name: "E with Grave", tags: "language french e grave accent" },
  {
    char: "È",
    name: "E with Grave Uppercase",
    tags: "language french e grave accent uppercase",
  },
  {
    char: "ê",
    name: "E with Circumflex",
    tags: "language french e circumflex hat",
  },
  {
    char: "ë",
    name: "E with Umlaut",
    tags: "language french e umlaut diaeresis",
  },
  { char: "ł", name: "L with Stroke", tags: "language polish l stroke slash" },
  {
    char: "Ł",
    name: "L with Stroke Uppercase",
    tags: "language polish l stroke slash uppercase",
  },
  { char: "þ", name: "Thorn", tags: "language icelandic thorn th" },
  {
    char: "Þ",
    name: "Thorn Uppercase",
    tags: "language icelandic thorn th uppercase",
  },
  { char: "ð", name: "Eth", tags: "language icelandic eth edh" },
  {
    char: "Ð",
    name: "Eth Uppercase",
    tags: "language icelandic eth edh uppercase",
  },

  // IPA / Phonetic
  {
    char: "ə",
    name: "Schwa",
    tags: "language ipa phonetic schwa upside down e",
  },
  { char: "ɛ", name: "Open E", tags: "language ipa phonetic epsilon open e" },
  { char: "ʃ", name: "Esh", tags: "language ipa phonetic esh hook" },
  { char: "ʒ", name: "Ezh", tags: "language ipa phonetic ezh yogh" },
  {
    char: "ʔ",
    name: "Glottal Stop",
    tags: "language ipa phonetic glottal stop question mark",
  },
  {
    char: "ʕ",
    name: "Voiced Pharyngeal Fricative",
    tags: "language ipa phonetic pharyngeal fricative hook",
  },
  { char: "ɔ", name: "Open O", tags: "language ipa phonetic open o" },
  { char: "ʌ", name: "Open V", tags: "language ipa phonetic turned v" },
  { char: "ɪ", name: "Small Capital I", tags: "language ipa phonetic small i" },
  { char: "ɣ", name: "Gamma", tags: "language ipa phonetic gamma g" },
  {
    char: "∀",
    name: "For All",
    tags: "math logic universal quantifier forall all inverted A",
  },
  {
    char: "∃",
    name: "There Exists",
    tags: "math logic existential quantifier exists inverted E",
  },
  { char: "¬", name: "Not", tags: "math logic negation not tilde" },
  { char: "∩", name: "Intersection", tags: "math set intersection cap" },
  { char: "∪", name: "Union", tags: "math set union cup" },
  { char: "⊂", name: "Subset", tags: "math set subset contained" },
  { char: "⊃", name: "Superset", tags: "math set superset contains" },
  {
    char: "⊆",
    name: "Subset or Equal",
    tags: "math set subset equal contained",
  },
  {
    char: "⊇",
    name: "Superset or Equal",
    tags: "math set superset equal contains",
  },
  { char: "∈", name: "Element Of", tags: "math set element member in" },
  { char: "∉", name: "Not Element Of", tags: "math set element not member" },
  { char: "∅", name: "Empty Set", tags: "math set null empty zero slash" },
  {
    char: "≡",
    name: "Identical To",
    tags: "math equivalent identical equal triple",
  },
  { char: "∼", name: "Tilde Operator", tags: "math tilde similar" },
  { char: "≅", name: "Congruent", tags: "math congruent equal tilde" },
  {
    char: "⟨",
    name: "Left Angle Bracket",
    tags: "math bracket angle left langle",
  },
  {
    char: "⟩",
    name: "Right Angle Bracket",
    tags: "math bracket angle right rangle",
  },
  { char: "⌈", name: "Left Ceiling", tags: "math ceiling bracket left" },
  { char: "⌉", name: "Right Ceiling", tags: "math ceiling bracket right" },
  { char: "⌊", name: "Left Floor", tags: "math floor bracket left" },
  { char: "⌋", name: "Right Floor", tags: "math floor bracket right" },
  { char: "α", name: "Alpha", tags: "greek letter alpha math angle" },
  { char: "β", name: "Beta", tags: "greek letter beta math" },
  { char: "γ", name: "Gamma", tags: "greek letter gamma math radiation" },
  { char: "δ", name: "Delta", tags: "greek letter delta math change" },
  { char: "ε", name: "Epsilon", tags: "greek letter epsilon math small" },
  { char: "ζ", name: "Zeta", tags: "greek letter zeta math" },
  { char: "η", name: "Eta", tags: "greek letter eta math" },
  { char: "θ", name: "Theta", tags: "greek letter theta math angle" },
  { char: "ι", name: "Iota", tags: "greek letter iota math" },
  { char: "κ", name: "Kappa", tags: "greek letter kappa math" },
  {
    char: "λ",
    name: "Lambda",
    tags: "greek letter lambda math function wavelength",
  },
  { char: "μ", name: "Mu", tags: "greek letter mu math micro prefix" },
  { char: "ν", name: "Nu", tags: "greek letter nu math" },
  { char: "ξ", name: "Xi", tags: "greek letter xi math" },
  { char: "ο", name: "Omicron", tags: "greek letter omicron math" },
  { char: "π", name: "Pi", tags: "greek letter pi math 3.14" },
  { char: "ρ", name: "Rho", tags: "greek letter rho math density" },
  {
    char: "σ",
    name: "Sigma",
    tags: "greek letter sigma math sum standard deviation",
  },
  {
    char: "τ",
    name: "Tau",
    tags: "greek letter tau math time constant torque",
  },
  { char: "υ", name: "Upsilon", tags: "greek letter upsilon math" },
  { char: "φ", name: "Phi", tags: "greek letter phi math golden ratio angle" },
  { char: "χ", name: "Chi", tags: "greek letter chi math distribution" },
  { char: "ψ", name: "Psi", tags: "greek letter psi math quantum" },
  {
    char: "ω",
    name: "Omega",
    tags: "greek letter omega math angular velocity ohm last",
  },
  {
    char: "Γ",
    name: "Capital Gamma",
    tags: "greek capital letter gamma math function",
  },
  {
    char: "Δ",
    name: "Capital Delta",
    tags: "greek capital letter delta math change triangle",
  },
  { char: "Θ", name: "Capital Theta", tags: "greek capital letter theta math" },
  {
    char: "Λ",
    name: "Capital Lambda",
    tags: "greek capital letter lambda math",
  },
  { char: "Ξ", name: "Capital Xi", tags: "greek capital letter xi math" },
  {
    char: "Π",
    name: "Capital Pi",
    tags: "greek capital letter pi math product",
  },
  {
    char: "Σ",
    name: "Capital Sigma",
    tags: "greek capital letter sigma math sum",
  },
  { char: "Φ", name: "Capital Phi", tags: "greek capital letter phi math" },
  { char: "Ψ", name: "Capital Psi", tags: "greek capital letter psi math" },
  {
    char: "Ω",
    name: "Capital Omega",
    tags: "greek capital letter omega math ohm resistance",
  },
  {
    char: "⇄",
    name: "Rightwards Arrow Over Leftwards",
    tags: "arrow left right double swap",
  },
  {
    char: "⇅",
    name: "Upwards Arrow Leftwards Of Downwards",
    tags: "arrow up down double swap",
  },
  {
    char: "↦",
    name: "Rightwards Arrow From Bar",
    tags: "arrow right maps to bar function",
  },
  {
    char: "↠",
    name: "Rightwards Two Headed Arrow",
    tags: "arrow right two headed double",
  },
  {
    char: "↣",
    name: "Rightwards Arrow With Tail",
    tags: "arrow right tail maps to",
  },
  {
    char: "⇉",
    name: "Rightwards Paired Arrows",
    tags: "arrow right paired double fast",
  },
  {
    char: "⇝",
    name: "Rightwards Squiggle Arrow",
    tags: "arrow right squiggle wave",
  },
  {
    char: "⟶",
    name: "Long Rightwards Arrow",
    tags: "arrow right long implies",
  },
  {
    char: "⟵",
    name: "Long Leftwards Arrow",
    tags: "arrow left long implied by",
  },
  {
    char: "⟷",
    name: "Long Left Right Arrow",
    tags: "arrow left right long iff",
  },
  {
    char: "⤴",
    name: "Arrow Pointing Rightwards Then Curving Upwards",
    tags: "arrow right curve up",
  },
  {
    char: "⤵",
    name: "Arrow Pointing Rightwards Then Curving Downwards",
    tags: "arrow right curve down",
  },
  { char: "€", name: "Euro", tags: "currency euro money e" },
  { char: "£", name: "Pound", tags: "currency pound british money lira" },
  { char: "¥", name: "Yen", tags: "currency yen yuan japanese chinese money" },
  { char: "₹", name: "Indian Rupee", tags: "currency indian rupee money" },
  { char: "₩", name: "Won", tags: "currency korean won money" },
  { char: "₽", name: "Ruble", tags: "currency russian ruble money" },
  { char: "₺", name: "Turkish Lira", tags: "currency turkish lira money" },
  { char: "₴", name: "Hryvnia", tags: "currency ukrainian hryvnia money" },
  { char: "₿", name: "Bitcoin", tags: "currency bitcoin crypto money" },
  { char: "¢", name: "Cent", tags: "currency cent money c" },
  { char: "₵", name: "Cedi", tags: "currency ghanaian cedi money" },
  { char: "₡", name: "Colon", tags: "currency costa rican colon money" },
  { char: "₫", name: "Dong", tags: "currency vietnamese dong money" },
  { char: "₱", name: "Peso", tags: "currency philippine mexican peso money" },
  { char: "₲", name: "Guarani", tags: "currency paraguayan guarani money" },
  { char: "₸", name: "Tenge", tags: "currency kazakhstani tenge money" },
  { char: "₼", name: "Manat", tags: "currency azerbaijani manat money" },
  { char: "©", name: "Copyright", tags: "typography copyright c law" },
  {
    char: "®",
    name: "Registered",
    tags: "typography registered r trademark law",
  },
  { char: "™", name: "Trademark", tags: "typography trademark tm law" },
  {
    char: "℗",
    name: "Sound Recording Copyright",
    tags: "typography copyright sound recording p music",
  },
  { char: "℠", name: "Service Mark", tags: "typography service mark sm law" },
  { char: "№", name: "Numero", tags: "punctuation number numero" },
  {
    char: "‼",
    name: "Double Exclamation",
    tags: "punctuation exclamation double bang",
  },
  { char: "⁇", name: "Double Question", tags: "punctuation question double" },
  {
    char: "⁈",
    name: "Question Exclamation",
    tags: "punctuation question exclamation interrobang",
  },
  {
    char: "⁉",
    name: "Exclamation Question",
    tags: "punctuation exclamation question",
  },
  {
    char: "‗",
    name: "Double Low Line",
    tags: "punctuation underscore double low line",
  },
  {
    char: "⁂",
    name: "Asterism",
    tags: "punctuation asterism three asterisks dots",
  },
  { char: "⸻", name: "Three Em Dash", tags: "punctuation dash long three em" },
  {
    char: "❡",
    name: "Reversed Pilcrow",
    tags: "punctuation paragraph reversed pilcrow",
  },
  {
    char: "⸘",
    name: "Inverted Interrobang",
    tags: "punctuation inverted interrobang question exclamation spanish",
  },
  {
    char: "⌘",
    name: "Command",
    tags: "technical mac apple command loop cloverleaf",
  },
  { char: "⌥", name: "Option", tags: "technical mac apple option alt" },
  { char: "⇪", name: "Caps Lock", tags: "technical keyboard caps lock arrow" },
  {
    char: "⌫",
    name: "Erase to Left",
    tags: "technical keyboard backspace erase left",
  },
  {
    char: "⌦",
    name: "Erase to Right",
    tags: "technical keyboard delete erase right",
  },
  { char: "⎋", name: "Escape", tags: "technical keyboard escape esc" },
  { char: "⏎", name: "Return", tags: "technical keyboard return enter" },
  {
    char: "␣",
    name: "Open Space",
    tags: "technical space character symbol blank",
  },
  { char: "␀", name: "Null", tags: "technical null character symbol control" },
  { char: "↹", name: "Tab", tags: "technical keyboard tab arrows" },
  { char: "⇥", name: "Right Tab", tags: "technical keyboard tab right" },
  { char: "⇤", name: "Left Tab", tags: "technical keyboard tab left" },
  { char: "✓", name: "Check Mark", tags: "symbol check mark tick yes" },
  {
    char: "✔",
    name: "Heavy Check Mark",
    tags: "symbol check mark heavy tick yes",
  },
  { char: "✗", name: "Ballot X", tags: "symbol x mark cross no" },
  { char: "✘", name: "Heavy Ballot X", tags: "symbol x mark heavy cross no" },
  { char: "★", name: "Black Star", tags: "symbol star black filled" },
  { char: "☆", name: "White Star", tags: "symbol star white empty" },
  {
    char: "✦",
    name: "Black Four Pointed Star",
    tags: "symbol star black four point",
  },
  {
    char: "✧",
    name: "White Four Pointed Star",
    tags: "symbol star white four point",
  },
  { char: "✪", name: "Circled White Star", tags: "symbol star white circled" },
  {
    char: "⚝",
    name: "Outlined White Star",
    tags: "symbol star white outlined",
  },
  { char: "⁎", name: "Low Asterisk", tags: "symbol asterisk star low" },
  {
    char: "⁕",
    name: "Flower Punctuation Mark",
    tags: "symbol flower punctuation asterisk",
  },
  { char: "♠", name: "Spade", tags: "symbol card game spade black" },
  { char: "♥", name: "Heart", tags: "symbol card game heart love black" },
  { char: "♦", name: "Diamond", tags: "symbol card game diamond black" },
  { char: "♣", name: "Club", tags: "symbol card game club clover black" },
  { char: "♪", name: "Eighth Note", tags: "music note eighth single" },
  {
    char: "♫",
    name: "Beamed Eighth Notes",
    tags: "music note eighth double beam",
  },
  {
    char: "♬",
    name: "Beamed Sixteenth Notes",
    tags: "music note sixteenth double beam",
  },
  { char: "♭", name: "Flat", tags: "music note flat b" },
  { char: "♮", name: "Natural", tags: "music note natural" },
  { char: "♯", name: "Sharp", tags: "music note sharp hash" },
  { char: "Ж", name: "Zhe", tags: "cyrillic russian zhe zh" },
  { char: "Я", name: "Ya", tags: "cyrillic russian ya backwards r" },
  { char: "Ѓ", name: "Gje", tags: "macedonian cyrillic gje g accent" },
  { char: "Ќ", name: "Kje", tags: "macedonian cyrillic kje k accent" },
  { char: "Џ", name: "Dzhe", tags: "serbian macedonian cyrillic dzhe" },
  { char: "Ә", name: "Schwa Cyrillic", tags: "kazakh cyrillic schwa" },
  { char: "Ғ", name: "Ghayn", tags: "kazakh uzbek cyrillic ghayn g stroke" },
].map((s, i) => ({ ...s, id: `sym-${i}` })); // Assign stable unique IDs

function send(frame) {
  process.stdout.write(JSON.stringify(frame) + "\n");
}

function log(...a) {
  console.error(...a);
} // debug -> stderr

function render(rev, text) {
  const query = (text || "").toLowerCase().trim();
  let results = symbols;

  if (query) {
    results = symbols.filter(
      (s) =>
        s.name.toLowerCase().includes(query) ||
        s.tags.toLowerCase().includes(query) ||
        s.char.includes(query),
    );
  }

  const items = results.map((s) => ({
    id: s.id,
    title: `${s.char}  ${s.name}`,
    subtitle: s.tags,
    icon: "tag",
    actions: [{ id: "default", title: "Copy", icon: "copy" }],
  }));

  send({
    type: "render",
    rev: rev,
    view: "list",
    placeholder: "Search characters (e.g., dot, arrow, pi, spanish)...",
    emptyText: `No characters found for "${query}"`,
    items: items,
  });
}

function handleAction(id, action) {
  const sym = symbols.find((s) => s.id === id);
  if (sym) {
    // Ask Tabame to copy the character to the clipboard
    send({ type: "command", command: "copy", text: sym.char });
    // Ask Tabame to hide the launcher (which also gracefully closes the plugin)
    send({ type: "command", command: "hide" });
  }
}

let buf = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buf += chunk;
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      continue;
    }

    if (msg.type === "close") process.exit(0);
    else if (msg.type === "init" || msg.type === "query") {
      render(msg.rev || 0, msg.text != null ? msg.text : msg.query || "");
    } else if (msg.type === "action") {
      handleAction(msg.id || "", msg.action || "default");
    }
  }
});
process.stdin.on("end", () => process.exit(0));
