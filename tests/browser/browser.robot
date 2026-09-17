*** Settings ***
Documentation       Browser Library (Playwright) tests against the bundled
...                 static site. CI serves tests/site over HTTP and passes the
...                 URL in SITE_URL.

Library             Browser

Suite Setup         New Browser    chromium    headless=${True}
Suite Teardown      Close Browser    ALL


*** Variables ***
${SITE_URL}     %{SITE_URL=http://127.0.0.1:8000}


*** Test Cases ***
Chromium Launches And Renders The Page
    [Documentation]    Runs without --shm-size=1g. Upstream passes that flag in
    ...    every one of its own CI steps, which is an admission that its image
    ...    does not work at the default /dev/shm.
    New Page    ${SITE_URL}/index.html
    Get Text    id=heading    ==    robotframework-containers

Form Submission Navigates
    New Page    ${SITE_URL}/index.html
    Fill Text    id=username    robot
    Click    id=submit
    Get Text    id=welcome    ==    Welcome

Screenshots Land In The Reports Directory
    New Page    ${SITE_URL}/index.html
    Take Screenshot    fullPage=${True}
