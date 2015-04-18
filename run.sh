#!/bin/sh

set -o pipefail
set -e

cyan='\033[0;36m'
blue='\033[0;34m'
no_color='\033[0m' # No Color

echo "${cyan}Stopping the backend container and removing its image...${no_color}"
docker rm -f backend &>/dev/null || true
docker rmi -f backend-image &>/dev/null || true
echo "${cyan}Building a new backend image...${no_color}"
docker build -t="backend-image" --force-rm hosts/backend
echo "${cyan}Starting a new backend image...${no_color}"
docker run --name backend -d backend-image

echo "${cyan}Fetching Lua depedencies...${no_color}"
function load_dependency {
    local target="$1"
    local user="$2"
    local repo="$3"
    local commit="$4"

    if [ -e "$target" ]; then
        echo "Dependency $target already downloaded."
    else
        curl https://codeload.github.com/$user/$repo/tar.gz/$commit | tar -xz --strip 1 $repo-$commit/lib
    fi
}

load_dependency "lib/resty/jwt.lua" "SkyLothar" "lua-resty-jwt" "586a507f9e57555bdd7a7bc152303c91b4a04527"
load_dependency "lib/resty/hmac.lua" "jkeys089" "lua-resty-hmac" "67bff3fd6b7ce4f898b4c3deec7a1f6050ff9fc9"
load_dependency "lib/basexx.lua" "aiq" "basexx" "c91cf5438385d9f84f53d3ef27f855c52ec2ed76"

# build proxy containers and images

echo "${cyan}Building base proxy image, if necessary...${NC}"
image_exists=$(docker images | grep "proxy-base-image") || true
if [ -z "$image_exists" ]; then
    echo "${blue}Building image${no_color}"
    docker build -t="proxy-base-image" --force-rm hosts/proxy
else
    echo "${blue}Base image already exists${no_color}"
fi

for proxy_dir in hosts/proxy/*; do
    [ -d "${proxy_dir}" ] || continue # if not a directory, skip

    proxy_name="$(basename $proxy_dir)"
    echo "${cyan}Building container and image for the '$proxy_name' proxy (Nginx) host...${no_color}"

    echo "${blue}Deploying Lua scripts and depedencies${no_color}"
    rm -rf hosts/proxy/$proxy_name/nginx/lua
    mkdir -p hosts/proxy/$proxy_name/nginx/lua
    cp nginx-jwt.lua hosts/proxy/$proxy_name/nginx/lua
    cp -r lib/ hosts/proxy/$proxy_name/nginx/lua

    echo "${blue}Stopping the container and removing the image${no_color}"
    docker rm -f "proxy-$proxy_name" &>/dev/null || true
    docker rmi -f "proxy-$proxy_name-image" &>/dev/null || true

    echo "${blue}Building the new image${no_color}"
    docker build -t="proxy-$proxy_name-image" --force-rm hosts/proxy/$proxy_name

    host_port="$(cat hosts/proxy/$proxy_name/host_port)"
    echo "${blue}Staring new container, binding it to Docker host port $host_port${no_color}"
    docker run --name "proxy-$proxy_name" -d -p $host_port:80 --link backend:backend "proxy-$proxy_name-image"
done

echo "${cyan}Running integration tests:${no_color}"
cd test
# make sure npm packages are installed
npm install
# run tests
npm test

echo "${cyan}Proxy:${no_color}"
echo curl http://$(boot2docker ip)
