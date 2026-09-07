import { readdir, rename, stat, unlink } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const root = path.resolve("public/assets/articles");
const optimizeAboveBytes = 20 * 1024 * 1024;
const cloudflareLimitBytes = 25 * 1024 * 1024;
const supportedExtensions = new Set([".jpg", ".jpeg", ".png", ".webp"]);

const walk = async (directory) => {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(
    entries.map((entry) => {
      const fullPath = path.join(directory, entry.name);
      return entry.isDirectory() ? walk(fullPath) : [fullPath];
    })
  );
  return nested.flat();
};

const encode = (pipeline, extension) => {
  if (extension === ".png") {
    return pipeline.png({ compressionLevel: 9, palette: true, quality: 90 });
  }
  if (extension === ".webp") return pipeline.webp({ quality: 86, effort: 6 });
  return pipeline.jpeg({ quality: 88, mozjpeg: true });
};

const optimize = async (filePath) => {
  const extension = path.extname(filePath).toLowerCase();
  const originalSize = (await stat(filePath)).size;
  if (!supportedExtensions.has(extension) || originalSize <= optimizeAboveBytes) return null;

  const temporaryPath = `${filePath}.optimized`;
  let optimizedSize = originalSize;
  try {
    for (const maxDimension of [2400, 2000, 1600, 1200]) {
      const pipeline = sharp(filePath)
        .rotate()
        .resize({
          width: maxDimension,
          height: maxDimension,
          fit: "inside",
          withoutEnlargement: true
        });
      await encode(pipeline, extension).toFile(temporaryPath);
      optimizedSize = (await stat(temporaryPath)).size;
      if (optimizedSize <= optimizeAboveBytes) break;
      await unlink(temporaryPath);
    }

    if (optimizedSize >= originalSize || optimizedSize >= cloudflareLimitBytes) {
      throw new Error(
        `Unable to reduce ${path.relative(root, filePath)} below the Cloudflare Pages file limit.`
      );
    }

    await unlink(filePath);
    await rename(temporaryPath, filePath);
    return { filePath, originalSize, optimizedSize };
  } catch (error) {
    await unlink(temporaryPath).catch(() => {});
    throw error;
  }
};

const files = await walk(root);
const results = (await Promise.all(files.map(optimize))).filter(Boolean);

if (!results.length) {
  console.log("No oversized article images needed optimization.");
} else {
  for (const result of results) {
    console.log(
      `Optimized ${path.relative(root, result.filePath)}: ` +
        `${(result.originalSize / 1024 / 1024).toFixed(1)} MiB -> ` +
        `${(result.optimizedSize / 1024 / 1024).toFixed(1)} MiB`
    );
  }
}
