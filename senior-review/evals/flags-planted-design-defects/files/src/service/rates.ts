export interface RateProvider { name: string; fetch(from: string, to: string): Promise<number>; }

export async function fetchRate(providers: RateProvider[], from: string, to: string): Promise<number> {
  for (const p of providers) {
    try {
      return await p.fetch(from, to);
    } catch (e) {
      console.log("provider failed", p.name);
    }
  }
  return 0;
}
