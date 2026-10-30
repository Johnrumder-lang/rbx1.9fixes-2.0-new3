# Ragdoll Sandbox v3.2.1

Die vollständige Spiel-Datei ist `RagdollSandbox_v3_2_1.rbxlx`. In Roblox Studio über **File → Open from File** öffnen. Die Skriptquellen und die Datei sind synchronisiert; es wurde keine Roblox-Experience veröffentlicht und kein echter Spielstand zurückgesetzt.

## Neu in v3.2.1

- **Mobiles Chip-Inventar:** **CHIPS** über dem linken Bewegungsstick antippen. Der Button lässt sich im vorhandenen Touch-Layout-Editor verschieben und speichern.
- Getrennte, scrollbar bedienbare **CHIPS**- und **SLOTS**-Ansichten mit großen Tasten. Alle sechs Slots sind erreichbar; das Fenster passt sich Hochformat, Querformat, Tablets und den Bildschirmrändern an.
- **STORE HELD CHIP** legt einen Chip aus der linken oder rechten Hand in die Tasche. **SLOT** setzt ihn ein, **EJECT** wirft ihn aus, **TAKE** nimmt ihn in die Hand und schließt das Inventar. Scanner/Zoom haben getrennte Schalter, Videos weiterhin **PLAY**. Die Einlagerungstaste setzt den Chip nicht versehentlich in einen gegriffenen Spieler ein.
- Die vorhandenen Serverprüfungen und Steuerungssperren gelten auch für Touch. Tastatursteuerung über K/F bleibt bestehen.
- Vor Veröffentlichung im Studio-Geräteemulator und auf einem Touchgerät prüfen: CHIPS öffnen/schließen, Handy drehen, lange Tasche und alle sechs Slots scrollen, Chip aus beiden Händen einlagern, SLOT/EJECT/TAKE sowie Scanner/Zoom/Video bedienen. Diese echten Touch- und Renderingtests konnten hier nicht ausgeführt werden.

## Neu in v3.2

- **M → CLANS:** Für **$2.500** einen Clan gründen; Namen prüft der Roblox-Textfilter. Der Leiter lädt Personen aus dem aktuellen Server ein. Einladungen gelten fünf Minuten und müssen angenommen werden. Beitritt ist kostenlos; maximal 50 Mitglieder. Mitglieder können austreten, der Leiter kann Mitglieder entfernen oder den Clan auflösen. Die Gründungskosten werden beim Auflösen nicht erstattet. Mitgliedschaft wird gespeichert und der Clanname erscheint als zusätzliche Zeile über Name/Titel. Änderungen werden auf anderen Servern regelmäßig nachgeladen.
- **M → DAILY:** Das Tagesfenster öffnet sich automatisch, wenn eine Belohnung verfügbar ist. Ein Anspruch pro UTC-Kalendertag, Wechsel um 00:00 UTC. **Tag 3: ein Skin; Tag 7: drei Skins.** An Tag 1, 2, 4, 5, 6 gibt es **$25–1.000** und zusätzlich eine **0,5-%-Chance** auf einen Tier-1-Implantatkoffer ohne Admin-Implantate. Die Koffer bleiben als Abholanspruch gespeichert; **TAKE CASE** legt einen echten Koffer in die Hand. Es wird nichts automatisch eingebaut. Bei vollständig besessenen Skins gibt es $250 je ersetztem Skin. Nach Tag 7 beginnt der Zyklus erneut; ein ausgelassener Tag setzt die Serie auf Tag 1.
- Clan-Gründung und Tagesbelohnungen werden mit Geld/Skins gemeinsam gespeichert. Wiederholte Klicks und wiederholte DataStore-Aufrufe zahlen nicht mehrfach aus. Bei einem Speicherfehler wird keine neue Belohnung ausgegeben; eine reservierte Gründungsgebühr wird zurückgegeben. Unveröffentlichtes Studio nutzt Sitzungsspeicher; dauerhafte Änderungen benötigen einen öffentlichen Server mit funktionierendem Speicher.
- **Sechs ausgerüstete Chip-Slots.** F speichert alle gehaltenen Chiptypen im Deck, einschließlich gespawnter Blank-Chips ohne Metadaten. Wenn eine andere Person gegriffen wird, bleibt F die bestehende Einsetz-Aktion. Scanner und Zoom Optics haben jeweils getrennte **ON/OFF**- und **EJECT**-Knöpfe.
- **Quickhacks: fünf Sekunden Upload.** Das HUD zeigt den Countdown. Vor der Wirkung prüft der Server Chip, Körper, Sicht und Reichweite erneut; Auswerfen oder verlorener Kontakt bricht ab. Das gilt auch für den Blackwall-Upload; dessen Beam hat anschließend seinen kurzen bestehenden Effektdurchlauf. Viren behalten **15 Sekunden** Inkubation.
- **Ripperdoc → UNINSTALL CYBERWARE:** Übersicht aller installierten Implantate, einschließlich Seitenangabe und Ausbaupreis. Ausbau zur Liste hinzufügen, **SIGN THE LIST**, anschließend auf die Behandlungsliege legen. Doppelte Ausbau-Einträge werden nicht doppelt berechnet.
- **Code `fixes`:** einmalig **$200 + ein noch nicht besessener Waffenskin**. `2.0` und `update2` sind deaktiviert. Bereits verdiente Belohnungen bleiben; `netrunner` und `chips` funktionieren weiterhin.
- **Zielvirus / Rampage:** Server-Wegfindung statt direktem Laufen gegen Wände, mit Wegpunkten, Sprüngen, Berücksichtigung der Körpergröße und Neuberechnung bei Hindernissen oder Stillstand. Ohne erreichbaren Pfad wird erneut gesucht; Schüsse brauchen freie Sicht.
- **Videos / Krankenhaus-Replays:** Terrain wird nicht geklont. Die Baseplate wird weiterhin kopiert. Bei SKIP, Zeitüberschreitung oder Aufbaufehler werden Videofenster und Mauszustand aufgeräumt. Wiederholtes Abspielen benutzt getrennte Übertragungs-IDs.
- **Psychose:** Der Sandevistan besitzt keinen versteckten zweiten Psychose-Zähler mehr. Implantatlast bis einschließlich Kapazität (z. B. **23/23**) ist sicher. Laufende Überlastungs-Halluzinationen und Störungen enden, sobald die Last wieder sicher ist. Das gilt auch für Admins mit abgeschalteter Immunität. Gezielte Virus-/Quickhack-Angriffe bleiben eigene Effekte.
- Das M-Menü hat zwei Tab-Zeilen, damit CLANS und DAILY sowie Admin-Tabs lesbar bleiben.

