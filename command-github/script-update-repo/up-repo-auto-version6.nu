# update-repo.nu — Crea/actualiza repos y remotos en GitHub usando Nushell (WSL friendly)
# Uso:
#   nu update-repo.nu [ruta=.] [-m "mensaje"] [--reindex] [--public]

# ---------------- helpers ----------------

def has_cmd [name: string] { (which $name | is-empty) == false }

def git_get [key: string] {
  let r = (git config --global --get $key | complete)
  if $r.exit_code == 0 { $r.stdout | str trim } else { "" }
}

def set_git_if_missing [key: string, prompt: string] {
  let cur = (git_get $key)
  if ($cur | is-empty) {
    let val = (input $prompt)
    if not ($val | is-empty) { git config --global $key $val }
  }
}

def ensure_git_identity [] {
  set_git_if_missing "user.name"  "Git user.name (tu nombre): "
  set_git_if_missing "user.email" "Git user.email: "
}

# Exporta variables del ssh-agent al entorno del caller (SIN referenciar $out dentro de let-env)
def-env start_ssh_agent [] {
  let out = (ssh-agent -s | complete).stdout
  let sock_line = ($out | lines | where {|x| $x | str starts-with "SSH_AUTH_SOCK="} | first)
  let pid_line  = ($out | lines | where {|x| $x | str starts-with "SSH_AGENT_PID="}  | first)
  let sock = ($sock_line | str replace "SSH_AUTH_SOCK=" "" | split row ";" | get 0 | str trim)
  let pid  = ($pid_line  | str replace "SSH_AGENT_PID="  "" | split row ";" | get 0 | str trim)
  if not ($sock | is-empty) { let-env SSH_AUTH_SOCK = $sock }
  if not ($pid  | is-empty) { let-env SSH_AGENT_PID = $pid }
}

def-env ensure_ssh_agent_and_key [] {
  # crea llave si no existe
  if (ls ~/.ssh/id_ed25519 | is-empty) {
    let email = (git_get "user.email")
    echo "🔑 Creando llave SSH (~/.ssh/id_ed25519)…"
    ssh-keygen -q -t ed25519 -C (if ($email | is-empty) { "wsl@local" } else { $email }) -f ~/.ssh/id_ed25519 -N ""
  }
  # si no hay agente activo, arráncalo
  if ((ssh-add -l | complete).exit_code != 0) { start_ssh_agent }
  # añade la llave (ignora si ya está)
  ssh-add ~/.ssh/id_ed25519 | ignore
}

def is_repo_here [] { (git rev-parse --is-inside-work-tree | complete).exit_code == 0 }
def has_origin   [] { (git remote | complete).stdout | lines | any {|it| $it == "origin"} }
def has_upstream [] { (git rev-parse --abbrev-ref --symbolic-full-name '@{u}' | complete).exit_code == 0 }

def safe_pull [] {
  if (has_upstream) {
    git fetch --all --prune
    git pull --ff-only
  } else if (has_origin) {
    echo "ℹ️  Rama sin upstream; omito pull (luego push -u)."
  } else {
    echo "ℹ️  No hay remoto 'origin'; omito pull."
  }
}

def commit_all [msg: string, reindex: bool] {
  if $reindex { git rm -r --cached . | ignore }
  git add -A
  if ((git commit -m $msg | complete).exit_code != 0) { echo "ℹ️  Nada que commitear." }
}

def gh_authed [] { has_cmd gh and ((gh auth status | complete).exit_code == 0) }

def gh_user [] {
  let r = (gh api user | complete)
  if $r.exit_code == 0 { ($r.stdout | from json | get login) } else { "" }
}

def repo_exists [owner: string, name: string] {
  if (gh_authed) {
    (gh repo view $"($owner)/($name)" | complete).exit_code == 0
  } else {
    (git ls-remote $"git@github.com:($owner)/($name).git" | complete).exit_code == 0
  }
}

def set_origin_and_push [owner: string, name: string] {
  git remote add origin $"git@github.com:($owner)/($name).git"
  if (has_upstream) { git push } else { git push -u origin HEAD }
}

# ---------------- comando principal ----------------

export def main [
  ruta: string = "."
  --message(-m): string = "chore: sync carpeta completa"
  --reindex
  --public
] {
  cd $ruta
  echo $"📂 Carpeta: (pwd)"

  ensure_git_identity
  ensure_ssh_agent_and_key

  let repo_name = ($env.PWD | path basename)
  let gh_owner  = (if (gh_authed) { gh_user } else { "" })

  if (is_repo_here) {
    echo "📦 Repo existente."
    safe_pull
    commit_all $message $reindex

    if not (has_origin) {
      echo "🌐 No hay 'origin'. Verificando remoto…"
      if (gh_authed) {
        let owner = (if ($gh_owner | is-empty) { (input "Usuario GitHub: ") } else { $gh_owner })
        let vis   = (if $public { "--public" } else { "--private" })
        if (repo_exists $owner $repo_name) {
          echo $"🔗 Existe ($owner)/($repo_name). Configurando origin…"
          set_origin_and_push $owner $repo_name
        } else {
          echo $"🆕 Creando repo con gh: (if $public { "público" } else { "privado" })"
          gh repo create $repo_name $vis --source . --remote origin --push
        }
      } else {
        let owner = (input "Tu usuario de GitHub (SSH): ")
        if ($owner | is-empty) { echo "❌ Usuario vacío. Aborto."; return }
        if (repo_exists $owner $repo_name) {
          echo "🔗 Repo remoto existe. Configurando origin…"
          set_origin_and_push $owner $repo_name
        } else {
          echo "⚠️  Sin gh y el repo remoto no existe aún."
          echo $"   Crea '($owner)/($repo_name)' en GitHub y luego:"
          echo $"   git remote add origin git@github.com:($owner)/($repo_name).git"
          echo "   git push -u origin main"
          return
        }
      }
    } else {
      if (has_upstream) { git push } else { git push -u origin HEAD }
    }
    echo "✅ Listo."
    return
  }

  # --- no era repo: inicializar y subir ---
  echo "🆕 No es repo. Inicializando…"
  git init
  git branch -M main
  git add -A
  (git commit -m "feat: primer volcado de la carpeta" | complete) | ignore

  if (gh_authed) {
    let owner = (if ($gh_owner | is-empty) { (input "Usuario GitHub: ") } else { $gh_owner })
    let vis   = (if $public { "--public" } else { "--private" })
    if (repo_exists $owner $repo_name) {
      echo $"🔗 Existe ($owner)/($repo_name). Configurando origin…"
      set_origin_and_push $owner $repo_name
    } else {
      echo $"🆕 Creando repo con gh: (if $public { "público" } else { "privado" })"
      gh repo create $repo_name $vis --source . --remote origin --push
    }
  } else {
    let owner = (input "Tu usuario de GitHub (SSH): ")
    if ($owner | is-empty) { echo "❌ Usuario vacío. Aborto."; return }
    if (repo_exists $owner $repo_name) {
      echo "🔗 Repo remoto existe. Configurando origin…"
      set_origin_and_push $owner $repo_name
    } else {
      echo "⚠️  'gh' no está y el repo remoto no existe aún."
      echo $"   Crea '($owner)/($repo_name)' en GitHub y luego:"
      echo $"   git remote add origin git@github.com:($owner)/($repo_name).git"
      echo "   git push -u origin main"
      return
    }
  }
  echo "✅ Listo."
}
