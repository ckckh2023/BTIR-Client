#!/bin/bash

# Force SUID on chrome-sandbox so Chromium's setuid sandbox helper works
# for unprivileged users (Ubuntu 24.04+ restricts unprivileged userns).
# electron-builder's default postinst detects userns as root and skips SUID,
# which breaks the app for normal users on default AppArmor configurations.
chmod 4755 /opt/BTIR-Client/chrome-sandbox 2>/dev/null || true

exit 0