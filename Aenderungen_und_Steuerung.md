# Ragdoll Sandbox v3.0

Die Datei `RagdollSandbox_v3_0.rbxlx` in Roblox Studio öffnen. Sie enthält die ursprüngliche Spielwelt, 40 geänderte Skripte und fünf neue Module. Die Originaldatei bleibt unverändert. Es wurde nichts bei Roblox veröffentlicht und kein vorhandener Spielstand zurückgesetzt.

## Steuerung

| Aktion | Bedienung |
| --- | --- |
| Quickhack-Modus | **O** ein-/ausschalten, Spieler anvisieren |
| Quickhack auswählen | **Mausrad**; im Modus bleibt der Kameraabstand gleich |
| Ausgewählten Quickhack ausführen | **F** bei gültigem Ziel |
| Chip-Inventar | **K** |
| Bisheriger Admin-Zeitstopp | **I**; O gehört jetzt dem Quickhack-Modus |
| Freecam verschenken oder entziehen | **M → GIFTS → Spieler → FREECAM** |
| Geschenkte Freecam verwenden | **U**, WASD, E/Q, Shift/Ctrl, Mausrad, rechte Maustaste; H blendet HUD aus |
| Aufträge | **JOBS** oben rechts |
| Stillwater beschwören/weglegen | **SUMMON / DISMISS** nach abgeschlossener Stillwater-Quest |
| Eigene Admin-Psychose erleben | **M → ADMIN → MY PSYCHOSIS IMMUNITY: OFF** |
| Alle Fortschritte zurücksetzen | Als Spielbesitzer **M → ADMIN → WIPE ALL PROGRESS**, danach Bestätigungsklick |

Freecam-Geschenke werden im bestehenden Geschenk-Speicher gesichert. Entziehen beendet eine laufende Freecam sofort. Das Geschenk verleiht keine weiteren Adminrechte; der T-Teleport bleibt für Admins reserviert.

Der Schalter für die eigene Psychose wirkt zusätzlich zur serverweiten Cyberpsychose-Einstellung. Ist Cyberpsychose serverweit ausgeschaltet, bleibt sie ausgeschaltet.

## Änderungen

- Kamera-, Chip- und Computermodelle überarbeitet: zusätzliche Gehäusedetails, Bedienelemente und korrekte Linsenausrichtung. Chips auf 48 % verkleinert. Die fest platzierten Ripperdoc-Terminals stehen auf Arbeitsflächen mit Bodenstützen.
- Eigene Spielmenüs in Schwarz und Grautönen mit heller Schrift; neue Schrift, Klick- und Hover-Sounds. Computeraktionen geben Tonfeedback. Verkauf gewöhnlicher Chips zum Computer ergänzt; kostenlose Adminchips sind vom Weiterverkauf ausgeschlossen.
- Quickhacks funktionieren gegen Admins. Reichweite, Sichtkontakt, Abklingzeiten und vorhandene Firewalls werden weiterhin geprüft. Blackwall trifft ebenfalls Admins und hat neue Ringe, Datenfragmente, Bögen, Strahl und Schockwelle.
- Sandevistan verlangsamt Charaktere im Umkreis von 70 Studs. Der Abklingzustand bleibt beim Tod und Respawn im laufenden Server erhalten. Weltzeit und globale Schwerkraft bleiben bei diesem lokalen Effekt normal.
- Stillwater friert Charaktere im Umkreis von 42 Studs ein. Überlappende lokale Zeitstopps behalten eine gemeinsame Freigabezeit. Stillwater erscheint nicht automatisch am Avatar; Beschwören setzt die abgeschlossene Quest voraus.
- Krankenhaus-Replays: Bildschirmdarstellung über PlayerGui/Adornee korrigiert, gemeinsame Serverzeit und zeitlich passende Wiedergabe für später hinzukommende Zuschauer ergänzt.
- Drei bezahlte Aufträge: markierten NPC ausschalten ($450), Datenkurier vom Ripperdoc zum Krankenhaus ($250), drei feindliche NPCs ausschalten ($300). Ein aktiver Auftrag pro Spieler, Zeitlimit und Abklingzeit; Auszahlungen erfolgen auf dem Server.
- Cyberpsychose: private Erscheinungen getöteter Gegner, Unschärfe und zusätzliche Bildstörungen, gefährlichere Ausraster und Cyberware-Ausfälle. Treffer mit unterstützten Schusswaffen auf eine eigene Erscheinung lösen tödliche Rückkopplung beim Schützen aus. Andere Spieler sehen diese Erscheinungen nicht.
- Kapazitätschips gewähren je nach Stufe **+1 / +2 / +3** Kapazität.
- Regrowth Core regeneriert zusätzlich 2/4/7 HP pro Sekunde, schließt ab Stufe 2 Blutungen und lässt Gliedmaßen schneller nachwachsen. EMP unterbricht die Regeneration; Blackwall und tödliche Psychose-Rückkopplung umgehen Wiederbelebung.
- Globaler Fortschrittsreset umfasst auch Offline-Spieler. Eine neue Speicher-Generation verhindert, dass verspätete Speichervorgänge den alten Fortschritt wiederherstellen. Laufende Server erkennen den Reset und bitten Spieler um erneuten Beitritt. Adminrechte, Geschenke und Einstellungen bleiben erhalten.

