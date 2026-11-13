#!/usr/bin/env python3
"""Génère puis lit une phrase de test avec la voix système de macOS."""

from __future__ import annotations

import argparse
import subprocess
import tempfile
import time
from pathlib import Path


DEFAULT_TEXT = (
    "Bonjour, ceci est un test de transcription vocale avec DictaMac. "
    "La voix synthétique doit apparaître dans cette note sans sous-titrage parasite."
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--text", default=DEFAULT_TEXT, help="Texte à synthétiser")
    parser.add_argument("--voice", default="Thomas", help="Voix macOS utilisée")
    parser.add_argument("--delay", type=float, default=3.0, help="Délai avant lecture")
    parser.add_argument("--volume", type=float, default=1.5, help="Volume de lecture afplay")
    parser.add_argument("--output", type=Path, help="Fichier AIFF à conserver")
    parser.add_argument("--no-play", action="store_true", help="Génère sans lire l'audio")
    return parser.parse_args()


def synthesize(text: str, voice: str, output: Path) -> None:
    print(f"Génération de l'audio dans {output}…", flush=True)
    subprocess.run(
        ["say", "-v", voice, "-o", str(output), text],
        check=True,
    )


def play(output: Path, delay: float, volume: float) -> None:
    print(
        f"Maintenez fn maintenant : lecture dans {max(delay, 0.0):g} seconde(s).",
        flush=True,
    )
    time.sleep(max(delay, 0.0))
    print("Lecture en cours… Relâchez fn à la fin de la phrase.", flush=True)
    subprocess.run(["afplay", "--volume", str(max(volume, 0.0)), str(output)], check=True)


def main() -> None:
    arguments = parse_arguments()
    if arguments.output:
        output = arguments.output.expanduser().resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        synthesize(arguments.text, arguments.voice, output)
        if not arguments.no_play:
            play(output, arguments.delay, arguments.volume)
        return

    with tempfile.TemporaryDirectory(prefix="dictamac-audio-") as directory:
        output = Path(directory) / "dictation-test.aiff"
        synthesize(arguments.text, arguments.voice, output)
        if not arguments.no_play:
            play(output, arguments.delay, arguments.volume)


if __name__ == "__main__":
    main()
