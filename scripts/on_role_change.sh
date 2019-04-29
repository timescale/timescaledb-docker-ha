#!/bin/bash

cat <<EOT
$(date) - $0 - I was called with the following parameters: $@
EOT
