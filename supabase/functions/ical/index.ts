// Haalt een Rentman iCal-agenda op namens de ingelogde gebruiker.
// Nodig voor de webversie: de browser mag de agenda niet zelf ophalen (CORS).
// Alleen ingelogde gebruikers (geldige JWT) kunnen deze functie aanroepen.

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const { url } = await req.json();
    if (typeof url !== 'string') throw new Error('url ontbreekt');
    const target = url.trim().replace(/^webcal:\/\//i, 'https://');
    const parsed = new URL(target);
    if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
      throw new Error('Alleen http(s)-links');
    }
    const res = await fetch(parsed, { headers: { 'User-Agent': 'EventFriend' } });
    const text = await res.text();
    if (!res.ok) {
      return new Response(`Agenda-server gaf status ${res.status}`, { status: 502, headers: cors });
    }
    if (!text.includes('BEGIN:VCALENDAR')) {
      return new Response('Dit lijkt geen iCal-agenda te zijn', { status: 422, headers: cors });
    }
    return new Response(text, {
      headers: { ...cors, 'Content-Type': 'text/plain; charset=utf-8' },
    });
  } catch (e) {
    return new Response(String(e instanceof Error ? e.message : e), { status: 400, headers: cors });
  }
});
