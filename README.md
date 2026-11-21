# Shooter (Arbeitstitel)

Deckungs-Shooter fürs Handy im Pappaufsteller-Look, frei nach dem Amiga-Klassiker „Take 'em Out“.
Alle Kulissen und Gegner sind flache Bilder auf echten 3D-Ebenen – daraus entsteht die Parallaxe.
Mündungsfeuer, Funken, Staub, Splitter und Einschusslöcher sind echte 3D-Effekte mit Licht.

- `main.gd` – das ganze Spiel (Szene, Gegner, Schießen, Deckung, Effekte, Anzeige, Update-Knopf)
- `art/` – Bilder (Golden-Hour-Szene, mit ChatGPT erstellt)
- `sfx/` – Geräusche (.ogg von ElevenLabs, .wav noch Platzhalter)
- `tools/make_sfx.py` – erzeugt die Platzhalter-Geräusche

GitHub Actions baut bei jedem Push die APK und veröffentlicht sie als Release `build-N`.
Steuerung: tippen = schießen, nach unten wischen oder COVER = in Deckung (lädt nach), nach oben wischen = raus.
