*** Settings ***
Documentation       Tests for audit log profile configuration and log file rotation

Resource            ../../resources/common.resource
Resource            ../../resources/microshift-config.resource
Resource            ../../resources/microshift-host.resource
Resource            ../../resources/microshift-process.resource
Resource            ../../resources/oc.resource
Library             ../../resources/DataFormats.py

Suite Setup         Setup
Suite Teardown      Teardown

Test Tags           restart    slow


*** Variables ***
${AUDIT_LOG}            /var/log/kube-apiserver/audit.log
${AUDIT_LOG_DIR}        /var/log/kube-apiserver
${TEST_NS}              audit-test-ns

${PROFILE_NONE}         SEPARATOR=\n
...                     apiServer:
...                     \ \ auditLog:
...                     \ \ \ \ profile: None

${PROFILE_DEFAULT}      SEPARATOR=\n
...                     apiServer:
...                     \ \ auditLog:
...                     \ \ \ \ profile: Default

${PROFILE_WRITE}        SEPARATOR=\n
...                     apiServer:
...                     \ \ auditLog:
...                     \ \ \ \ profile: WriteRequestBodies

${PROFILE_ALL}          SEPARATOR=\n
...                     apiServer:
...                     \ \ auditLog:
...                     \ \ \ \ profile: AllRequestBodies

${PROFILE_INVALID}      SEPARATOR=\n
...                     apiServer:
...                     \ \ auditLog:
...                     \ \ \ \ profile: Unknown

${ROTATION_CONFIG}      SEPARATOR=\n
...                     apiServer:
...                     \ \ auditLog:
...                     \ \ \ \ maxFileSize: 2
...                     \ \ \ \ maxFiles: 2
...                     \ \ \ \ profile: AllRequestBodies


*** Test Cases ***
Invalid Audit Profile Prevents Startup
    [Documentation]    An unrecognized audit profile should prevent MicroShift from starting.
    Drop In MicroShift Config    ${PROFILE_INVALID}    10-audit
    Stop MicroShift
    Command Should Fail    timeout 30 systemctl start microshift

    [Teardown]    Run Keywords
    ...    Remove Drop In MicroShift Config    10-audit
    ...    AND    Restart MicroShift

Audit Profile None Produces No Logs
    [Documentation]    With profile None, no audit entries should be written.
    Drop In MicroShift Config    ${PROFILE_NONE}    10-audit
    Restart MicroShift

    ${cm_name}=    Set Variable    audit-none-cm
    Run With Kubeconfig    oc create configmap ${cm_name} -n ${TEST_NS}

    ${count}=    Grep Audit Log Count    ${cm_name}
    Should Be Equal As Integers    ${count}    0

    [Teardown]    Run Keywords
    ...    Run With Kubeconfig    oc delete configmap ${cm_name} -n ${TEST_NS} --ignore-not-found
    ...    AND    Remove Drop In MicroShift Config    10-audit
    ...    AND    Restart MicroShift

Audit Profile Default Logs Metadata Only
    [Documentation]    Default profile should log metadata but not request/response bodies.
    Drop In MicroShift Config    ${PROFILE_DEFAULT}    10-audit
    Restart MicroShift

    ${cm_name}=    Set Variable    audit-default-cm
    Run With Kubeconfig    oc create configmap ${cm_name} -n ${TEST_NS}
    Run With Kubeconfig    oc get configmap ${cm_name} -n ${TEST_NS}

    ${meta_count}=    Grep Audit Log Count    ${cm_name}
    Should Be True    ${meta_count} > 0

    ${body_count}=    Grep Audit Log Bodies Count    ${cm_name}
    Should Be Equal As Integers    ${body_count}    0

    [Teardown]    Run Keywords
    ...    Run With Kubeconfig    oc delete configmap ${cm_name} -n ${TEST_NS} --ignore-not-found
    ...    AND    Remove Drop In MicroShift Config    10-audit
    ...    AND    Restart MicroShift

Audit Profile WriteRequestBodies Logs Write Operations
    [Documentation]    WriteRequestBodies should log request bodies for write operations
    ...    (create, update, patch, delete) but not for read operations.
    Drop In MicroShift Config    ${PROFILE_WRITE}    10-audit
    Restart MicroShift

    ${cm_name}=    Set Variable    audit-write-cm
    Run With Kubeconfig    oc create configmap ${cm_name} -n ${TEST_NS}
    Run With Kubeconfig    oc get configmap ${cm_name} -n ${TEST_NS}

    ${write_bodies}=    Grep Audit Log Write Bodies    ${cm_name}
    Should Be True    ${write_bodies} > 0

    ${read_bodies}=    Grep Audit Log Read Bodies    ${cm_name}
    Should Be Equal As Integers    ${read_bodies}    0

    [Teardown]    Run Keywords
    ...    Run With Kubeconfig    oc delete configmap ${cm_name} -n ${TEST_NS} --ignore-not-found
    ...    AND    Remove Drop In MicroShift Config    10-audit
    ...    AND    Restart MicroShift

