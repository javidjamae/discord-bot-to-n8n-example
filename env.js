export function checkRequiredEnv(env) {
  const missing = [];
  if (!env.DISCORD_TOKEN) missing.push('DISCORD_TOKEN');
  if (!env.APPLICATION_ID) missing.push('APPLICATION_ID');
  if (!env.N8N_WEBHOOK_URL) missing.push('N8N_WEBHOOK_URL');
  return missing;
}
