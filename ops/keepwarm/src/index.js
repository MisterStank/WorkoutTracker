// Hits the Render API's /healthz every 10 minutes (see cron in wrangler.jsonc)
// so the free-tier instance stays awake and users never wait ~50s for a cold
// start.
//
// Deliberately /healthz only — no database query. Neon is left to scale to
// zero: its resume is ~0.5s (vs Render's ~50s) and keeping it warm 24/7 would
// blow the free 100 CU-hour/month budget in ~2 weeks.
const TARGET = "https://workouttracker-api-pe1p.onrender.com/healthz";

export default {
  async scheduled(_event, _env, ctx) {
    ctx.waitUntil(fetch(TARGET).catch(() => {}));
  },
};