Audit Profile AllRequestBodies Logs All Operations
    [Documentation]    AllRequestBodies should log request bodies for all operations.
    Drop In MicroShift Config    ${PROFILE_ALL}    10-audit
    Restart MicroShift

    ${cm_name}=    Set Variable    audit-all-cm
    Run With Kubeconfig    oc create configmap ${cm_name} -n ${TEST_NS}
    Run With Kubeconfig    oc get configmap ${cm_name} -n ${TEST_NS}

    ${write_bodies}=    Grep Audit Log Write Bodies    ${cm_name}
    Should Be True    ${write_bodies} > 0

    ${read_bodies}=    Grep Audit Log Read Bodies    ${cm_name}
    Should Be True    ${read_bodies} > 0

    [Teardown]    Run Keywords
    ...    Run With Kubeconfig    oc delete configmap ${cm_name} -n ${TEST_NS} --ignore-not-found
    ...    AND    Remove Drop In MicroShift Config    10-audit
    ...    AND    Restart MicroShift

Audit Log Rotation Respects Max File Size And Count
    [Documentation]    With maxFileSize=2 (MB) and maxFiles=2, audit log rotation should
    ...    produce exactly 2 backup files of approximately 2MB each.
    Drop In MicroShift Config    ${ROTATION_CONFIG}    10-audit
    Restart MicroShift

    Wait Until Keyword Succeeds    60x    5s
    ...    Audit Backup Files Should Match    2

    [Teardown]    Run Keywords
    ...    Remove Drop In MicroShift Config    10-audit
    ...    AND    Restart MicroShift


*** Keywords ***
Setup
    [Documentation]    Test suite setup
    Check Required Env Variables
    Login MicroShift Host
    Setup Kubeconfig
    Run With Kubeconfig    oc create namespace ${TEST_NS}

Teardown
    [Documentation]    Test suite teardown
    Run With Kubeconfig    oc delete namespace ${TEST_NS} --ignore-not-found
    Logout MicroShift Host
    Remove Kubeconfig

Grep Audit Log Count
    [Documentation]    Count audit log entries matching the resource name
    [Arguments]    ${resource_name}
    ${stdout}=    Command Should Work
    ...    grep -c '"${resource_name}"' ${AUDIT_LOG} || echo 0
    RETURN    ${stdout.strip()}

Grep Audit Log Bodies Count
    [Documentation]    Count audit entries with requestObject or responseObject for a resource
    [Arguments]    ${resource_name}
    ${stdout}=    Command Should Work
    ...    grep '"${resource_name}"' ${AUDIT_LOG} | grep -c '"requestObject"\\|"responseObject"' || echo 0
    RETURN    ${stdout.strip()}

Grep Audit Log Write Bodies
    [Documentation]    Count audit entries with requestObject for write verbs
    [Arguments]    ${resource_name}
    ${stdout}=    Command Should Work
    ...    grep '"${resource_name}"' ${AUDIT_LOG} | grep -E '"verb":"(create|update|patch|delete)"' | grep -c '"requestObject"' || echo 0
    RETURN    ${stdout.strip()}

Grep Audit Log Read Bodies
    [Documentation]    Count audit entries with responseObject for read verbs
    [Arguments]    ${resource_name}
    ${stdout}=    Command Should Work
    ...    grep '"${resource_name}"' ${AUDIT_LOG} | grep -E '"verb":"(get|list|watch)"' | grep -c '"responseObject"' || echo 0
    RETURN    ${stdout.strip()}

Audit Backup Files Should Match
    [Documentation]    Verify the expected number of audit backup files exist.
    ...    Generates API traffic to fill audit logs while waiting.
    [Arguments]    ${expected_count}
    Generate API Traffic
    ${stdout}=    Command Should Work
    ...    find ${AUDIT_LOG_DIR} -name 'audit-*.log' -type f | wc -l
    Should Be Equal As Strings    ${stdout.strip()}    ${expected_count}

Generate API Traffic
    [Documentation]    Generate API activity to produce audit log entries
    FOR    ${i}    IN RANGE    20
        Run With Kubeconfig    oc get pods -A    allow_fail=True
        Run With Kubeconfig
        ...    oc create configmap traffic-cm-${i} -n ${TEST_NS} --from-literal=data=padding${{" " * 4096}}
        ...    allow_fail=True
        Run With Kubeconfig    oc delete configmap traffic-cm-${i} -n ${TEST_NS} --ignore-not-found    allow_fail=True
    END
