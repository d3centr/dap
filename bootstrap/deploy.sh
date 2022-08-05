#!/bin/bash

./runtime.sh build
. runtime.sh

echo "DaP ~ running deployment workflow"
run_workflow workflow/aws/blue-green-deployment.sh
exit_code=$?
echo "DaP ~ deployment exit code: $exit_code"
echo

# install apps
[ $exit_code -eq 0 ] && {
    . ../DaP/load_ENV.sh
    : ${DaP_PACK:=`env_path $DaP_ENV/cluster/PACK`}
    [ $DaP_PACK != none ] && {
        echo "DaP ~ installing $DaP_PACK apps."
        ./workflow/pack/$DaP_PACK.sh
    }
}

