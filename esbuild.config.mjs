import * as esbuild from "esbuild";

const options = {
  entryPoints: {
    application: "app/javascript/application.js",
    lesson_math: "app/javascript/lesson_blocks/math.js",
    lesson_diagram: "app/javascript/lesson_blocks/diagram.js",
  },
  bundle: true,
  format: "esm",
  splitting: true,
  chunkNames: "[name]-[hash].digested",
  platform: "browser",
  target: ["es2022"],
  outdir: "app/assets/builds",
  publicPath: "/assets",
  loader: { ".woff2": "file", ".woff": "file", ".ttf": "file" },
  assetNames: "[name]-[hash].digested",
  minify: process.env.NODE_ENV === "production",
  sourcemap: process.env.NODE_ENV === "production" ? false : "linked",
  logLevel: "info",
};

if (process.argv.includes("--watch")) {
  const context = await esbuild.context(options);
  await context.watch();
} else {
  await esbuild.build(options);
}
