#!/bin/sh

set -u

printf '%s\n' 'Cette commande va forcer l’arrêt de DictaMac, xcodebuild et swift-frontend.'
printf '%s' 'Continuer ? [y/N] '
read -r answer

case "$answer" in
    y|Y|yes|YES|oui|OUI) ;;
    *)
        printf '%s\n' 'Arrêt annulé.'
        exit 0
        ;;
esac

killall -9 DictaMac 2>/dev/null || true
pkill -9 -x xcodebuild 2>/dev/null || true
pkill -9 -x swift-frontend 2>/dev/null || true

printf '%s\n' 'Arrêt d’urgence terminé : DictaMac et les processus de build Swift ont été ciblés.'
