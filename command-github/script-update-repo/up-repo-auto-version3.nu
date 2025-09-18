# update-repo.nu — Crea/actualiza repos y remotos GitHub en Nushell (sin bash)
# Uso:
#   nu update-repo.nu [ruta=.] [-m "mensaje"] [--reindex] [--public]
# Ejemplos:
#   nu update-repo.nu .
#   nu update-repo.nu ~/java-proyects -m "feat: cambios de hoy" --reindex
#   nu update-repo.nu . --public   # crea repo público si no existe (requiere gh)

# ---------- helpers de nivel superior (evita problemas de parseo) ----------
def _has-cmd [name: string] { (which $name | is-empty) == false }

def _git-get [key: string] {
  let r = (git config --global --get $key | complete)
  if $r.exit_code == 0 { $r.stdout | str trim } else { "" }
}

def _set-git-if-missing [key: string, prompt: string] {
  let cur = (_git-get $key)
  if ($cur | is-empty) {
    let val = (input $prompt)
    if not ($val | is-empty) { git config --global $key $val }
  }
}

def _ensure-git-identity [] {
  _set-git-if-missing "user.name"  "Git user.name (tu nombre): "
  _set-git-if-missing "user.email" "Git user.email: "
}

def _ensure-ssh-agent-and-key [] {
  # crea llave si no existe
  if (ls ~/.ssh/id_ed25519 | is-empty) {
    let email = (_git-get "user.email")
    echo "🔑 Creando llave SSH (~/.ssh/id_ed25519)…"
    ssh-keygen -q -t ed25519 -C (if ($email | is-empty) { "wsl@local" } else { $email }) -f ~/.ssh/id_ed25519 -N ""
  }

  # si no hay agente cargado, arrancar uno y exportar variables (una sola línea cada let-env)
  let add_try = (ssh-add -l | complete)
  if $add_try.exit_code != 0 {
    let agent_out = (ssh-agent -s | complete).stdout
    let sock = ($agent_out | lines | where {|x| $x | str starts-with "SSH_AUTH_SOCK="} | first | split row "=" | get 1 | split row ";" | get 0 | str trim)
    let pid  = ($agent_out | lines | where {|x| $x | str starts-with "SSH_AGENT_PID="}  | first | split row "=" | get 1 | split row ";" | get 0 | str trim)
    if not ($sock | is-empty) { let-env SSH_AUTH_SOCK = $sock }
    if not ($pid  | is-empty) { let-env SSH_AGENT_PID = $pid  }
  }

  # añade la llave (ignora si ya estaba)
  ssh-add ~/.ssh/id_ed25519 | ignore
}

def _is-repo-here [] { (git rev-parse --is-inside-work-tree | complete).exit_code == 0 }

def _has-origin [] {
  let rem = (git remote | complete).stdout | lines
  $rem | any {|it| $it == "origin" }
}

def _has-upstream [] {
  let r = (git rev-parse --abbrev-ref --symbolic-full-name '@{u}' | complete)
  $r.exit_code == 0
}

def _safe-pull [] {
  if (_has-upstream) {
    git fetch --all --prune
    git pull --ff-only
  } else if (_has-origin) {
    echo "ℹ️  Rama sin upstream; omito pull (se hará push -u)."
  } else {
    echo "ℹ️  No hay remoto 'origin'; omito pull."
  }
}

def _commit-all [msg: string, reindex: bool] {
  if $reindex { git rm -r --cached . | ignore }
  git add -A
  let c = (git commit -m $msg | complete)
  if $c.exit_code != 0 { echo "ℹ️  Nada que commitear (working tree clean)." }
}

def _gh-authed [] {
  if not (_has-cmd gh) { return false }
  (gh auth status | complete).exit_code == 0
}

def _gh-user [] {
  let r = (gh api user | complete)
  if $r.exit_code == 0 {
    ($r.stdout | from json | get login)
  } else { "" }
}

def _repo-exists-github [owner: string, name: string] {
  if (_gh-authed) {
    (gh repo view $"($owner)/($name)" | complete).exit_code == 0
  } else {
    # sondeo por SSH; devuelve 0 si existe/visible
    (git ls-remote $"git@github.com:($owner)/($name).git" | complete).exit_code == 0
  }
}

