

export const index = 0;
let component_cache;
export const component = async () => component_cache ??= (await import('../entries/pages/_layout.svelte.js')).default;
export const universal = {
  "prerender": false,
  "ssr": false,
  "trailingSlash": "always"
};
export const universal_id = "src/routes/+layout.js";
export const imports = ["_app/immutable/nodes/0.BUQX1oAF.js","_app/immutable/chunks/DCFHxH7p.js","_app/immutable/chunks/Cfmyk3fP.js","_app/immutable/chunks/kbp9nX7q.js","_app/immutable/chunks/MzNe-riY.js","_app/immutable/chunks/PXEY3gE8.js","_app/immutable/chunks/BJkl5pb7.js","_app/immutable/chunks/lv7HgJ88.js","_app/immutable/chunks/DcFVeYv9.js","_app/immutable/chunks/2qczH55V.js","_app/immutable/chunks/cW8nfSSB.js"];
export const stylesheets = ["_app/immutable/assets/0.ByyRAiBv.css"];
export const fonts = [];