## Codes

Im vorhandenen Code-Menü einlösen:

| Code | Belohnung |
| --- | --- |
| `netrunner` | **$200 und ein zufälliger, noch nicht besessener Waffenskin** |
| `chips` | **$1–500 und ein bis zwei zufällige, noch nicht besessene Waffenskins** |

Jeder Code ist einmal pro Spielstand einlösbar. Belohnung und Einlösestatus werden gemeinsam gespeichert. Sind bereits alle Waffenskins vorhanden, wird nur das Geld vergeben. Dauerhafte Einlösung erfolgt auf öffentlichen Servern; Studio erlaubt eine Sitzung zum Testen. Ohne funktionierende Speicherung wird auf öffentlichen Servern keine ungesicherte Belohnung ausgegeben.

## Prüfung

- Alle 154 Skripte aus der exportierten Datei mit dem offiziellen Luau-Compiler geprüft: bestanden.
- 49 Gameplay-/Speicher-Assertions und 13 Freecam-/Berechtigungs-Assertions: bestanden. Diese Tests verwenden echte Modulquellen mit simulierten Roblox-Diensten.
- XML erneut eingelesen, eindeutige Instanzreferenzen und alle Objektverweise geprüft. Die ursprünglichen Instanzeigenschaften außerhalb der Skriptquellen sind erhalten.
- **Roblox Studio und echte Mehrspieler-/Grafiktests waren hier nicht verfügbar.** Die Tests belegen keine visuelle oder physikalische Laufzeitprüfung in Studio.

Vor dem Veröffentlichen in einer Testkopie mit mindestens zwei Spielern prüfen: Quickhack-Lock/Mausrad/F gegen einen Admin, Sandevistan-Tod/Respawn und Distanzgrenzen, Stillwater-Quest/Beschwören/überlappende Zeitstopps, denselben Krankenhausfilm auf beiden Clients, private Psychose-Erscheinungen, Freecam-Geschenk/Entzug/Wiederbeitritt und einmalige Code-Auszahlung. Den globalen Reset nur in einer getrennten Test-Experience mit eigenen Speichern ausprobieren. Visuell insbesondere Ripperdoc-Arbeitsflächen, Blackwall und kleine Bildschirme kontrollieren.

`RagdollSandbox_v3_0_Quellen_und_Tests.zip` enthält die Quellen nach Studio-Pfad, die Änderungen als Diff, Testharnesses und den Exportprüfbericht.
