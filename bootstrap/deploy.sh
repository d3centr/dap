#!/bin/bash
. ../DaP/load_ENV.sh

./runtime.sh build
. runtime.sh

echo "DaP ~ running deployment workflow"
run_workflow dap-bootstrap aws/blue-green-deployment.sh
exit_code=$?
echo "DaP ~ deployment exit code: $exit_code"

# install apps
[ $exit_code -eq 0 ] && {
    : ${DaP_PACK:=`env_path $DaP_ENV/cluster/PACK`}
    [ $DaP_PACK != none ] && {
        echo "DaP ~ installing $DaP_PACK apps."
        ./workflow/pack/$DaP_PACK.sh
    }
}

