#!/bin/bash
. runtime.sh

cd ../spark
dap ./pre-install.sh
dap ./install.sh -a sparkubi -p base

cd ../superset
dap ./pre-install.sh
dap ./install.sh -p base