def _set-origin-and-push [owner: string, name: string] {
  git remote add origin $"git@github.com:($owner)/($name).git"
  if (_has-upstream) { git push } else { git push -u origin HEAD }
}

# ---------- comando principal ----------
export def main [
  ruta: string = "."
  --message(-m): string = "chore: sync carpeta completa"
  --reindex
  --public
] {
  cd $ruta
  echo $"📂 Carpeta: (pwd)"
  _ensure-git-identity
  _ensure-ssh-agent-and-key

  let repo_name = ($env.PWD | path basename)
  let gh_owner  = (if (_gh-authed) { _gh-user } else { "" })

  if (_is-repo-here) {
    echo "📦 Repo existente."
    _safe-pull
    _commit-all $message $reindex

    if not (_has-origin) {
      echo "🌐 No hay 'origin'. Verificando cuenta y remoto…"
      if (_gh-authed) {
        let vis = (if $public { "--public" } else { "--private" })
        # Si ya existe, gh falla; por eso primero consultamos
        if (_repo-exists-github (if ($gh_owner | is-empty) { (input "Usuario GitHub: ") } else { $gh_owner }) $repo_name) {
          let owner = (if ($gh_owner | is-empty) { (input "Usuario GitHub: ") } else { $gh_owner })
          echo $"🔗 Repo ($owner)/($repo_name) ya existe. Configurando origin…"
          _set-origin-and-push $owner $repo_name
        } else {
          echo $"🆕 Creando repo en GitHub con gh: (if $public { "público" } else { "privado" })"
          gh repo create $repo_name $vis --source . --remote origin --push
        }
      } else {
        let owner = (input "Tu usuario de GitHub (para remoto SSH): ")
        if ($owner | is-empty) { echo "❌ Usuario vacío. Aborto."; return }
        if (_repo-exists-github $owner $repo_name) {
          echo "🔗 Repo remoto existe. Configurando origin…"
          _set-origin-and-push $owner $repo_name
        } else {
          echo "⚠️  No hay gh y el repo remoto aún no existe."
          echo $"   Crea '($owner)/($repo_name)' en GitHub y luego ejecuta:"
          echo $"   git remote add origin git@github.com:($owner)/($repo_name).git"
          echo "   git push -u origin main"
          return
        }
      }
    } else {
      if (_has-upstream) { git push } else { git push -u origin HEAD }
    }
    echo "✅ Listo."
    return
  }

  # --- No era repo: inicializar y subir ---
  echo "🆕 No es repo. Inicializando…"
  git init
  git branch -M main
  git add -A
  (git commit -m "feat: primer volcado de la carpeta" | complete) | ignore

  if (_gh-authed) {
    let vis = (if $public { "--public" } else { "--private" })
    if (_repo-exists-github (if ($gh_owner | is-empty) { (input "Usuario GitHub: ") } else { $gh_owner }) $repo_name) {
      let owner = (if ($gh_owner | is-empty) { (input "Usuario GitHub: ") } else { $gh_owner })
      echo $"🔗 Repo ($owner)/($repo_name) existe. Configurando origin…"
      _set-origin-and-push $owner $repo_name
    } else {
      echo $"🆕 Creando repo en GitHub con gh: (if $public { "público" } else { "privado" })"
      gh repo create $repo_name $vis --source . --remote origin --push
    }
  } else {
    let owner = (input "Tu usuario de GitHub (para remoto SSH): ")
    if ($owner | is-empty) { echo "❌ Usuario vacío. Aborto."; return }
    if (_repo-exists-github $owner $repo_name) {
      echo "🔗 Repo remoto existe. Configurando origin…"
      _set-origin-and-push $owner $repo_name
    } else {
      echo "⚠️  'gh' no está disponible y el repo remoto no existe aún."
      echo $"   Crea '($owner)/($repo_name)' en GitHub y luego ejecuta:"
      echo $"   git remote add origin git@github.com:($owner)/($repo_name).git"
      echo "   git push -u origin main"
      return
    }
  }
  echo "✅ Listo."
}
