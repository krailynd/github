# update-repo.nu — Nushell
# Uso:
#   nu update-repo.nu [ruta=.] [-m "mensaje"] [--reindex] [--public]

# --- helpers estables ---

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

# Arranca ssh-agent y EXPORTA variables al entorno del llamador
def-env _start-ssh-agent [] {
  let out = (ssh-agent -s | complete).stdout
  let sock = ($out | lines | where {|x| $x | str starts-with "SSH_AUTH_SOCK="} | first | split row "=" | get 1 | split row ";" | get 0 | str trim)
  let pid  = ($out | lines | where {|x| $x | str starts-with "SSH_AGENT_PID="}  | first | split row "=" | get 1 | split row ";" | get 0 | str trim)
  if not ($sock | is-empty) { let-env SSH_AUTH_SOCK = $sock }
  if not ($pid  | is-empty) { let-env SSH_AGENT_PID = $pid }
}

def-env _ensure-ssh-agent-and-key [] {
  # crea llave si no existe
  if (ls ~/.ssh/id_ed25519 | is-empty) {
    let email = (_git-get "user.email")
    ssh-keygen -q -t ed25519 -C (if ($email | is-empty) { "wsl@local" } else { $email }) -f ~/.ssh/id_ed25519 -N ""
  }
  # intenta listar; si falla, arranca agente y vuelve a intentar
  if ((ssh-add -l | complete).exit_code != 0) { _start-ssh-agent }
  ssh-add ~/.ssh/id_ed25519 | ignore
}

def _is-repo-here [] { (git rev-parse --is-inside-work-tree | complete).exit_code == 0 }
def _has-origin   [] { (git remote | complete).stdout | lines | any {|it| $it == "origin"} }
def _has-upstream [] { (git rev-parse --abbrev-ref --symbolic-full-name '@{u}' | complete).exit_code == 0 }

def _safe-pull [] {
  if (_has-upstream) {
    git fetch --all --prune
    git pull --ff-only
  } else if (_has-origin) {
    echo "ℹ️  Rama sin upstream; omito pull (luego push -u)."
  } else {
    echo "ℹ️  No hay remoto 'origin'; omito pull."
  }
}

def _commit-all [msg: string, reindex: bool] {
  if $reindex { git rm -r --cached . | ignore }
  git add -A
  if ((git commit -m $msg | complete).exit_code != 0) { echo "ℹ️  Nada que commitear." }
}

def _gh-authed [] { _has-cmd gh and ((gh auth status | complete).exit_code == 0) }
def _gh-user   [] {
  let r = (gh api user | complete)
  if $r.exit_code == 0 { ($r.stdout | from json | get login) } else { "" }
}

def _repo-exists [owner: string, name: string] {
  if (_gh-authed) {
    (gh repo view $"($owner)/($name)" | complete).exit_code == 0
  } else {
    (git ls-remote $"git@github.com:($owner)/($name).git" | complete).exit_code == 0
  }
}

def _set-origin-and-push [owner: string, name: string] {
  git remote add origin $"git@github.com:($owner)/($name).git"
  if (_has-upstream) { git push } else { git push -u origin HEAD }
}

# --- comando principal ---

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
      echo "🌐 No hay 'origin'. Verificando remoto…"
      if (_gh-authed) {
        let owner = (if ($gh_owner | is-empty) { (input "Usuario GitHub: ") } else { $gh_owner })
        let vis   = (if $public { "--public" } else { "--private" })
        if (_repo-exists $owner $repo_name) {
          echo $"🔗 Existe ($owner)/($repo_name). Configurando origin…"
          _set-origin-and-push $owner $repo_name
        } else {
          echo $"🆕 Creando repo con gh: (if $public { "público" } else { "privado" })"
          gh repo create $repo_name $vis --source . --remote origin --push
        }
      } else {
        let owner = (input "Tu usuario de GitHub (SSH): ")
        if ($owner | is-empty) { echo "❌ Usuario vacío. Aborto."; return }
        if (_repo-exists $owner $repo_name) {
          echo "🔗 Repo remoto existe. Configurando origin…"
          _set-origin-and-push $owner $repo_name
        } else {
          echo "⚠️  Sin gh y el repo remoto no existe aún."
          echo $"   Crea '($owner)/($repo_name)' en GitHub y luego:"
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

  # --- no era repo: inicializar y subir ---
  echo "🆕 No es repo. Inicializando…"
  git init
  git branch -M main
  git add -A
  (git commit -m "feat: primer volcado de la carpeta" | complete) | ignore

  if (_gh-authed) {
    let owner = (if ($gh_owner | is-empty) { (input "Usuario GitHub: ") } else { $gh_owner })
    let vis   = (if $public { "--public" } else { "--private" })
    if (_repo-exists $owner $repo_name) {
      echo $"🔗 Existe ($owner)/($repo_name). Configurando origin…"
      _set-origin-and-push $owner $repo_name
    } else {
      echo $"🆕 Creando repo con gh: (if $public { "público" } else { "privado" })"
      gh repo create $repo_name $vis --source . --remote origin --push
    }
  } else {
    let owner = (input "Tu usuario de GitHub (SSH): ")
    if ($owner | is-empty) { echo "❌ Usuario vacío. Aborto."; return }
    if (_repo-exists $owner $repo_name) {
      echo "🔗 Repo remoto existe. Configurando origin…"
      _set-origin-and-push $owner $repo_name
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
