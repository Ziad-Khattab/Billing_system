

export const index = 0;
let component_cache;
export const component = async () => component_cache ??= (await import('../entries/pages/_layout.svelte.js')).default;
export const universal = {
  "prerender": false,
  "ssr": false,
  "trailingSlash": "always"
};
export const universal_id = "src/routes/+layout.js";
export const imports = ["_app/immutable/nodes/0.D0ja55a1.js","_app/immutable/chunks/C5ujjk74.js","_app/immutable/chunks/87bIvZSd.js","_app/immutable/chunks/D46fgPKJ.js","_app/immutable/chunks/DJBmNonr.js","_app/immutable/chunks/RAoeSuPI.js","_app/immutable/chunks/CB6WrZVh.js","_app/immutable/chunks/DRJs6kCy.js","_app/immutable/chunks/I1f-VoRA.js","_app/immutable/chunks/BnS-mJsP.js","_app/immutable/chunks/CVvJ1TDU.js"];
export const stylesheets = ["_app/immutable/assets/0.DaEXVyo5.css"];
export const fonts = [];
