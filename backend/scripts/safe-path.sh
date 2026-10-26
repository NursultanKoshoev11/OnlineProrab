safe_directory_path() {
  path="$1"
  label="$2"

  case "$path" in
    /*) ;;
    *) echo "$label must be an absolute path" >&2; return 2 ;;
  esac
  case "$path" in
    /|*/|*//*|*/./*|*/../*|*/.|*/..) echo "$label must not be root or contain non-normal path segments" >&2; return 2 ;;
  esac

  parent="$(dirname "$path")"
  name="$(basename "$path")"
  if [ "$parent" = "/" ]; then
    echo "$label must be a dedicated directory below a non-root parent" >&2
    return 2
  fi

  check_parent_components() {
    candidate="$1"
    current="/"
    remainder="${candidate#/}"
    while [ -n "$remainder" ]; do
      component="${remainder%%/*}"
      if [ "$remainder" = "$component" ]; then
        remainder=""
      else
        remainder="${remainder#*/}"
      fi
      current="${current%/}/$component"
      if [ -L "$current" ]; then
        echo "$label parent must not contain symbolic links" >&2
        return 2
      fi
    done
  }

  check_parent_components "$parent" || return $?
  if [ ! -d "$parent" ]; then
    mkdir -p "$parent" || { echo "could not create parent directory for $label" >&2; return 2; }
  fi
  check_parent_components "$parent" || return $?
  parent="$(CDPATH= cd "$parent" && pwd -P)" || { echo "could not resolve parent directory for $label" >&2; return 2; }

  path="$parent/$name"
  if [ -L "$path" ]; then
    echo "$label must not be a symbolic link" >&2
    return 2
  fi
  if [ -e "$path" ] && [ ! -d "$path" ]; then
    echo "$label must be a directory" >&2
    return 2
  fi
  printf '%s\n' "$path"
}
