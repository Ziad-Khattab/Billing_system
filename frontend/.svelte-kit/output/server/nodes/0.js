

export const index = 0;
let component_cache;
export const component = async () => component_cache ??= (await import('../entries/pages/_layout.svelte.js')).default;
export const universal = {
  "prerender": false,
  "ssr": false,
  "trailingSlash": "always"
};
export const universal_id = "src/routes/+layout.js";
export const imports = ["_app/immutable/nodes/0.D6lBFTmi.js","_app/immutable/chunks/Cng9lrDC.js","_app/immutable/chunks/CafSqgsp.js","_app/immutable/chunks/CJWuDs3g.js","_app/immutable/chunks/CEqC-9dc.js","_app/immutable/chunks/XeH-lC1-.js","_app/immutable/chunks/CXbl8UwR.js","_app/immutable/chunks/9oG6dCtG.js","_app/immutable/chunks/BKuqSeVd.js","_app/immutable/chunks/2DZDIbpT.js","_app/immutable/chunks/a0sD2_6o.js","_app/immutable/chunks/DOI6MEZn.js"];
export const stylesheets = ["_app/immutable/assets/0.Ba7CdXxy.css"];
export const fonts = [];
