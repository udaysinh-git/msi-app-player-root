#!/system/bin/sh
# /data/adb/service.d/00zygote-kick.sh
# ReZygisk (ptrace mode) starts its monitor at post-fs-data, after the first
# zygote has already forked, so the boot zygote is not injected until it
# restarts. Restart zygote once early in boot so ReZygisk injects it.
( sleep 8; setprop ctl.restart zygote ) &
