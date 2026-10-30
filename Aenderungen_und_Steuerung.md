# Ragdoll Sandbox v3.1

Die vollständige Spiel-Datei ist `RagdollSandbox_v3_1.rbxlx`. In Roblox Studio über **File → Open from File** öffnen. Die Skriptquellen und die Datei sind synchronisiert; es wurde keine Roblox-Experience veröffentlicht und kein echter Spielstand zurückgesetzt.

## Fehlerbehebungen

- **Studio-Start:** `ProgressEpoch` fängt auch Fehler beim Anfordern des DataStores ab. Ein unveröffentlichter Place startet mit Sitzungsspeicher. In veröffentlichten Servern werden echte Spielstände weiterhin geladen; bei unbekannter Speicher-Generation wird kein vorhandener Spielstand überschrieben.
- **Ripperdoc:** Der neue PC steht auf der vorhandenen Theke am Front-Desk und zeigt zur Bedienposition. Die zusätzlichen Tische mitten im Raum entfallen.
- **Quickhacks:** Neuer reservierter Keybind **F4**. Der Client wartet auf das echte Server-Remote, statt bei einem Startfehler ein funktionsloses lokales Remote anzulegen. Spieler anvisieren, mit dem Mausrad auswählen, mit F ausführen. Der Kameraabstand bleibt dabei fest.
- **Psychose:** Ausschalten der Admin-Immunität setzt die Belastung nicht mehr künstlich auf 65 %. Ohne Implantatlast wird Cyberware-Psychosestress auf null gesetzt – für Admins und normale Spieler. Die serverweite Psychose-Einstellung bleibt wirksam; ein gezielter Quickhack oder Virus ist weiterhin ein eigener Angriff.
- **Aufnahmen:** Große Boden-/Baseplate-Teile außerhalb des Map-Modells werden vor dem übrigen Umgebungsbudget in die Wiedergabe kopiert. Das gilt auch für Krankenhaus-Replays.
- **Schrift:** Wieder die ursprüngliche Schrift **Sarpanch**. Die schwarzen/grauen Menüs und UI-Sounds bleiben erhalten.
- **Dodge:** Alle Chipstufen versetzen den Charakter seitlich. Wand- und Bodenprüfung verhindern Versetzungen durch Wände oder in freie Luft; ohne freie Ausweichrichtung kann der Treffer landen. Eine kurze Ausweichphase deckt die übrigen Pellets derselben Salve ab.
- **Blut und Löcher:** Schadensabwehr wird vor Fleisch-Feedback ausgewertet. Abgefangene Treffer erzeugen keine Durchschusstunnel oder Austrittsblut. Erst Schaden, der tatsächlich durch den Aegis-Schild dringt, erzeugt Körperverletzungen.
- **Serverseitige Aufnahme:** Chip-TAKE, Paketaufnahme und erzwungene Waffenaufnahme synchronisieren jetzt auch den lokalen Handzustand. Serverseitiges Fallenlassen löst den lokalen Griff.

## Chips, Viren und Fremdsteuerung

**F mit einem gehaltenen Chip** bringt ihn ins Inventar und öffnet das Deck. Dort kann er geslottet, ausgeworfen und mit **TAKE** wieder in die Hand genommen werden. Videos lassen sich über **PLAY** abspielen. Wer eine andere Person mit der freien Hand festhält, setzt ihr den Chip mit F ein.

Beim Einsetzen von **KILL A TARGET** erscheint beim Einsetzenden eine Spielerliste. Der Chip wird erst nach gültiger Zielwahl eingesetzt. Nach **15 Sekunden** beginnt die Wirkung. Das Ziel kann eine andere lebende Person sein; der Träger selbst ist ausgeschlossen. Firewall und bestehende Angriffsschutzregeln werden beim Aktivieren geprüft.

Die Fremdsteuerung beschafft eine freie Schusswaffe oder eine Pistole, hebt sie auf und steuert Bewegung, Zielen, Schießen und Nachladen. Gameplay-Tasten und Menüklicks sind währenddessen gesperrt. Der Zielauftrag hat kein Zeitlimit und wird nach einem Tod/Respawn des Trägers im laufenden Server fortgesetzt. Er endet, wenn die ausgewählte Zielperson stirbt. Verlässt sie den Server, wird nicht heimlich ein anderes Ziel gewählt. Normale Rampages behalten ihre festgelegte Dauer.

Das Programmieren eines Virus kostet **$250 plus den Blank-Chip**, auch für Admins. Ein direkt eingesetzter Virus hat **15 Sekunden Verzögerung**; ein Video-Trojaner beginnt diesen Countdown nach der Wiedergabe. Auch biologische Virus-Symptome haben 15 Sekunden Inkubation.

## Jobs

| Auftrag | Aufgabe | Geld |
| --- | --- | --- |
| Player Bounty | Eine vom Server ausgewählte lebende Spielerperson töten | $150 |
| Three Kill Streak | Drei Spielerkills, ohne selbst zu sterben; NPCs zählen nicht | $200 |
| Package Delivery | Ein echtes Paket zwischen zwei zufällig gewählten Orten tragen | $30 |

