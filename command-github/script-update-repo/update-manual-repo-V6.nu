# git-dos.nu — Menú Git mínimo (analizar / actualizar)
# Uso:
#   nu git-dos.nu
#   nu git-dos.nu --ruta ./mi/proyecto

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

# -------- acciones --------

def accion_analizar [] {
  if not (is_repo_here) { print "❌ Esta carpeta no es un repositorio Git."; return }
  print "🔍 Análisis del proyecto\n"

  print "📦 Repo raíz:"
  print (git rev-parse --show-toplevel)

  print "\n🌿 Rama actual y upstream:"
  (git rev-parse --abbrev-ref HEAD | complete).stdout | str trim | print
  if (has_upstream) { (git rev-parse --abbrev-ref '@{u}' | complete).stdout | str trim | print } else { print "— sin upstream —" }

  print "\n🔗 Remotos:"
  git remote -v | uniq | print

  print "\n📊 Estado:"
  git status --short --branch | print

  print "\n🪵 Últimos commits:"
  (git log --oneline -n 10 | complete).stdout | print

  print "\n📁 Sin trackear:"
  (git ls-files --others --exclude-standard | complete).stdout | print

  print "\n🧹 Ignorados (top 20):"
  (git ls-files --others -i --exclude-standard | complete).stdout | lines | first 20 | str join (char nl) | print

  print "\n📐 Tamaño de .git:"
  (du -sh .git | complete).stdout | print

  print "\n✅ Fin del análisis."
}

def accion_actualizar [] {
  ensure_git_identity
  if not (is_repo_here) { print "❌ Esta carpeta no es un repositorio Git."; return }

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
    print "⚠️  No hay remoto 'origin'."
    print "   Ejemplo para añadir remoto por HTTPS y subir:"
    print "   git remote add origin https://github.com/USUARIO/REPO.git"
    print "   git push -u origin main"
  }
}

# -------- menú --------

export def main [
  --ruta: string = "."
] {
  cd $ruta
  print $"📂 Carpeta base: (pwd)\n"

  loop {
    print "=========================="
    print "   MENÚ: GIT (2 opciones) "
    print "=========================="
    print "1) Analizar proyecto"
    print "2) Actualizar proyecto (todos los archivos y carpetas)"
    print "3) Salir"
    print "--------------------------"
    print "Ejemplo de elección: 1"
    let op = (input "👉 Elige una opción [1-3]: ")

    match ($op | str trim) {
      "1" => { accion_analizar }
      "2" => { accion_actualizar }
      "3" => { print "👋 Saliendo…"; break }
      _   => { print "❓ Opción no válida.\n" }
    }
  }
}