## Bisherige Fehlerbehebungen

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

165 Skripte aus der exportierten Datei kompilieren. **440 Assertions** mit aktuellen Quellen und simulierten Roblox-Diensten bestehen, einschließlich mobiler Inventaraktionen und Größenanpassung. XML, Referenzen, Quellenübereinstimmung und Erhalt der bestehenden Welteigenschaften sind geprüft.

**Ein echter Roblox-Studio-/Mehrspieler-/Grafiktest wurde hier nicht ausgeführt.** Vor dem Veröffentlichen mit mindestens zwei Clients prüfen:

1. Zwei Clients: Clan für $2.500 gründen, einladen/beitreten, Tags sehen, rejoinen, austreten/entfernen/auflösen. Im veröffentlichten Test-Place Speicherung über getrennte Server prüfen.
2. Tagespopup, einmaligen Anspruch, Skin-Tage, erneuten Beitritt und Kofferabholung prüfen. Kalender-/Ausfallfälle sind zusätzlich im CLI simuliert.
3. Zielvirus mit Wänden, Treppen, beweglichen Hindernissen und unerreichbarem Ziel testen; erzwungene Bewegung/Sprünge und freie Schusslinie kontrollieren.
4. Kamera aufnehmen, Video im Deck abspielen/überspringen/erneut abspielen; Krankenhaus-Großbildschirm auf zwei Clients ansehen. Terrain darf keinen Clone-Fehler erzeugen.
5. Genau 23/23 Kapazität mit Sandevistan halten; kein Überlastungseffekt bei 0 %. Danach echte Überlastung und gezielte Angriffe getrennt testen.
6. Alle sechs Slots belegen, Scanner/Zoom schalten und auswerfen, gespawnten Blank-Chip mit F einlagern. Upload nach fünf Sekunden sowie Abbruch beim Auswerfen prüfen. Ripperdoc-Ausbau über die neue Liste durchführen.
7. Unveröffentlichten Place starten; F4 öffnen, Spieler locken, Mausrad/F nutzen. F mit Chip, SLOT/EJECT/TAKE sowie Kameraaufnahme ausprobieren.
8. Admin-Immunität ohne Implantate ausschalten; danach Überlastung mit Implantaten und gezielten Virusangriff getrennt prüfen.
9. Zielvirus einsetzen: Auswahl beim Einsetzenden, 15 Sekunden warten, keine eigene Steuerung, sichtbare Waffenaufnahme, Fortsetzung nach Trägertod und Ende nach Zieltod.
10. PvP-Jobs mit echten Spielern abschließen/verlieren; 180 Sekunden nach Fehlschlag, keine Sperre nach Erfolg. Paket wirklich transportieren und Routen wechseln.
11. Dodge an freien Stellen und neben Wänden; Aegis vor und nach Schildbruch; keine Löcher bei vollständig abgewehrten Treffern.
12. Ripperdoc-Theke, Boden in eigenen Videos und Krankenhaus-Bildschirm sowie Stillwater-Summon kontrollieren.
13. Geschenke geben, Empfänger ausloggen, offline entziehen und erneut beitreten. Serverübergreifende Entziehung und Einzel-/Gesamt-Reset ausschließlich in einer getrennten Test-Experience prüfen.
