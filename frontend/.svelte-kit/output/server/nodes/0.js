

export const index = 0;
let component_cache;
export const component = async () => component_cache ??= (await import('../entries/pages/_layout.svelte.js')).default;
export const universal = {
  "prerender": false,
  "ssr": false,
  "trailingSlash": "always"
};
export const universal_id = "src/routes/+layout.js";
export const imports = ["_app/immutable/nodes/0.3Ycdq4CI.js","_app/immutable/chunks/BEnCpAxF.js","_app/immutable/chunks/CWHxxP7T.js","_app/immutable/chunks/B-qVnNdr.js","_app/immutable/chunks/CVIdiGTY.js","_app/immutable/chunks/Cp4tK-LL.js","_app/immutable/chunks/rtlt21_5.js","_app/immutable/chunks/DG99Qqj_.js","_app/immutable/chunks/Yaqbs_um.js","_app/immutable/chunks/DBmGnoXY.js","_app/immutable/chunks/9gnaBVc_.js"];
export const stylesheets = ["_app/immutable/assets/0.BYlcRFK4.css"];
export const fonts = [];
