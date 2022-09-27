#!/bin/bash

env_path () { [ -f ../DaP/$1/var ] && cat ../DaP/$1/var || cat ../DaP/$1/default;}
: ${DaP_ENV:=`env_path ENV`}

env_file () { [ -f ../DaP/$1/var ] && echo ../DaP/$1/var || echo ../DaP/$1/default;}

env_branch () {
    local branch=`env_path $DaP_ENV/BRANCH`
    [ $branch = _local ] && git symbolic-ref HEAD --short || echo $branch
}

