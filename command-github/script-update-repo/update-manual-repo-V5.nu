# git-mini.nu — Menú simple Git/GitHub (HTTPS, sin gh/SSH)
# Opciones: 1) crear proyecto  2) analizar  3) actualizar
# Uso: nu git-mini.nu [--ruta ./carpeta]

# -------- helpers básicos --------

def git_get [key: string] {
  let r = (git config --global --get $key | complete)
  if $r.exit_code == 0 { $r.stdout | str trim } else { "" }
}

def ensure_git_identity [] {
  let name = (git_get "user.name")
  if ($name | is-empty) {
    print "Ejemplo: Juan Pérez"
    let val = (input "📝 Git user.name (tu nombre): ")
    if not ($val | is-empty) { git config --global user.name $val }
  }
  let email = (git_get "user.email")
  if ($email | is-empty) {
    print "Ejemplo: juanperez@example.com"
    let val = (input "✉️  Git user.email: ")
    if not ($val | is-empty) { git config --global user.email $val }
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

# Remoto por HTTPS (sin gh)
def repo_exists_https [owner: string, name: string] {
  (git ls-remote $"https://github.com/($owner)/($name).git" | complete).exit_code == 0
}
def set_origin_and_push_https [owner: string, name: string] {
  if not (has_origin) {
    git remote add origin $"https://github.com/($owner)/($name).git"
  }
  if (has_upstream) { git push } else { git push -u origin HEAD }
}

# -------- acciones --------

def accion_crear_proyecto [] {
  ensure_git_identity

  let por_defecto = (pwd | path basename)
  print "Ejemplo de nombre: mi-repo-supercool"
  let nombre = (input $'📛 Nombre del repo (Enter = "($por_defecto)"): ')
  let repo_name = (if ($nombre | is-empty) { $por_defecto } else { $nombre })

  print "Ejemplo de usuario/organización: tu-usuario"
  let owner = (input "👤 Usuario/organización en GitHub: ")
  if ($owner | is-empty) { print "❌ Usuario vacío. Aborto."; return }

  if not (is_repo_here) {
    print "🆕 Inicializando repo local…"
    git init
    git branch -M main
  }

  git add -A
  (git commit -m "feat: primer volcado de la carpeta" | complete) | ignore

  if (repo_exists_https $owner $repo_name) {
    print $"🔗 Remoto encontrado. Configurando origin HTTPS…"
    set_origin_and_push_https $owner $repo_name
    print "✅ Proyecto listo y subido."
  } else {
    print "⚠️  El repo remoto no existe (o es privado sin credenciales)."
    print $"   1) Crea: https://github.com/new  (Nombre: '($repo_name)')"
    print $"   2) Luego ejecuta:"
    print $"      git remote add origin https://github.com/($owner)/($repo_name).git"
    print "      git push -u origin main"
  }
}

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

  print 'Ejemplo de mensaje: chore: actualización rápida'
  let msg = (input '📝 Mensaje de commit (Enter = "chore: actualización rápida"): ')
  let final_msg = (if ($msg | is-empty) { "chore: actualización rápida" } else { $msg })

  let reindex_q = (input "¿Forzar reindex (limpiar caché de Git)? s/N. Ejemplo: s : ")
  let reindex = (($reindex_q | str downcase) == "s")

  commit_all $final_msg $reindex

  if (has_origin) {
    if (has_upstream) { git push } else { git push -u origin HEAD }
    print "✅ Cambios enviados."
  } else {
    print "⚠️  No hay remoto 'origin'."
    print "   Ejemplo para añadir remoto por HTTPS:"
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
    print "      MENÚ GIT SIMPLE     "
    print "=========================="
    print "1) Crear proyecto"
    print "2) Analizar proyecto"
    print "3) Actualizar proyecto (carpeta completa)"
    print "4) Salir"
    print "--------------------------"
    print "Ejemplo de elección: 1"
    let op = (input "👉 Elige una opción [1-4]: ")

    match ($op | str trim) {
      "1" => { accion_crear_proyecto }
      "2" => { accion_analizar }
      "3" => { accion_actualizar }
      "4" => { print "👋 Saliendo…"; break }
      _   => { print "❓ Opción no válida.\n" }
    }
  }
}
