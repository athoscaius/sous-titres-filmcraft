# Interface native

AppKit + AVKit, macOS 14+, Apple Silicon. Le document est indépendant de FilmCraft ; aucune modification de la vidéo source.

Compilation (depuis la racine du livrable) :

```sh
xcrun clang -Wno-deprecated-declarations -c source/Integration/FilmCraftEnvironment.c -o /private/tmp/FilmCraftEnvironment.o
xcrun swiftc -module-cache-path /private/tmp/artcraft-subtitle-ui-cache \
  -parse-as-library -D FILMCRAFT_INTEGRATION -target arm64-apple-macos14.0 \
  -framework AppKit -framework AVKit -framework AVFoundation -framework Security \
  source/UI/*.swift source/Integration/FilmCraftBridge.swift /private/tmp/FilmCraftEnvironment.o -o ArtCraftSousTitresIA
```

Ne pas inclure les tests autonomes du dossier Integration/Tests dans cette commande.
Le moteur natif doit se trouver à `Contents/Resources/bin/transcribe` dans le bundle.

Vérifications :

- `--self-test` : vérifications des données sans interface ni transcription.
- `--preview-ui --preview-video VIDEO --preview-output IMAGE.png` : ouvre une démonstration de l’interface avec quatre sous-titres fictifs, capture puis quitte.
- `--qa-video VIDEO --qa-context "Noms propres et jargon" --qa-edit-checks --qa-output RESULTAT.json` : transcription complète par le moteur du bundle, sauvegarde du projet obtenu et capture `RESULTAT.json.png`, puis fermeture. N’utiliser qu’une vidéo de test pour ce mode automatisé.

La version 1.2 fonctionne sans sauvegarde de projet. Les structures JSON restent utilisées pour le moteur et les tests, mais les commandes de projet et la demande de sauvegarde sont retirées de l’interface. Le découpage après correction ou import est proportionnel au texte : l’interface invite à réécouter le minutage.

SRT et VTT sont des exports de texte et de temps. L’export ASS conserve le style. L’envoi direct à FilmCraft exige une connexion du logiciel, confirme le nom de la séquence, puis vérifie le contexte avant le transfert. Les temps du document et de l’aperçu sont relatifs à la vidéo ; le décalage de séquence est appliqué seulement aux exports et à l’envoi FilmCraft.

L’annulation interrompt le processus du moteur qui transmet SIGTERM à Whisper ; le document précédent est conservé. L’interface bloque l’édition pendant le calcul. Les données temporaires se trouvent dans un dossier privé distinct par tâche, effacé après le traitement.

Le paramètre de test facultatif `--qa-context` utilise le vrai champ de contexte. `--qa-edit-checks` exerce ensuite les actions du contrôleur (correction française du texte et des temps, appliquer, scinder, fusionner, annuler, rétablir), puis vérifie la sauvegarde du projet et les exports. Il produit les fichiers SRT/VTT/ASS et un rapport `RESULTAT.editing-checks.txt`. Ces modifications ne concernent que les données de test de cette exécution.

Le mode timeline importe une seule piste au premier envoi. Les renvois modifient son contenu et son style en conservant son identifiant numérique. La génération est immédiate au clic, sans confirmation. Le mode de test `--qa-update-track` exerce la génération, l’édition puis le renvoi sur la même piste, dans une instance FilmCraft isolée explicitement désignée.

Version 1.3 : transcription séparée de l’envoi, édition directe des cellules de la liste, familles et variantes de polices macOS, curseurs taille/X/Y et couleur du contour. Les trois anciens encarts et le faux gras ont été retirés. Les envois de timeline utilisent désormais les titres texte natifs sur une piste vidéo ArtCraft unique afin de respecter la position libre et les faces de police. Le mode `--qa-two-step` vérifie la révision inchangée après la transcription avant d’invoquer le bouton d’envoi.

Version 1.4.1 : authentification requise par FilmCraft 0.13. Compiler aussi `Integration/FilmCraftEnvironment.c`, ajouter son objet à swiftc ainsi que `-framework Security`. Le LaunchAgent prépare la connexion par session macOS ; un hôte déjà démarré sans clé doit être relancé une fois. `--connection-self-test` teste les identifiants dans un dossier temporaire, sans modifier la session réelle. `ARTCRAFT_BACKEND_RESOURCES` permet de réutiliser explicitement les ressources bin/models/licenses d’un paquet déjà construit lors d’une compilation d’interface.
