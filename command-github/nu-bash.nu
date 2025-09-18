# 3) Inicializa Git y primer commit
git init
git add .
git commit -m "feat: primer commit de java-proyects"

# 4) Crea el repo en GitHub y súbelo de una
#    --private o --public según prefieras
gh repo create java-proyects --private --source . --remote origin --push
