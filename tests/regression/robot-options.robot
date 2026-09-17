*** Settings ***
Documentation       Regression guard for ppodgorsek #194 / #345 / #353.
...
...                 Upstream passes ROBOT_OPTIONS to the shell unquoted, so a
...                 value containing spaces is word-split and the variable
...                 arrives mangled. This suite is run by CI with:
...
...                     ROBOT_OPTIONS=--variable "SPACED:value with spaces"
...
...                 It is kept out of tests/base so a normal run does not fail
...                 on the unset default.

Library             OperatingSystem


*** Variables ***
${SPACED}       ${EMPTY}


*** Test Cases ***
Variable With Spaces Survives ROBOT_OPTIONS
    Should Be Equal    ${SPACED}    value with spaces
