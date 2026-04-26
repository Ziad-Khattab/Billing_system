

export const index = 0;
let component_cache;
export const component = async () => component_cache ??= (await import('../entries/pages/_layout.svelte.js')).default;
export const universal = {
  "prerender": false,
  "ssr": false,
  "trailingSlash": "always"
};
export const universal_id = "src/routes/+layout.js";
export const imports = ["_app/immutable/nodes/0.DaAqiMYD.js","_app/immutable/chunks/BFd6ASy-.js","_app/immutable/chunks/0ZUd9Tt2.js","_app/immutable/chunks/rnO5xDFN.js","_app/immutable/chunks/BMuHSHd6.js","_app/immutable/chunks/CB_n9g6T.js","_app/immutable/chunks/CLgMX-D9.js","_app/immutable/chunks/Tuw6h4fL.js","_app/immutable/chunks/DQN_FATh.js","_app/immutable/chunks/Cna-0EbY.js","_app/immutable/chunks/B3GpPDC8.js"];
export const stylesheets = ["_app/immutable/assets/0.DL_Ug_Vt.css"];
export const fonts = [];
