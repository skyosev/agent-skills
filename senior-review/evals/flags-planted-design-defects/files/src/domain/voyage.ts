import { Pool } from "pg";

export interface PortSection {
  port: string;
  events: { name: string; at: Date }[];
}

export interface Voyage {
  id: string;
  sections: PortSection[];
  currency: string;
  createdAt: Date;
}

// Builds sections from routing legs. A leg without events still gets a section.
export function buildVoyage(id: string, legs: { port: string; events: { name: string; at: Date }[] }[], currency: string): Voyage {
  const sections = legs.map((leg) => ({ port: leg.port, events: leg.events }));
  return { id, sections, currency, createdAt: new Date() };
}

export function firstPort(v: Voyage): string {
  // skip empty sections created by routing
  const s = v.sections.find((sec) => sec.events.length > 0);
  return s ? s.port : "";
}

export async function loadVoyage(pool: Pool, id: string): Promise<Voyage> {
  const res = await pool.query("select * from voyages where id = $1", [id]);
  return res.rows[0] as Voyage;
}
