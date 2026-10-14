#!/usr/bin/env bash
set -Eeuo pipefail

release_sha="${1:?release SHA is required}"
deploy_root="${2:?deployment directory is required}"

if [[ ! "$release_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Invalid release SHA" >&2
  exit 2
fi
if [[ ! "$deploy_root" =~ ^/[A-Za-z0-9._/-]+$ || "$deploy_root" == / || "$deploy_root" == */ || "$deploy_root" == *//* || "$deploy_root" == *'/../'* || "$deploy_root" == */.. || "$deploy_root" == *'/./'* || "$deploy_root" == */. ]]; then
  echo "Deployment directory must be a normalized absolute path" >&2
  exit 2
fi
if [[ -L "$deploy_root" || ! -d "$deploy_root" ]]; then
  echo "Deployment directory must already exist and must not be a symbolic link" >&2
  exit 2
fi
resolved_deploy_root="$(cd -P "$deploy_root" && pwd -P)"
if [[ "$resolved_deploy_root" != "$deploy_root" ]]; then
  echo "Deployment directory path must not contain symbolic links" >&2
  exit 2
fi
deploy_root="$resolved_deploy_root"

image_archive="/tmp/stroy-website-${release_sha}.image.tar.gz"
source_archive="/tmp/stroy-website-${release_sha}.source.tar.gz"
releases_dir="${deploy_root}/releases"
release_dir="${releases_dir}/${release_sha}"
staging_dir="${deploy_root}/releases/.${release_sha}.tmp.$$"
previous_release=""
previous_image_id=""
deployment_started=0
next_link=""

current_link="${deploy_root}/current"
if [[ -e "$current_link" && ! -L "$current_link" ]]; then
  echo "The current release pointer must be a symbolic link" >&2
  exit 2
fi
if [[ -L "$current_link" ]]; then
  previous_release="$(readlink -f "$current_link" || true)"
  case "$previous_release" in
    "$releases_dir"/*) ;;
    *) echo "The current release pointer must target a release under $releases_dir" >&2; exit 2 ;;
  esac
  if [[ ! -d "$previous_release" || -L "$previous_release" || \
      ! -d "$previous_release/website" || -L "$previous_release/website" || \
      ! -f "$previous_release/website/docker-compose.yml" || \
      -L "$previous_release/website/docker-compose.yml" ]]; then
    echo "The current release does not contain a regular website Compose file" >&2
    exit 2
  fi
fi
if docker inspect stroy-website >/dev/null 2>&1; then
  previous_image_id="$(docker inspect --format '{{.Image}}' stroy-website)"
fi

restore_compose() {
  local compose_file="$1"
  docker compose -p website \
    -f "$compose_file" \
    -f <(printf 'services:\n  stroy-website:\n    image: stroy-website:production\n') \
    up --detach --no-build --wait --wait-timeout 120
}

rollback() {
  local status=$?
  trap - EXIT

  if (( status != 0 && deployment_started == 1 )); then
    echo "Website deploy failed; restoring the previous image" >&2
    if [[ -n "$previous_image_id" ]]; then
      if docker image tag "$previous_image_id" stroy-website:production; then
        if [[ -n "$previous_release" && -f "$previous_release/website/docker-compose.yml" ]]; then
          restore_compose "$previous_release/website/docker-compose.yml" || echo "Rollback Compose failed; inspect the website service manually" >&2
        elif [[ -f "$release_dir/website/docker-compose.yml" ]]; then
          restore_compose "$release_dir/website/docker-compose.yml" || echo "Rollback Compose failed; inspect the website service manually" >&2
        fi
      else
        echo "Could not restore the previous image tag; inspect the website service manually" >&2
      fi
    else
      echo "No previous website image was available for rollback" >&2
    fi
  fi

  rm -f "$image_archive" "$source_archive"
  if [[ -n "$next_link" ]]; then
    rm -f "$next_link"
  fi
  rm -rf "$staging_dir"
  exit "$status"
}
trap rollback EXIT

if [[ -n "$previous_image_id" && ( -z "$previous_release" || ! -f "$previous_release/website/docker-compose.yml" ) ]]; then
  echo "Set current to a snapshot of the active Compose configuration before replacing an existing website" >&2
  exit 2
fi

[[ -f "$image_archive" && -f "$source_archive" ]]
if [[ -L "$releases_dir" || ( -e "$releases_dir" && ! -d "$releases_dir" ) ]]; then
  echo "Release history path must be a regular directory" >&2
  exit 2
fi
mkdir -p "$releases_dir"
if [[ -L "$release_dir" || ( -e "$release_dir" && ! -d "$release_dir" ) ]]; then
  echo "Release path must be a regular directory" >&2
  exit 2
fi

if [[ -d "$release_dir" ]]; then
  if [[ ! -d "$release_dir/website" || -L "$release_dir/website" || \
      ! -f "$release_dir/website/docker-compose.yml" || \
      -L "$release_dir/website/docker-compose.yml" ]]; then
    echo "Existing release does not contain a regular website Compose file" >&2
    exit 2
  fi
else
  source_members="$(tar -tzf "$source_archive")"
  if [[ "$source_members" != "website/docker-compose.yml" ]]; then
    echo "Unexpected paths in website deployment archive" >&2
    exit 2
  fi
  if ! tar -tvzf "$source_archive" | awk 'NR == 1 && substr($0, 1, 1) == "-" { valid = 1; next } { invalid = 1 } END { exit invalid || !valid }'; then
    echo "Website deployment archive may contain only a regular Compose file" >&2
    exit 2
  fi
  mkdir -m 750 "$staging_dir"
  tar -xzf "$source_archive" -C "$staging_dir"
  [[ -d "$staging_dir/website" && ! -L "$staging_dir/website" ]]
  [[ -f "$staging_dir/website/docker-compose.yml" && ! -L "$staging_dir/website/docker-compose.yml" ]]
  mv "$staging_dir" "$release_dir"
fi

docker load --input "$image_archive" >/dev/null
deployment_started=1
docker compose -p website -f "$release_dir/website/docker-compose.yml" \
  up --detach --no-build --wait --wait-timeout 120

next_link="${deploy_root}/.current-${release_sha}-$$"
ln -s "$release_dir" "$next_link"
mv -Tf "$next_link" "${deploy_root}/current"

echo "Deployed website revision $release_sha"
