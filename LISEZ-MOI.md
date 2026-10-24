# Sous-titres FilmCraft

Compagnon indépendant pour **FilmCraft**, conçu pour ce Mac Apple Silicon, macOS 14 ou ultérieur. Transcription française locale avec Whisper large-v3, correction du texte et des temps, aperçu vidéo et personnalisation des sous-titres. Version 1.4.0.

## Démarrer

1. Ouvrir FilmCraft et le montage à sous-titrer, puis le compagnon. Le nom du projet et de la séquence active est détecté automatiquement.
2. Lors de la première activation seulement, si FilmCraft était déjà ouvert sans connexion, enregistrer puis quitter FilmCraft soi-même. Cliquer **Timeline FilmCraft** dans le compagnon pour le rouvrir connecté, puis rouvrir le projet si nécessaire.
3. Cliquer **Transcrire la séquence**. Le compagnon analyse le mixage de toute la timeline sans créer de piste ni envoyer de sous-titres à ce stade.
4. Modifier les textes et les temps directement dans la liste. Ajouter, scinder, fusionner ou recomposer si nécessaire.
5. Dans **Style**, choisir une famille de police du Mac ; ses variantes s’affichent dans un second sélecteur quand plusieurs sont disponibles. Régler la taille, la couleur du texte, l’épaisseur et la couleur du contour. Déplacer les curseurs Horizontal et Vertical pour positionner les sous-titres.
6. Quand le résultat convient, cliquer **Sous-titrer la TL**. Une piste unique « Sous-titres · ArtCraft » reçoit les titres. Les envois suivants de la session mettent à jour son contenu sans ajouter de piste.

**Format de l’envoi direct :** FilmCraft 0.12.0 limite la position de ses sous-titres natifs. Le compagnon utilise donc des titres texte natifs, entièrement éditables dans FilmCraft, sur une piste vidéo dédiée. Cela conserve les variantes de police, la position libre et la couleur du contour. Ce ne sont pas des images aplaties ni une piste de sous-titres fermés. Les anciennes pistes de sous-titres déjà présentes ne sont pas supprimées ou masquées automatiquement.

Le mixage respecte les placements, coupes, silences et réglages audio de FilmCraft. Il utilise toute la séquence, indépendamment des points d’entrée/sortie. Les temps des sous-titres commencent au zéro de la séquence, sans décalage manuel. L’aperçu lit ce mixage audio ; l’image du montage reste dans FilmCraft. Les horodatages Whisper restent approximatifs et peuvent être retouchés. Garder le montage stable pendant le traitement : tout changement de projet, de séquence ou de révision interrompt l’envoi.

Les encarts Sous-titre sélectionné, Contexte et FilmCraft position dans la séquence sont retirés. Le compagnon ne propose pas de sauvegarde de projet ni de demande d’enregistrement à la fermeture. Les titres envoyés restent dans FilmCraft et se sauvegardent avec le montage.

## Polices, position et exports

- Les familles disponibles proviennent de macOS, sans liste prédéfinie. Le sélecteur Variante affiche les styles réellement installés de la famille (Regular, Medium, Italic, Bold…). La liste est rafraîchie quand l’application redevient active.
- Les curseurs de position déplacent le bloc de texte dans l’image, de gauche à droite et du haut vers le bas. L’étendue tient compte de sa largeur et de sa hauteur pour limiter les sorties du cadre. La taille est exprimée en pixels pour une image de référence de 1 080 lignes.
- SRT et VTT conservent texte, retours à la ligne et minutage. Ils peuvent servir à importer une piste de sous-titres native dans FilmCraft, sans style graphique.
- ASS conserve aussi le style, le contour et la position pour les outils compatibles ; FilmCraft 0.12.0 ne lit pas ASS.
- L’ouverture d’un fichier vidéo reste accessible dans Fichier → Ouvrir une vidéo pour une transcription indépendante de la timeline. Le parcours principal est la séquence active.
- Aucun fichier de FilmCraft ni sa signature ne sont modifiés. Une session déjà ouverte sans canal compagnon doit être enregistrée et relancée une fois.

## Qualité et confidentialité

Le moteur utilise **Whisper large-v3** multilingue, quantifié Q5_0 pour réduire sa mémoire, avec calcul Metal sur Apple Silicon. C’est le grand modèle, et non une petite variante rapide. Le français est imposé ; le modèle traite le contexte de la parole pour reconnaître les noms et le vocabulaire spécialisé. Cela ne garantit pas l’absence de faute : relire les passages bruités, la musique et les voix superposées. Aucun modèle de réécriture ne transforme automatiquement le sens de la transcription.

