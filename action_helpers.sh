#!/bin/bash

set -e

function lunarg_get_latest_sdk_version() {
  local platform=$1
  local url=https://vulkan.lunarg.com/sdk/latest/$platform.txt
  echo "note: resolving latest via webservices lookup: $url" >&2
  curl -sL https://vulkan.lunarg.com/sdk/latest/$platform.txt
}

remote_url_used=
function lunarg_fetch_sdk_config() {
  local platform=$1 query_version=$2
  remote_url_used=https://vulkan.lunarg.com/sdk/config/$query_version/$platform/config.json
  curl -sL $remote_url_used
}

function resolve_vulkan_sdk_environment() {
  local query_version=$1
  local config_file=$2
  local sdk_components=$(echo "$3" | xargs echo | sed -e 's@[,; ]\+@;@g')
  
  local base_dir=$PWD
  local platform=unknown
  
  case `uname -s` in
    Darwin) platform=mac ;;
    Linux) platform=linux ;;
    MINGW*)
      platform=windows
      base_dir=$(pwd -W)
    ;;
  esac
  
  build_dir=$base_dir/_vulkan_build
  test -d $build_dir || mkdir -v $build_dir

  VULKAN_SDK=$base_dir/VULKAN_SDK
  test -d $VULKAN_SDK || mkdir -v $VULKAN_SDK

  if [[ -z "$config_file" ]] ; then
    test -n "$query_version"
    config_file=$build_dir/config.json
    lunarg_fetch_sdk_config $platform $query_version > $config_file
  fi

  test -s $config_file
  sdk_version=$(jq .version $config_file)
  test -n $sdk_version
  test $sdk_version != null
  
  (
    echo VULKAN_SDK_BUILD_DIR=$build_dir
    echo VULKAN_SDK=$VULKAN_SDK
    echo VULKAN_SDK_PLATFORM=$platform
    echo VULKAN_SDK_QUERY_URL=$remote_url_used
    echo VULKAN_SDK_QUERY_VERSION=$query_version
    echo VULKAN_SDK_CONFIG_FILE=$config_file
    echo VULKAN_SDK_CONFIG_VERSION=$sdk_version
    echo VULKAN_SDK_COMPONENTS=\"$sdk_components\"
    case `uname -s` in
      MINGW*)
        # # declare > $build_dir/_system.env
        # function vsdevenv() {
        #     local tmpfile=$(mktemp -p $PWD);
        #     echo "#!/bin/bash" > $tmpfile
        #     for x in "$@" ; do echo -n "\"""$x""\" " >> $tmpfile; done
        #     echo >> $tmpfile
        #     # cat $tmpfile >&2
        #     cmd //q //c "$vsdevcmd -no_logo -arch=amd64 -host_arch=amd64 && bash $tmpfile";
        #     rm $tmpfile
        # }
        # vsdevcmd=$(cygpath -ms /c/Program\ Files\ \(x86\)/Microsoft\ Visual\ Studio/*/*/Common7/Tools/vsdevcmd.bat|sort -r|head -1)
        # ASM=$(cygpath -ms /c/Program\ Files\ \(x86\)/Microsoft\ Visual\ Studio/*/*/VC/Tools/MSVC/*/bin/Hostx64/*/ml.exe|sort -r|head -1)
        # ASM_PATH=$(dirname $(cygpath $ASM))
        # echo -e "#\!/bin/bash\nvsdevcmd=$vsdevcmd\nexport PATH=$ASM_PATH:\$PATH\n$(declare -f vsdevenv)\nvsdevenv \"\$@\"" > $build_dir/devenv.sh
        # # vsdevenv "declare" > $build_dir/_vsdev.env
        # # echo "compiler.env ($vsdevcmd):" >&2
        # # grep -vxF -f $build_dir/_system.env $build_dir/_vsdev.env | tee $build_dir/compiler.env >&2
        # # echo "//" >&2
        # # CL=$(bash -c ". $build_dir/compiler.env && which cl.exe | xargs cygpath -ms")
        . msvc-env/msvc_helpers.sh
        create_msvc_wrapper devenv.sh amd64 $build_dir
        CL=$($build_dir/devenv.sh which cl.exe)
        echo CC=$CL
        echo CXX=$CL
        echo PreferredToolArchitecture=x64
      ;;
      *)
        echo -e "#!/bin/bash\n\"\$@\"" > $build_dir/devenv.sh
        chmod a+x $PWD/_vulkan_build/devenv.sh
      ;;
    esac
    echo devenv=$PWD/_vulkan_build/devenv.sh
  ) > $build_dir/env
  cat $build_dir/env >&2
}

function configure_sdk_prereqs() {
  local vulkan_build_tools=$1
  test -d $vulkan_build_tools/bin || mkdir -p $vulkan_build_tools/bin
  export PATH=$vulkan_build_tools/bin:$PATH
  case `uname -s` in
    Darwin) ;;
    Linux) 
      test -f /etc/os-release && . /etc/os-release
      echo "VERSION_ID=$VERSION_ID"
      case $VERSION_ID in
        # legacy builds using 16.04
        16.04) 
          apt-get -qq -o=Dpkg::Use-Pty=0 update
          apt-get -qq -o=Dpkg::Use-Pty=0 install -y jq curl git make build-essential ninja-build
          curl -s -L https://github.com/Kitware/CMake/releases/download/v3.20.3/cmake-3.20.3-Linux-x86_64.tar.gz | tar --strip 1 -C $vulkan_build_tools -xzf -
          hash
          cmake --version
        ;;
        # everything else
        *) sudo apt-get -qq -o=Dpkg::Use-Pty=0 install -y ninja-build ;;
      esac
    ;;
    MINGW*)
     curl -L -o $vulkan_build_tools/ninja-win.zip https://github.com/ninja-build/ninja/releases/download/v1.10.2/ninja-win.zip
     unzip -d $vulkan_build_tools/bin $vulkan_build_tools/ninja-win.zip
    ;;
  esac
}
