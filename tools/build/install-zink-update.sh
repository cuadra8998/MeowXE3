#!/bin/bash
# install-zink-update.sh: puts the MeowXE3 package's Zink libraries into /Library/GPUBundles/nvmtl/zink (new files renamed
# into place: running OpenGL apps keep the copies they loaded; each picks up the new ones when it relaunches).
set -e
[ "$(id -u)" = 0 ] || { echo "run it with sudo"; exit 1; }
S=${NMX:-$HOME/nmx}/MeowXE3/GPUBundles/nvmtl/zink; D=/Library/GPUBundles/nvmtl/zink
for f in libnvk_cgl.dylib libnvk_zink.dylib; do
  cp $S/$f $D/.$f.new && chown root:wheel $D/.$f.new && chmod 755 $D/.$f.new && mv -f $D/.$f.new $D/$f
done
ls -l $D; echo ZINK-UPDATED
