# git-menu.nu — Menú Git/GitHub en Nushell (sin SSH, por HTTPS)
# Uso:
#   nu git-menu.nu
#   nu git-menu.nu --ruta ./mi/proyecto

# ---------------- helpers ----------------

def has_cmd [name: string] { (which $name | is-empty) == false }

def git_get [key: string] {
  let r = (git config --global --get $key | complete)
  if $r.exit_code == 0 { $r.stdout | str trim } else { "" }
}

def set_git_if_missing [key: string, prompt: string, example: string] {
  let cur = (git_get $key)
  if ($cur | is-empty) {
    print $'Ejemplo: ($example)'
    let val = (input $prompt)
    if not ($val | is-empty) { git config --global $key $val }
  } else {
    print $'✅ Ya configurado: ($key) = "($cur)"'
  }
}

def ensure_git_identity [] {
  set_git_if_missing "user.name"  "📝 Git user.name (tu nombre): "  'Juan Pérez'
  set_git_if_missing "user.email" "✉️  Git user.email: "           'juanperez@example.com'
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
  } else {
    print "ℹ️  Sin remoto 'origin'; omito pull."
  }
}

def commit_all [msg: string, reindex: bool] {
  if $reindex { git rm -r --cached . | ignore }
  git add -A
  if ((git commit -m $msg | complete).exit_code != 0) { print "ℹ️  Nada que commitear." }
}

# --- GitHub vía HTTPS (sin SSH) ---

def gh_authed [] { has_cmd gh and ((gh auth status | complete).exit_code == 0) }
def gh_user [] {
  let r = (gh api user | complete)
  if $r.exit_code == 0 { ($r.stdout | from json | get login) } else { "" }
}

def repo_exists_https [owner: string, name: string] {
  # Comprobación ligera por HTTPS (puede fallar en privados sin auth)
  (git ls-remote $"https://github.com/($owner)/($name).git" | complete).exit_code == 0
}

def set_origin_and_push_https [owner: string, name: string] {
  if not (has_origin) {
    git remote add origin $"https://github.com/($owner)/($name).git"
  }
  if (has_upstream) { git push } else { git push -u origin HEAD }
}

# ---------------- acciones ----------------

def accion_configurar [] {
  print "🧩 Configuración global de Git"
  ensure_git_identity
  print "\n✅ Configuración lista.\n"
}

def accion_crear_proyecto [] {
  ensure_git_identity

  let por_defecto = (pwd | path basename)
  print $"Ejemplo de nombre: mi-repo-supercool"
  let nombre = (input $'📛 Nombre del repo en GitHub (Enter = "($por_defecto)"): ')
  let repo_name = (if ($nombre | is-empty) { $por_defecto } else { $nombre })

  print "Ejemplo visibilidad: privado / publico"
  let vis_in = (input "🔒 Visibilidad (privado/publico) [Enter=privado]: ")
  let flag_vis = (if ($vis_in | str downcase) == "publico" { "--public" } else { "--private" })

  if not (is_repo_here) {
    print "🆕 Inicializando repo local…"
    git init
    git branch -M main
  }

  git add -A
  (git commit -m "feat: primer volcado de la carpeta" | complete) | ignore

  if (gh_authed) {
    let owner = (if ((gh_user | str length) > 0) { gh_user } else { (input "👤 Usuario GitHub: ") })
    if (repo_exists_https $owner $repo_name) {
      print $"🔗 Ya existe ($owner)/($repo_name). Configurando origin (HTTPS)…"
      set_origin_and_push_https $owner $repo_name
    } else {
      print $"🛠️  Creando repo con gh: (if $flag_vis == '--public' { 'público' } else { 'privado' })"
      # gh se encarga de crear el repo, fijar origin (HTTPS) y hacer push
      gh repo create $repo_name $flag_vis --source . --remote origin --push
    }
  } else {
    let owner = (input "👤 Tu usuario de GitHub (HTTPS). Ejemplo: miduDev: ")
    if ($owner | is-empty) { print "❌ Usuario vacío. Aborto."; return }
    if (repo_exists_https $owner $repo_name) {
      print "🔗 Repo remoto existe. Configurando origin (HTTPS)…"
      set_origin_and_push_https $owner $repo_name
    } else {
      print "⚠️  No tienes 'gh' autenticado y el repo remoto no existe aún."
      print $"   Crea 'https://github.com/($owner)/($repo_name})' en GitHub y luego:"
      print $"   git remote add origin https://github.com/($owner)/($repo_name).git"
      print "   git push -u origin main"
      return
    }
  }

  print "✅ Proyecto listo y subido."
}

