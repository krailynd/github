# update-repo.nu — Sube/actualiza un repo completo (crea remoto si falta)
# Uso:
#   nu update-repo.nu [ruta=.] [-m "mensaje"] [--reindex] [--public]
#
# Requisitos: git. Opcional: gh (GitHub CLI) para crear el repo remoto sin pedir usuario.

export def main [
  ruta: string = "."
  --message(-m): string = "chore: sync carpeta completa"
  --reindex       # rehace índice si cambiaste .gitignore
  --public        # si se crea repo con gh, será público (por defecto privado)
] {
  cd $ruta

  # ---------- helpers ----------
  def _has_cmd [name: string] { (which $name | is-empty) == false }
  def _git_cfg [key: string] { (git config --global --get $key | complete).stdout | str trim }
  def _set_if_missing [key: string, prompt: string] {
    let val = (_git_cfg $key)
    if ($val | is-empty) {
      let nuevo = (input $prompt)
      if not ($nuevo | is-empty) { git config --global $key $nuevo }
    }
  }
  def _ensure_git_identity [] {
    _set_if_missing "user.name"  "Git user.name (tu nombre): "
    _set_if_missing "user.email" "Git user.email: "
  }
  def _ensure_ssh_key [] {
    if (ls ~/.ssh/id_ed25519 | is-empty) {
      echo "🔑 No hay llave SSH (~/.ssh/id_ed25519). Creando…"
      let email = (_git_cfg "user.email")
      ssh-keygen -t ed25519 -C (if ($email | is-empty) { "wsl@local" } else { $email }) -f ~/.ssh/id_ed25519 -N ""
    }
    # inicia ssh-agent y añade la llave (modo Nushell)
    let agent = (ssh-agent -s | lines)
    let-env SSH_AUTH_SOCK = (
      $agent | where ($it | str starts-with 'SSH_AUTH_SOCK=') | first
      | str replace 'SSH_AUTH_SOCK=' '' | split row ';' | get 0 | str trim
    )
    let-env SSH_AGENT_PID = (
      $agent | where ($it | str starts-with 'SSH_AGENT_PID=') | first
      | str replace 'SSH_AGENT_PID=' '' | split row ';' | get 0 | str trim
    )
    ssh-add ~/.ssh/id_ed25519 | ignore
  }
  def _has_upstream [] {
    git rev-parse --abbrev-ref --symbolic-full-name '@{u}' | ignore
    $env.LAST_EXIT_CODE == 0
  }
  def _has_remote_origin [] { git remote | lines | any {|it| $it == "origin"} }
  def _safe_pull [] {
    if (_has_upstream) {
      git fetch --all --prune
      git pull --ff-only
    } else if (_has_remote_origin) {
      echo "ℹ️  Rama sin upstream; se omitirá pull (luego haremos push -u)."
    } else {
      echo "ℹ️  No existe remoto 'origin'; se omitirá pull."
    }
  }
  def _commit_all [msg: string, reindex: bool] {
    if $reindex { git rm -r --cached . | ignore }
    git add -A
    git commit -m $msg
    if ($env.LAST_EXIT_CODE != 0) { echo "ℹ️  Nada que commitear (working tree clean)." }
  }
  def _push [] {
    if (_has_upstream) { git push }
    else if (_has_remote_origin) { git push -u origin HEAD }
    else { echo "⚠️  No existe remoto 'origin'." }
  }
  def _gh_authed [] {
    if not (_has_cmd gh) { return false }
    gh auth status | ignore
    $env.LAST_EXIT_CODE == 0
  }

  # ---------- inicio ----------
  echo $"📂 Carpeta: (pwd)"
  _ensure_git_identity
  _ensure_ssh_key

  git rev-parse --is-inside-work-tree | ignore
  let is_repo = ($env.LAST_EXIT_CODE == 0)

  if $is_repo {
    echo "📦 Repo existente."
    _safe_pull
    _commit_all $message $reindex

    if not (_has_remote_origin) {
      echo "🌐 No hay 'origin'. Vamos a crearlo…"
      if (_gh_authed) {
        let name = ($env.PWD | path basename)
        let vis  = (if $public { "--public" } else { "--private" })
        gh repo create $name $vis --source . --remote origin --push
      } else {
        let user = (input "Tu usuario de GitHub (para remoto SSH): ")
        if ($user | is-empty) { echo "❌ Usuario vacío. Aborta."; return }
        let repo = ($env.PWD | path basename)
        git remote add origin $"git@github.com:($user)/($repo).git"
        git push -u origin HEAD
      }
    } else {
      _push
    }
    echo "✅ Listo."
    return
  }

  # No era repo → inicializar y crear remoto/push
  echo "🆕 No es repo. Inicializando…"
  git init
  git branch -M main
  git add -A
  git commit -m "feat: primer volcado de la carpeta"

  if (_gh_authed) {
    let name = ($env.PWD | path basename)
    let vis  = (if $public { "--public" } else { "--private" })
    gh repo create $name $vis --source . --remote origin --push
    if ($env.LAST_EXIT_CODE == 0) { echo "✅ Repo remoto creado y subido con gh." }
    else { echo "⚠️  Falló gh; agrega remoto SSH manual y haz push." }
  } else {
    echo "ℹ️  'gh' no disponible o no autenticado."
    let user = (input "Tu usuario de GitHub (para remoto SSH): ")
    if ($user | is-empty) { echo "❌ Usuario vacío. Agrega remoto luego y haz push."; return }
    let repo = ($env.PWD | path basename)
    git remote add origin $"git@github.com:($user)/($repo).git"
    git push -u origin main
    echo "✅ Repo subido por SSH."
  }
}
