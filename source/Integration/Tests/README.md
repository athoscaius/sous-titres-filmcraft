# FilmCraft integration fixture

IntegrationFixture.swift is a standalone test executable, excluded from the app build.
Compile alongside ../FilmCraftBridge.swift with `swiftc -module-cache-path /private/tmp/filmcraft-swift-module-cache`.

Run only against an empty FilmCraft instance that you launched with:

```
open -n -a /Applications/FilmCraft.app --args --empty --no-recover --data-dir /private/tmp/artcraft-filmcraft-bridge-test --control 47873
```

First verify `project.inspect`: `path: null`, `root.children: []`, `activeSequence: null`.
Create a sequence with `file.newSequence {name:"Test compagnon — sous-titres",width:1920,height:1080,fps:25}`.
Write `/private/tmp/artcraft-filmcraft-bridge-test/captions.srt`:

```
1
00:00:00,500 --> 00:00:02,000
Bonjour à tous.

2
00:00:02,200 --> 00:00:04,000
Une première ligne,
puis une deuxième.
```

The test checks imported count and rejects stale target snapshots without duplicating captions.
Query `captions.list` afterward to assert one track, two cues and round-tripped font, size,
colors, background, outline, anchor, margin, line spacing and preserved newline. Sample observed
result is ../../../../verification/filmcraft-style-roundtrip.json.
Only close the session you own after checking its project path/name/sequence identity again.
Never run against an existing user project, never terminate a user session, never configure the user’s login environment during fixture tests. FilmCraft 0.13 requires a private random FILMCRAFT_CONTROL_TOKEN passed only in the fixture process environment.

## Formats de séquence (1.4)

`FormatFixture.swift` se compile séparément avec `UI/SubtitleCanvas.swift`, `UI/SubtitleDocument.swift` et `Integration/FilmCraftBridge.swift` (définir `FILMCRAFT_INTEGRATION`). Il exige le PID et un port distinct de 47873 d’une instance vide lancée avec son propre `--data-dir` temporaire. Il refuse un projet enregistré et exige une séquence dont le nom commence par `Format fixture `. Il crée deux titres de test et renvoie leur taille, position et les identifiants des clips, à vérifier avec `graphics.list`. Ne jamais le lancer dans un projet utilisateur.

Les autotests `--self-test` du compagnon couvrent aussi les formats 16:9, 9:16, 1:1, UHD, vertical UHD et panoramique, les pixels non carrés, la conservation des mots et des limites de lignes, ainsi que la résolution ASS. `--preview-ui --preview-format 1080x1920 --preview-output /private/tmp/vertical.png` produit un aperçu fictif sans connexion FilmCraft.

## Authentification 0.13 (1.4.1)

Compiler `FilmCraftEnvironment.c` avec clang, puis ajouter l’objet, `UI/FilmCraftSession.swift` et `-framework Security` aux compilations autonomes. `AuthenticationFixture.swift` exige PID et port d’une instance vide isolée, une séquence `Format fixture authentication…`, un répertoire temporaire et la clé éphémère dans son environnement. Il teste les requêtes authentifiées, le refus sans clé, la détection, le mixage audio et les mises à jour sur la même piste. `--connection-self-test` utilise un dossier temporaire sans changer les variables de la session réelle.
