import * as esbuild from "esbuild";

const options = {
  entryPoints: ["app/javascript/application.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  target: ["es2022"],
  outdir: "app/assets/builds",
  publicPath: "/assets",
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
