

export const index = 0;
let component_cache;
export const component = async () => component_cache ??= (await import('../entries/pages/_layout.svelte.js')).default;
export const universal = {
  "prerender": false,
  "ssr": false,
  "trailingSlash": "always"
};
export const universal_id = "src/routes/+layout.js";
export const imports = ["_app/immutable/nodes/0.DQpLoUVB.js","_app/immutable/chunks/DJc2-CAY.js","_app/immutable/chunks/wYhilH5O.js","_app/immutable/chunks/ByWJFpS2.js","_app/immutable/chunks/B0xLTQC2.js","_app/immutable/chunks/DK76alUJ.js","_app/immutable/chunks/Bq3iEQjV.js","_app/immutable/chunks/DY_PTQZo.js","_app/immutable/chunks/BKuqSeVd.js","_app/immutable/chunks/BhCUie3Y.js","_app/immutable/chunks/CR0eax9s.js","_app/immutable/chunks/COY8JwtF.js"];
export const stylesheets = ["_app/immutable/assets/0.Ba7CdXxy.css"];
export const fonts = [];