La détection de parole Silero écarte les zones sans voix ; un contrôle préalable refuse l’audio totalement silencieux. Les horodatages et la séparation des mots restent approximatifs. Les sous-titres sont composés à partir de ces mots, puis peuvent être modifiés librement.

Les modèles (environ 1,1 Go) et le moteur natif sont inclus dans l’application. Aucun compte, abonnement, clé API ou envoi de média sur Internet. Aucune dépendance à Python, Homebrew ou Codex à l’exécution. L’extraction audio utilise AVFoundation : MP4, MOV et les formats audio usuels pris en charge par macOS ; un codec non lisible provoque une erreur claire. Toutes les pistes audio sont mixées en mono pour l’analyse. La limite de durée technique est de 18 heures ; le temps de calcul dépend du média et du Mac.

Les fichiers temporaires du moteur sont privés et nettoyés après traitement ou annulation. Le mixage de timeline est conservé dans le cache privé du compagnon pour permettre l’écoute pendant la session ; macOS peut purger ce cache. Les exports sont enregistrés aux emplacements que vous choisissez. La fermeture du compagnon abandonne son état temporaire ; les sous-titres déjà envoyés restent dans FilmCraft.

## Installation et mises à jour

Le DMG s’installe en glissant l’application dans **Applications**. `Installer.command` installe l’archive ZIP locale et conserve une version précédente en sauvegarde. L’application FilmCraft et sa signature ne sont jamais modifiées. Une mise à jour de FilmCraft ne remplace pas le compagnon ; un changement de son protocole peut toutefois demander une adaptation. L’export SRT/VTT reste indépendant de ce protocole.

Le contrôle natif de FilmCraft 0.12.0 écoute seulement en boucle locale mais ne possède pas l’authentification de PhotoCraft. Son activation est configurée par le compagnon pour permettre la détection automatique. Quitter FilmCraft met fin à cette connexion. La connexion est conservée pour les démarrages suivants par `~/Library/LaunchAgents/local.artcraft.filmcraft-connection.plist`, qui définit la variable native `FILMCRAFT_CONTROL_PORT` (47873) à l’ouverture de session. L’application la définit aussi pour la session courante. Pour désactiver : supprimer ce fichier, exécuter `launchctl unsetenv FILMCRAFT_CONTROL_PORT`, puis redémarrer FilmCraft. Aucun fichier du bundle FilmCraft n’est modifié.

Distribution signée localement (« ad hoc »), sans certificat Developer ID ni notarisation Apple. Sur un autre Mac, Gatekeeper peut nécessiter une autorisation dans Confidentialité et sécurité. Ce paquet cible Apple Silicon uniquement.

## Sources et construction

`build.command` recompile l’interface et le moteur puis crée le ZIP. Outils Xcode et réseau requis pour le premier téléchargement des sources/modèles officiels, tous épinglés et contrôlés par SHA-256. Les licences de Whisper, whisper.cpp et Silero sont incluses dans `source/backend/` et dans l’application. Le modèle conserve sa licence MIT. Le code du compagnon est fourni pour examen et adaptation personnelle, sans licence libre supplémentaire implicite.

L’icône actuelle utilise le singe sur fond bleu fourni par l’utilisateur. Le dessin original est conservé dans `assets/provided-icon.png`, avec sa transparence, sans régénération.

Références officielles : [Whisper](https://github.com/openai/whisper), [whisper.cpp](https://github.com/ggml-org/whisper.cpp), [FilmCraft](https://github.com/storytold/filmcraft), [captions FilmCraft](https://github.com/storytold/filmcraft/blob/274c4cf85ba638d4b6f867d97ca3f6478a993c8d/docs/captions.md).

Identité visuelle : nom « Sous-titres FilmCraft » et nouvelle icône fournie par l’utilisateur. Le dessin source est conservé dans `assets/provided-icon.png`, sans régénération. Les identifiants internes et dossiers de connexion restent inchangés pour conserver la configuration existante.

Valeurs par défaut : Delight Semi Bold (police à installer séparément), taille 70 px, contour extérieur de 0 px, une ligne, 35 caractères et durée maximale de 3 secondes.

Le compagnon lit automatiquement la résolution et le rapport de pixels de la séquence active. L’aperçu conserve son aspect ratio réel (horizontal, vertical, carré, panoramique). La taille 70 est une référence Full HD : elle est proportionnelle au côté court de la séquence, soit 140 pixels en UHD. Les titres trop longs sont ajustés à la largeur utile, avec les retours à la ligne choisis et des marges de sécurité. Le nombre de caractères transmis au moteur est plafonné par la largeur du cadre. Les curseurs X/Y restent réglables, sans être réinitialisés lors d’un changement de format. L’export ASS conserve également la résolution et la disposition.
