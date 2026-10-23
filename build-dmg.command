#!/bin/zsh
set -euo pipefail
PACKAGE_DIR="${0:A:h}"
SOURCE_APP="${1:-/Applications/Sous-titres FilmCraft.app}"
[[ -d "$SOURCE_APP" ]] || { print -u2 'Application absente. Construisez puis installez le ZIP, ou indiquez le chemin du paquet .app.'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")" == 'local.artcraft.sous-titres-ia' ]]
DMG_WORK="$(mktemp -d "${TMPDIR:-/tmp}/artcraft-subtitles-dmg.XXXXXX")"
trap 'rm -rf "$DMG_WORK"' EXIT
ditto --noextattr --norsrc "$SOURCE_APP" "$DMG_WORK/Sous-titres FilmCraft.app"
ln -s /Applications "$DMG_WORK/Applications"
cat > "$DMG_WORK/Installation.txt" <<'TXT'
Sous-titres FilmCraft — Mac Apple Silicon, macOS 14+

Glissez l’application dans Applications, puis ouvrez-la.
Ouvrez votre montage dans FilmCraft, puis cliquez Transcrire la séquence dans le compagnon.
Corrigez le texte et les durées directement dans la liste, réglez le style et les curseurs, puis cliquez Sous-titrer la TL pour envoyer les titres dans FilmCraft.

Le modèle Whisper large-v3 et son moteur sont inclus. Aucun compte ni téléchargement supplémentaire n’est nécessaire au traitement.

L’envoi direct utilise des titres texte natifs sur une piste vidéo unique pour conserver le style et la position libre. L’import manuel de sous-titres natifs reste possible avec les exports SRT/VTT.

Signature locale ad hoc, sans notarisation Apple ni certificat Developer ID : sur un autre Mac, Gatekeeper peut nécessiter une autorisation dans Réglages Système > Confidentialité et sécurité.

Projet indépendant de FilmCraft / ArtCraft. Voir LISEZ-MOI.md avec les sources pour les détails.
TXT
codesign --verify --deep --strict "$DMG_WORK/Sous-titres FilmCraft.app"
hdiutil create -volname 'Sous-titres FilmCraft' -srcfolder "$DMG_WORK" -format UDZO -ov "$PACKAGE_DIR/Sous-titres-FilmCraft-1.3.1-arm64.dmg"
hdiutil verify "$PACKAGE_DIR/Sous-titres-FilmCraft-1.3.1-arm64.dmg"
