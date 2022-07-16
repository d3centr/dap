#!/bin/bash

env_path () { [ -f ../DaP/$1/var ] && cat ../DaP/$1/var || cat ../DaP/$1/default;}
: ${DaP_ENV:=`env_path ENV`}

env_file () { [ -f ../DaP/$1/var ] && echo ../DaP/$1/var || echo ../DaP/$1/default;}