Es gibt einen aktiven Auftrag pro Person und ein Zeitlimit von zehn Minuten. Tod, Abbruch, Zeitüberschreitung oder verlorenes Ziel/Paket beenden den Auftrag mit **180 Sekunden Wartezeit**. Erfolgreiche Aufträge haben **keine Wartezeit**. Der Sperrzustand wird gespeichert; ein verlassener aktiver Auftrag zählt beim Wiederbeitritt als Fehlschlag.

Paket-Routen wählen verschiedene Start- und Zielorte aus Baustelle, rotem Haus, Ripperdoc und Garage, soweit die aktuelle Map diese Orte bereitstellt. Am Start das Paket mit F aufnehmen. Für die Zustellung muss genau dieses Paket tatsächlich getragen oder in der eigenen Tasche sein und am Ziel ankommen. Ein selbst gespawntes Paket ersetzt es nicht.

## Admin-Menüs und Stillwater

- **M → ADMIN → WIPE ALL PROGRESS:** nur der Spielbesitzer, mit zweitem Bestätigungsklick. Der Reset gilt für sämtliche Konten und alle Server, auch für Offline-Spieler.
- **M → PLAYERS → WIPE:** Einzel-Reset mit Bestätigung; ebenfalls über Server hinweg. Ein Admin kann den Spielbesitzer nicht zurücksetzen.
- Betroffene anwesende Spieler bekommen den Kopfexplosionseffekt und werden nach zwei Sekunden zum erneuten Beitritt aufgefordert. Andere Server erhalten die Änderung per MessagingService und prüfen zusätzlich regelmäßig den Speicher. Offline-Spieler laden beim nächsten Beitritt einen neuen Spielstand.
- Alte laufende Speichervorgänge bleiben in der alten Generation und können gelöschten Fortschritt nicht wiederherstellen. Einstellungen und Admin-Geschenke sind getrennt von Spiel-Fortschritt.
- **M → GIFT LOG:** gespeicherte Geschenke seitenweise anzeigen, über User ID suchen und mit Bestätigung entfernen, auch wenn die Person offline ist. Normale Admins können ihre eigenen Geschenke verwalten; der Spielbesitzer sieht auch alte Geschenke ohne dokumentierten Absender und Geschenke anderer Admins. Offline-Änderungen werden feldweise gespeichert, damit andere Geschenke erhalten bleiben. Änderungen werden auf anderen Servern nachgeladen; die regelmäßige Prüfung dient als Rückfall bei ausgefallenen Nachrichten.
- **T → Weapons → Stillwater + Sheath (quest):** erstellt Schwert und Scheide zusammen, nur nach abgeschlossener Quest. Automatisches Ausrüsten beim Spawn bleibt abgeschaltet.
- Freecam weiter über **M → GIFTS → FREECAM** verschenken; Empfänger nutzen **U**. Entziehen beendet eine aktive Freecam.

## Weitere Steuerung und Codes

**K:** Chip-Inventar. **I:** bisheriger Admin-Zeitstopp. **F4:** Quickhack-Modus. **M:** Einstellungen/Admin. **T:** Spawnmenü.

`netrunner` gibt einmalig **$200 + einen noch nicht besessenen Waffenskin**. `chips` gibt einmalig **$1–500 + ein bis zwei noch nicht besessene Waffenskins**. Sind alle Skins vorhanden, bleibt die Geldbelohnung. Dauerhafte Einlösung benötigt funktionierende öffentliche Speicherung; Studio kann nur die Sitzung testen.

## Prüfung und noch nötiger Studio-Test

159 Skripte aus der exportierten Datei kompilieren. **150 Assertions** mit aktuellen Quellen und simulierten Roblox-Diensten bestehen. XML, Referenzen, Quellenübereinstimmung und Erhalt der bestehenden Welteigenschaften sind geprüft.

**Ein echter Roblox-Studio-/Mehrspieler-/Grafiktest wurde hier nicht ausgeführt.** Vor dem Veröffentlichen mit mindestens zwei Clients prüfen:

1. Unveröffentlichten Place starten; F4 öffnen, Spieler locken, Mausrad/F nutzen. F mit Chip, SLOT/EJECT/TAKE sowie Kameraaufnahme ausprobieren.
2. Admin-Immunität ohne Implantate ausschalten; danach Überlastung mit Implantaten und gezielten Virusangriff getrennt prüfen.
3. Zielvirus einsetzen: Auswahl beim Einsetzenden, 15 Sekunden warten, keine eigene Steuerung, sichtbare Waffenaufnahme, Fortsetzung nach Trägertod und Ende nach Zieltod.
4. PvP-Jobs mit echten Spielern abschließen/verlieren; 180 Sekunden nach Fehlschlag, keine Sperre nach Erfolg. Paket wirklich transportieren und Routen wechseln.
5. Dodge an freien Stellen und neben Wänden; Aegis vor und nach Schildbruch; keine Löcher bei vollständig abgewehrten Treffern.
6. Ripperdoc-Theke, Boden in eigenen Videos und Krankenhaus-Bildschirm sowie Stillwater-Summon kontrollieren.
7. Geschenke geben, Empfänger ausloggen, offline entziehen und erneut beitreten. Serverübergreifende Entziehung und Einzel-/Gesamt-Reset ausschließlich in einer getrennten Test-Experience prüfen.
