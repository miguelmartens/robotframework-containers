*** Settings ***
Documentation       Smoke tests for the `base` variant. Nothing here needs a
...                 browser, a driver or a network connection, so this suite
...                 also runs unchanged inside the browser and selenium images.

Library             Collections
Library             DateTime
Library             OperatingSystem
Library             JSONLibrary
Library             FakerLibrary


*** Test Cases ***
Robot Framework Executes A Suite
    Log    Robot Framework is alive

JSON Library Is Usable
    [Documentation]    ppodgorsek #489 asked for JSON libraries to be bundled.
    ${data}=    Convert String To JSON    {"name": "robot", "count": 2}
    ${name}=    Get Value From Json    ${data}    $.name
    Should Be Equal    ${name}[0]    robot

Faker Library Generates Data
    ${word}=    FakerLibrary.Word
    Should Not Be Empty    ${word}

Date Handling Works
    ${now}=    Get Current Date
    Should Not Be Empty    ${now}

Timezone Comes From The TZ Environment Variable
    ${tz}=    Get Environment Variable    TZ    UTC
    Should Not Be Empty    ${tz}

The Reports Directory Is Writable
    [Documentation]    Guards the permission failures that dominate upstream's
    ...    issue tracker (#333, #420, #476). The entrypoint exports the
    ...    resolved directory so the check works with ROBOT_TEST_RUN_ID too.
    ${reports}=    Get Environment Variable    ROBOT_REPORTS_FINAL_DIR    ${OUTPUT DIR}
    Directory Should Exist    ${reports}
    Create File    ${reports}/.write-check    ok
    Remove File    ${reports}/.write-check

The Home Directory Is Writable
    [Documentation]    ppodgorsek #424: "cannot set HOME environment variable".
    ${home}=    Get Environment Variable    HOME
    Should Not Be Empty    ${home}
    Directory Should Exist    ${home}
    Create File    ${home}/.write-check    ok
    Remove File    ${home}/.write-check
