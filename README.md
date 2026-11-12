# EventFriend

De werkapp voor de freelance event technicus. Android-app (APK) en webversie uit één codebase (Flutter).

## Wat zit erin

| Tab | Inhoud |
|---|---|
| **Vandaag** | Klus van vandaag uit Rentman: tijden, locatie met route, bellen, in-/uitklokken |
| **Klussen** | Komende en afgelopen klussen uit al je Rentman-agenda's (+ eigen klussen), per klus notities, foto's en PDF-export |
| **Uren** | In-/uitklokken, pauze, kilometers, overzicht per week |
| **Notities** | Alle notities, doorzoekbaar, los of gekoppeld aan een klus |
| **Tools** | Offline calculators, elk met uitklapbare uitleg "Zo is het berekend" |

**Calculators:** LED-wall, beeld schalen, projectie, opname/bitrate, bridle (op hoek of op apex-diepte), truss-puntlast, vermogen ↔ stroom, spanningsval en kabel, delay, dB optellen en afstand, DMX-adressen, DIP-switch.

## Rentman koppelen

Als crewlid krijg je per opdrachtgever een iCal-link (agenda-synchronisatie). Voeg die toe via **Klussen → +** of het tandwiel rechtsboven. Je kunt op elk moment nieuwe agenda's toevoegen.

## Installeren

- **Android:** download `EventFriend.apk` van de nieuwste [release](../../releases/latest) en open hem op je telefoon (sta "installeren uit onbekende bron" toe).
- **Web:** zie de link in de release. Na het eerste bezoek werkt de webversie ook offline.

## Bouwen

Elke push naar `main` draait de tests, bouwt de APK (als release) en zet de webversie op GitHub Pages. Zie `.github/workflows/build.yml`.

Lokaal:

```bash
flutter test
flutter run
```

## Nog niet gedaan

- Synchronisatie tussen telefoon en webversie (account met online opslag). Nu bewaart elk apparaat zijn eigen gegevens.
- In de webversie kan de Rentman-agenda niet direct worden opgehaald (de browser blokkeert dat); daarvoor komt een kleine server-koppeling.
