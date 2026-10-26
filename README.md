# Sous-titres FilmCraft

Compagnon macOS indépendant pour transcrire en français une séquence FilmCraft avec **Whisper large-v3**, corriger le texte et créer des sous-titres stylisés. Traitement local, modèle et moteur inclus. Projet personnel, non officiel et non affilié à FilmCraft ou ArtCraft.

## Installer

[Télécharger le DMG pour Mac Apple Silicon](https://github.com/athoscaius/sous-titres-filmcraft/releases/latest/download/Sous-titres-FilmCraft-1.4.1-arm64.dmg), l’ouvrir puis glisser **Sous-titres FilmCraft** dans Applications.

Mac Apple Silicon, **macOS 14+**. Environ 1,1 Go de modèles inclus, aucun compte ni clé API, aucun envoi du média sur Internet. Signature locale ad hoc, sans Developer ID ni notarisation Apple ; sur un autre Mac, Gatekeeper peut nécessiter une autorisation dans Confidentialité et sécurité.

## Utiliser

1. Ouvrir le montage dans FilmCraft, puis le compagnon. La connexion sécurisée de FilmCraft 0.13 est préparée automatiquement. Si FilmCraft était déjà ouvert avant cette activation, enregistrer puis le relancer une fois depuis le bouton Timeline FilmCraft.
2. Cliquer **Transcrire la séquence**. Rien n’est ajouté à la timeline à ce stade.
3. Corriger les textes et durées directement dans la liste. Régler une/deux lignes, la taille, les polices du Mac et leurs variantes, les couleurs du texte et du contour, et les curseurs X/Y.
4. Cliquer **Sous-titrer la TL** quand le résultat convient. Les renvois de la session remplacent le contenu de la même piste, sans doublon.

Par défaut : **Delight Semi Bold, 70 px, contour 0 px, une ligne, 35 caractères, 3 secondes maximum**. Le contour se dessine à l’extérieur des lettres dans l’aperçu et dans les titres FilmCraft. Delight doit être installée sur le Mac ; les polices ne sont pas incluses dans le paquet.

La résolution et l’aspect ratio de la séquence sont détectés automatiquement : l’aperçu, la taille et la disposition des titres s’adaptent aux formats horizontal, vertical, carré et 4K. La taille choisie sert de référence Full HD, ajustée au côté court ; les textes longs restent dans la largeur utile et les curseurs de position restent modifiables. L’export ASS utilise aussi le format détecté.

L’envoi utilise des **titres texte natifs éditables sur une piste vidéo dédiée unique**, pour conserver la position libre et les variantes de police que les sous-titres natifs de FilmCraft 0.12.0 limitent. Les exports SRT/VTT conservent texte et temps ; l’export ASS conserve le style pour les outils compatibles. FilmCraft 0.12.0 ne lit pas ASS.

La transcription peut demander des corrections, notamment dans le bruit et sur les noms propres. Garder le montage stable pendant le traitement : un changement de projet ou de séquence interrompt l’envoi. Le compagnon ne modifie pas l’application FilmCraft et ne demande pas de sauvegarde de projet à sa fermeture.

Détails, confidentialité, connexion locale et désinstallation : [LISEZ-MOI.md](LISEZ-MOI.md).

## Construire et vérifier

```sh
./build.command
# Après installation :
"/Applications/Sous-titres FilmCraft.app/Contents/MacOS/ArtCraftSubtitlesIA" --self-test
./build-dmg.command
```

Outils Xcode et réseau nécessaires à la première construction. Sources, modèles et versions épinglés avec SHA-256 dans `source/backend/DEPENDENCIES.json` et le script de construction. Les binaires volumineux sont distribués dans les Releases, sans être stockés dans Git.

## Composants et droits

- [Whisper](https://github.com/openai/whisper) et [whisper.cpp](https://github.com/ggml-org/whisper.cpp), licences MIT incluses.
- Silero VAD, licence MIT incluse dans `source/backend/`.
- [FilmCraft](https://github.com/storytold/filmcraft), application hôte non incluse.
- Icône du singe bleu fournie par l’utilisateur, source `assets/provided-icon.png`.

Aucune licence libre supplémentaire n’est accordée au code propre à ce projet. Les composants tiers conservent leurs licences respectives.
