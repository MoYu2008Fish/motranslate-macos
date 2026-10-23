#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")" || exit 1
./deploy.sh
result=$?
if [ "$result" -ne 0 ]; then
    echo
    echo '部署未完成，请查看上面的错误。 / Deployment failed; see the error above.'
fi
if [ -t 0 ]; then
    echo
    read -r -p '按回车关闭 / Press Return to close…' _
fi
exit "$result"
