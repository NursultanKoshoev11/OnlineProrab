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

image_archive="/tmp/stroy-website-${release_sha}.image.tar.gz"
source_archive="/tmp/stroy-website-${release_sha}.source.tar.gz"
release_dir="${deploy_root}/releases/${release_sha}"
staging_dir="${deploy_root}/releases/.${release_sha}.tmp.$$"
previous_release=""
previous_image_id=""
deployment_started=0
next_link=""

if [[ -L "${deploy_root}/current" ]]; then
  previous_release="$(readlink -f "${deploy_root}/current" || true)"
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
mkdir -p "${deploy_root}/releases"

if [[ ! -d "$release_dir" ]]; then
  mkdir -m 750 "$staging_dir"
  while IFS= read -r entry; do
    case "$entry" in
      website/docker-compose.yml) ;;
      *) echo "Unexpected path in website deployment archive" >&2; exit 2 ;;
    esac
    case "/$entry/" in
      */../*) echo "Parent traversal in website deployment archive" >&2; exit 2 ;;
    esac
  done < <(tar -tzf "$source_archive")
  tar -xzf "$source_archive" -C "$staging_dir"
  [[ -f "$staging_dir/website/docker-compose.yml" ]]
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
