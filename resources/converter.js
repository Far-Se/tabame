// save as filter-emojis.js
// Usage: node filter-emojis.js input.json output.json

const fs = require("fs");

const inputFile = process.argv[2] || "emoji.json";
const outputFile = process.argv[3] || "emoji_new.json";

try {
  // Read input file
  const rawData = fs.readFileSync(inputFile, "utf8");
  const jsonData = JSON.parse(rawData);

  if (!Array.isArray(jsonData)) {
    throw new Error("Input JSON must be an array");
  }

  // Filter and transform data
  const filteredData = jsonData.map((item) => {
    const result = {
      u: item.unified,
      c: item.category,
      sc: item.subcategory,
      n: item.name,
      sn: item.short_name,
      so: item.sort_order,
    };

    // Extract skin variation unified values
    if (item.skin_variations && typeof item.skin_variations === "object") {
      result.sk = Object.values(item.skin_variations)
        .map((variation) => variation.unified)
        .filter(Boolean);
    }

    return result;
  });

  // Save output
  fs.writeFileSync(outputFile, JSON.stringify(filteredData), "utf8");

  console.log(`Filtered JSON saved to ${outputFile}`);
} catch (err) {
  console.error("Error:", err.message);
}
