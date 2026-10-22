# Ruta SDE · app de escritorio

Este repositorio solo contiene la versión publicada de la app (`ruta-sde.html`) y su número de versión (`version.txt`).
La app instalada en Windows revisa `version.txt` cada vez que se abre y, si cambió, descarga `ruta-sde.html` sola.

No edites estos archivos a mano: se generan con `python3 app/build.py --local` en el repositorio del código.
