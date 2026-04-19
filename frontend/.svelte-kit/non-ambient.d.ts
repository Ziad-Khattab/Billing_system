
// this file is generated — do not edit it


declare module "svelte/elements" {
	export interface HTMLAttributes<T> {
		'data-sveltekit-keepfocus'?: true | '' | 'off' | undefined | null;
		'data-sveltekit-noscroll'?: true | '' | 'off' | undefined | null;
		'data-sveltekit-preload-code'?:
			| true
			| ''
			| 'eager'
			| 'viewport'
			| 'hover'
			| 'tap'
			| 'off'
			| undefined
			| null;
		'data-sveltekit-preload-data'?: true | '' | 'hover' | 'tap' | 'off' | undefined | null;
		'data-sveltekit-reload'?: true | '' | 'off' | undefined | null;
		'data-sveltekit-replacestate'?: true | '' | 'off' | undefined | null;
	}
}

export {};


declare module "$app/types" {
	type MatcherParam<M> = M extends (param : string) => param is (infer U extends string) ? U : string;

	export interface AppTypes {
		RouteId(): "/" | "/admin" | "/admin/billing" | "/admin/contracts" | "/admin/customers" | "/dashboard" | "/dashboard/contracts" | "/dashboard/invoices" | "/dashboard/profile" | "/login" | "/packages" | "/register";
		RouteParams(): {
			
		};
		LayoutParams(): {
			"/": Record<string, never>;
			"/admin": Record<string, never>;
			"/admin/billing": Record<string, never>;
			"/admin/contracts": Record<string, never>;
			"/admin/customers": Record<string, never>;
			"/dashboard": Record<string, never>;
			"/dashboard/contracts": Record<string, never>;
			"/dashboard/invoices": Record<string, never>;
			"/dashboard/profile": Record<string, never>;
			"/login": Record<string, never>;
			"/packages": Record<string, never>;
			"/register": Record<string, never>
		};
		Pathname(): "/" | "/admin" | "/admin/billing" | "/admin/contracts" | "/admin/customers" | "/dashboard" | "/dashboard/invoices" | "/dashboard/profile" | "/login" | "/packages" | "/register";
		ResolvedPathname(): `${"" | `/${string}`}${ReturnType<AppTypes['Pathname']>}`;
		Asset(): string & {};
	}
}