def accion_analizar [] {
  if not (is_repo_here) { print "❌ Esta carpeta no es un repositorio Git."; return }
  print "🔍 Análisis completo del proyecto\n"

  print "📦 Repo:"
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

  print "\n📁 Archivos sin trackear:"
  (git ls-files --others --exclude-standard | complete).stdout | print

  print "\n🧹 Archivos ignorados (top 20):"
  (git ls-files --others -i --exclude-standard | complete).stdout | lines | first 20 | str join (char nl) | print

  print "\n📐 Tamaño aproximado .git:"
  (du -sh .git | complete).stdout | print

  print "\n✅ Fin del análisis.\n"
}

def accion_update_carpeta [] {
  ensure_git_identity

  if not (is_repo_here) { print "❌ Esta carpeta no es un repositorio Git."; return }

  safe_pull

  print "Ejemplo de mensaje: chore: sync carpeta completa"
  let msg = (input '📝 Mensaje de commit (Enter = "chore: sync carpeta completa"): ')
  let final_msg = (if ($msg | is-empty) { "chore: sync carpeta completa" } else { $msg })

  let reindex_q = (input "¿Forzar reindex (limpiar caché de Git)? s/N. Ejemplo: s : ")
  let reindex = (($reindex_q | str downcase) == "s")

  commit_all $final_msg $reindex
  if (has_origin) {
    if (has_upstream) { git push } else { git push -u origin HEAD }
  } else {
    print "⚠️  No hay remoto 'origin'. Usa la opción 2 para crear/configurar."
  }
  print "✅ Actualización completa enviada."
}

def accion_update_archivo [] {
  ensure_git_identity
  if not (is_repo_here) { print "❌ No es repo Git."; return }

  print "Ejemplo de ruta: src/app.js"
  let ruta = (input "📄 Ruta del archivo a actualizar: ")
  if ($ruta | is-empty) { print "❌ Ruta vacía."; return }
  if (ls $ruta | is-empty) { print "❌ El archivo no existe."; return }

  print 'Ejemplo de mensaje: fix: corrige bug en app.js'
  let msg = (input "📝 Mensaje de commit: ")
  if ($msg | is-empty) { print "❌ Mensaje vacío."; return }

  git add $ruta
  (git commit -m $msg | complete) | ignore
  if (has_origin) {
    if (has_upstream) { git push } else { git push -u origin HEAD }
  } else {
    print "⚠️  No hay remoto 'origin'. Usa la opción 2 para crear/configurar."
  }
  print "✅ Archivo actualizado y enviado."
}

def accion_update_cualquier [] {
  ensure_git_identity
  if not (is_repo_here) { print "❌ No es repo Git."; return }

  print "Ejemplos de ruta:"
  print " • carpeta completa: ./docs"
  print " • archivo específico: README.md"
  let ruta = (input "📦 ¿Qué quieres actualizar (archivo o carpeta)? (Enter = .): ")
  let target = (if ($ruta | is-empty) { "." } else { $ruta })

  print 'Ejemplo de mensaje: feat(docs): agrega tutorial'
  let msg = (input "📝 Mensaje de commit: ")
  if ($msg | is-empty) { print "❌ Mensaje vacío."; return }

  if ($target == ".") { git add -A } else { git add $target }
  (git commit -m $msg | complete) | ignore
  if (has_origin) {
    if (has_upstream) { git push } else { git push -u origin HEAD }
  } else {
    print "⚠️  No hay remoto 'origin'. Usa la opción 2 para crear/configurar."
  }
  print "✅ Actualización realizada."
}

# ---------------- menú ----------------

export def main [
  --ruta: string = "."
] {
  cd $ruta
  print $"📂 Carpeta base: (pwd)\n"

  loop {
    print "=============================="
    print "  MENÚ GIT / GITHUB"
    print "=============================="
    print "1) Configurar Git (nombre, correo)"
    print "2) Crear proyecto para GitHub (repo nuevo o conectar)"
    print "3) Analizar estado completo del proyecto"
    print "4) Actualización rápida de TODOS los archivos (carpeta)"
    print "5) Actualización rápida de SOLO UN archivo"
    print "6) Actualizar cualquier cosa (archivo o carpeta)"
    print "7) Salir"
    print "------------------------------"
    print "Ejemplo de elección: 2"
    let op = (input "👉 Elige una opción [1-7]: ")

    match ($op | str trim) {
      "1" => { accion_configurar }
      "2" => { accion_crear_proyecto }
      "3" => { accion_analizar }
      "4" => { accion_update_carpeta }
      "5" => { accion_update_archivo }
      "6" => { accion_update_cualquier }
      "7" => { print "👋 Saliendo…"; break }
      _   => { print "❓ Opción no válida. Intenta de nuevo.\n" }
    }
  }
}
