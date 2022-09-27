#!/bin/bash
. load_ENV.sh

echo "DaP ~ ENV: $DaP_ENV"
echo
echo "    - Configuration Keys -"
echo
for key in `find $DaP_ENV -type d -regex '.*/[A-Z_]*'`; do
    path=`sed "s/$DaP_ENV\///" <<< $key`
    KEY=`egrep -o [A-Z_]+$ <<< $key`
    override=`eval "echo \\$DaP_$KEY"`
    notice="`[ -z $override ] || echo -\> overriden by '$DaP_'$KEY: $override`"

    echo $path: `env_path $key` $notice
done
echo
echo "    - Configuration Files -"
for path in `find $DaP_ENV -type d -regex '.*/[a-z-]*'`; do
    subpath=`sed "s/$DaP_ENV\///" <<< $path`

    [[ -f $path/default || -f $path/var ]] && {
        echo
        echo $subpath
        sed 's/^/    /' `env_file $path` 
    }
done
echo
echo "DaP ~ END"

