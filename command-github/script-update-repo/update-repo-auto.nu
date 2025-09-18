# update-repo.nu  —  Actualiza (o crea) un repo y sube TODO
# Uso:
#   nu update-repo.nu [ruta=.] [-m "mensaje"] [--reindex] [--public]
#
# Ejemplos:
#   nu update-repo.nu .
#   nu update-repo.nu ~/java-proyects -m "feat: sube cambios" --reindex
#   nu update-repo.nu . --public   # si se crea repo nuevo con gh

export def main [
  ruta: string = "."
  --message(-m): string = "chore: sync carpeta completa"
  --reindex       # rehace índice: útil tras cambiar .gitignore
  --public        # si creamos repo con gh, será público (por defecto privado)
] {

  # 1) entrar a la ruta objetivo
  cd $ruta

  # utilidades
  def _has_upstream [] {
    git rev-parse --abbrev-ref --symbolic-full-name '@{u}' | ignore
    $env.LAST_EXIT_CODE == 0
  }

  def _has_remote_origin [] {
    git remote | lines | any {|it| $it == "origin" }
  }

  def _has_cmd [name: string] {
    (which $name | is-empty) == false
  }

  def _safe_pull [] {
    if (_has_upstream) {
      git fetch --all --prune
      git pull --ff-only
    } else if (_has_remote_origin) {
      # no upstream en esta rama: no hacemos pull, ya haremos push -u
      echo "ℹ️  No hay upstream configurado para esta rama; se omitirá pull."
    } else {
      echo "ℹ️  No hay remoto 'origin'; se omitirá pull."
    }
  }

  def _commit_all [msg: string, reindex: bool] {
    if $reindex {
      git rm -r --cached .
    }
    git add -A
    git commit -m $msg
    if ($env.LAST_EXIT_CODE != 0) {
      echo "ℹ️  Nada que commitear (working tree clean)."
    }
  }

  def _push [] {
    if (_has_upstream) {
      git push
    } else if (_has_remote_origin) {
      git push -u origin HEAD
    } else {
      echo "⚠️  No existe remoto 'origin'."
      return
    }
  }

  # 2) ¿es un repo?
  git rev-parse --is-inside-work-tree | ignore
  let is_repo = ($env.LAST_EXIT_CODE == 0)

  if $is_repo {
    echo $"📦 Repo existente en (pwd): (pwd)"
    _safe_pull
    _commit_all $message $reindex
    _push
    echo "✅ Listo."
    return
  }

  # 3) No era repo: inicializar y (si hay gh) crear remoto + push
  echo $"🆕 Inicializando repo nuevo en: (pwd)"
  git init
  git branch -M main
  git add -A
  git commit -m "feat: primer volcado de la carpeta"
  if (_has_cmd gh) {
    let name = ($env.PWD | path basename)
    let vis  = (if $public { "--public" } else { "--private" })
    # crea repo en tu cuenta y lo sube
    gh repo create $name $vis --source . --remote origin --push
    if ($env.LAST_EXIT_CODE == 0) {
      echo "✅ Repo remoto creado con gh y primer push realizado."
    } else {
      echo "⚠️  Falló crear/pushear con gh. Añade remoto manualmente y ejecuta de nuevo:"
      echo "    git remote add origin git@github.com:TU_USUARIO/REPO.git"
      echo "    git push -u origin main"
    }
  } else {
    echo "ℹ️  'gh' no está instalado. Añade el remoto y sube manualmente:"
    echo "    git remote add origin git@github.com:TU_USUARIO/REPO.git"
    echo "    git push -u origin main"
  }
}
