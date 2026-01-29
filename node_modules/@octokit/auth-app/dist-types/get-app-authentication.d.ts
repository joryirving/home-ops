import type { AppAuthentication, State } from "./types.js";
export declare function getAppAuthentication({ appId, privateKey, timeDifference, createJwt, }: State & {
    timeDifference?: number | undefined;
}): Promise<AppAuthentication>;
