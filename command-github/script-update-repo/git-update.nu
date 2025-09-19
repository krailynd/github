# git-update.nu — Actualiza un proyecto Git (carpeta completa)
# Uso:
#   nu git-update.nu [--ruta .]

# -------- helpers básicos --------

def git_get [key: string] {
  let r = (git config --global --get $key | complete)
  if $r.exit_code == 0 { $r.stdout | str trim } else { "" }
}

def ensure_git_identity [] {
  let name = (git_get "user.name")
  if ($name | is-empty) {
    print "Ejemplo: Juan Pérez"
    let v = (input "📝 Git user.name (tu nombre): ")
    if not ($v | is-empty) { git config --global user.name $v }
  }
  let email = (git_get "user.email")
  if ($email | is-empty) {
    print "Ejemplo: juanperez@example.com"
    let v = (input "✉️  Git user.email: ")
    if not ($v | is-empty) { git config --global user.email $v }
  }
}

def is_repo_here [] { (git rev-parse --is-inside-work-tree | complete).exit_code == 0 }
def has_origin   [] { (git remote | complete).stdout | lines | any {|it| $it == "origin"} }
def has_upstream [] { (git rev-parse --abbrev-ref --symbolic-full-name '@{u}' | complete).exit_code == 0 }

def safe_pull [] {
  if (has_upstream) {
    git fetch --all --prune
    git pull --ff-only
  } else if (has_origin) {
    print "ℹ️  Rama sin upstream; omito pull (luego push -u)."
  }
}

def commit_all [msg: string, reindex: bool] {
  if $reindex { git rm -r --cached . | ignore }
  git add -A
  if ((git commit -m $msg | complete).exit_code != 0) { print "ℹ️  Nada que commitear." }
}

# -------- comando principal --------

export def main [
  --ruta: string = "."
] {
  cd $ruta
  print $"📂 Carpeta: (pwd)"

  if not (is_repo_here) {
    print "❌ Esta carpeta no es un repositorio Git."
    print "Ejemplo para inicializar rápido y hacer primer commit:"
    print "  git init"
    print "  git branch -M main"
    print "  git add -A"
    print "  git commit -m \"feat: primer volcado\""
    print "Luego vuelve a ejecutar este script."
    return
  }

  ensure_git_identity
  safe_pull

  print 'Ejemplo de mensaje: chore: actualización completa'
  let msg = (input '📝 Mensaje de commit (Enter = "chore: actualización completa"): ')
  let final_msg = (if ($msg | is-empty) { "chore: actualización completa" } else { $msg })

  let reindex_q = (input "¿Forzar reindex (limpiar caché de Git)? s/N. Ejemplo: s : ")
  let reindex = (($reindex_q | str downcase) == "s")

  commit_all $final_msg $reindex

  if (has_origin) {
    if (has_upstream) { git push } else { git push -u origin HEAD }
    print "✅ Cambios enviados."
  } else {
    print "⚠️  No hay remoto 'origin' configurado."
    print "Ejemplo para añadir remoto por HTTPS y subir:"
    print "  git remote add origin https://github.com/USUARIO/REPO.git"
    print "  git push -u origin main"
  }

  print "✅ Listo."
}
