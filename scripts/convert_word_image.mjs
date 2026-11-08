import sharp from "sharp";

const [inputPath, outputPath] = process.argv.slice(2);

if (!inputPath || !outputPath) {
  console.error("Usage: node convert_word_image.mjs <input> <output>");
  process.exit(2);
}

await sharp(inputPath, { pages: 1 })
  .rotate()
  .png({ compressionLevel: 9 })
  .toFile(outputPath);
