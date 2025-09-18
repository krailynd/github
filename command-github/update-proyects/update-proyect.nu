#los primeros pasos, entras a tu carpeta
cd ~/ruta/a/tu/proyecto
#luego analizas el estad
#luego analizas el estadoo
git status -sb
git remote -v

#Asegúrate de estar en la rama correcta (ej. main)

git switch main
git fetch --all --prune

# Opción 1 (más segura): solo avance rápido
#
git pull --ff-only origin main

# Opción 2 (si prefieres rebase de tu rama local sobre lo último)
# git pull --rebase origin main


#Crea/actualiza tu rama de trabajo

git switch -c feature/mi-cambio     # crea y cambia
# si ya existe:
# git switch feature/mi-cambio


#Haz cambios, agrega y commitea

git add -A
git commit -m "feat: describe tu cambio"


#Sincroniza con la base (evita sorpresas al push)

git fetch origin
git rebase origin/main              # o: git merge origin/main


#Sube tu rama

git push -u origin HEAD
