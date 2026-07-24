export interface Config {
  port: number;
  databaseUrl: string;
  redisUrl: string;
  tokenKek: Buffer;
  appleAudience: string;
}

export function loadConfig(env = process.env): Config {
  const required = ["DATABASE_URL", "REDIS_URL", "TOKEN_KEK_BASE64", "APPLE_AUDIENCE"] as const;
  for (const key of required) {
    if (!env[key]) throw new Error(`Missing required environment variable: ${key}`);
  }
  const tokenKek = Buffer.from(env.TOKEN_KEK_BASE64!, "base64");
  if (tokenKek.length !== 32) throw new Error("TOKEN_KEK_BASE64 must decode to 32 bytes");
  return {
    port: Number(env.PORT ?? 3000),
    databaseUrl: env.DATABASE_URL!,
    redisUrl: env.REDIS_URL!,
    tokenKek,
    appleAudience: env.APPLE_AUDIENCE!
  };
}
