"""
The qemu-guest-agent.py package uses virsh qemu-agent-command under the hood to interact with the guest-agent running on
a VM. Due to behaviours of the qemu-guest-agent, checking the status of a guest-agent's subprocess executes a
destructive read on success.  For that reason, keywords that assert the state of, or wait for, a guest process must also
return the status returned from the poll. Keywords assume a RHEL-like guest OS, which is apparent in hardcoded command
paths used here.

The guest-agent package provides the following
keywords:
    - get_guest_process_result
    - start_guest_process
    - wait_guest_for_process
    - run_guest_process
    - terminate_guest_process

If you are looking for keywords to control the guest VM itself, see ./libvirt.resource
"""
from __future__ import annotations  # Support for Python 3.7 and earlier

import base64
import json

from robot.libraries.BuiltIn import BuiltIn, DotDict
from robot.libraries.Process import Process, ExecutionResult
from robot.utils.robottime import timestr_to_secs


def _do_guest_exec(vm_name: str, cmd: str, *args) -> int:
    # _do_guest_exec wraps a given command and arg list into a qemu-guest-agent guest-exec API call.  For more info this
    # API, see https://qemu-project.gitlab.io/qemu/interop/qemu-ga-ref.html#qapidoc-211. For more information on the
    # guest-exec return message, see https://qemu-project.gitlab.io/qemu/interop/qemu-ga-ref.html#qapidoc-201
    agent_cmd_wrapper = {
        'execute': 'guest-exec',
        'arguments': {
            'path': cmd,
            'arg': args,
            'capture-output': True,
        }
    }
    virsh_args = f'--connect=qemu:///system qemu-agent-command --domain={vm_name} --cmd='.split()
    virsh_args.append(json.dumps(agent_cmd_wrapper))

    #  qemu-agent-command "guest-exec" returns data to stdout as:
    #  {
    #    return: {
    #      pid: int
    #    }
    #  }
    result: ExecutionResult = Process().run_process('virsh', *virsh_args)
    # check that the "virsh" process exited cleanly.  This is not the same as the guest process's exit code.
    if result.rc != 0:
        raise RuntimeError(f'virsh command failed:'
                           f'\nstdout={result.stdout}'
                           f'\nstderr={result.stderr}'
                           f'\nrc={result.rc}')
    content = json.loads(result.stdout)['return']
    BuiltIn().log(f'guest-exec result: {content}')

    return content['pid']


def _do_guest_exec_status(vm_name: str, pid: int) -> (dict, bool):
    # _do_guest_exec_status wraps a given Process ID (pid) in a qemu-guest-agent guest-exec-status API call. For more
    # info this API, see https://qemu-project.gitlab.io/qemu/interop/qemu-ga-ref.html#qapidoc-198.  For information on
    # the guest-exec-status return message, see https://qemu-project.gitlab.io/qemu/interop/qemu-ga-ref.html#qapidoc-194
    agent_cmd_wrapper = {
        'execute': 'guest-exec-status',
        'arguments': {
            'pid': pid,
        }
    }
    virsh_args = f'--connect=qemu:///system qemu-agent-command --domain={vm_name} --cmd='.split()
    virsh_args.append(json.dumps(agent_cmd_wrapper))

    #  qemu-agent-command "guest-exec" returns data to stdout as the example below. Fields marked (optional) will be
    #  undefined if exited is False. optional keys may not exist even if exited is True.
    #  {
    #    return: {
    #      exited: boolean
    #      exitcode: int (optional)
    #      signal: int (optional)
    #      out-data: string (optional)
    #      err-data: string (optional)
    #      out-truncated: boolean (optional)
    #      err-truncated: boolean (optional)
    #    }
    #  }
    result: ExecutionResult = Process().run_process('virsh', *virsh_args)
    # check that the "virsh" process exited cleanly.  This is not the same as the guest process's exit code.
    if result.rc != 0:
        raise RuntimeError(f'virsh command failed:'
                           f'\nstdout={result.stdout}'
                           f'\nstderr={result.stderr}'
                           f'\nrc={result.rc}')
    content = json.loads(result.stdout)['return']
    BuiltIn().log(f'guest-exec-status result: {content}')
    return {
        'rc': content['exitcode'] if 'exitcode' in content else None,
        'stdout': base64.decodebytes(content['out-data'].encode('utf-8')) if 'out-data' in content else '',
        'stderr': base64.decodebytes(content['err-data'].encode('utf-8')) if 'err-data' in content else '',
    }, content['exited']


def _do_kill(vm_name: str, pid: str, signal: str) -> int:
    if not vm_name:
        raise ValueError('vm name is not specified')
    if not pid:
        raise ValueError('pid is not specified')
    return _do_guest_exec(vm_name, '/usr/bin/kill', signal, pid)


def terminate_guest_process(vm_name: str, pid: str | int, kill: bool = False) -> (int, bool):
    """
    :param vm_name:         The name of the VM to execute the command on.
    :type vm_name:          str
    :param pid:             The process ID returned by qemu-agent-command.execute.guest-exec. This is the PID of the
                            command executed on the guest.
    :type pid:              str | int
    :param kill:            If True, the process is forcefully killed. Otherwise, the process is gracefully terminated.
    :type kill:             bool
    :return:                The exit code of the kill command and boolean ``exited``.
    :rtype:                 (int, bool)
    :raises RuntimeError:   If /bin/kill process returns a non-zero exit code.
    :raises ValueError:     If the PID is not an integer, or vm_name or pid is not specified.

    ``terminate_guest_process`` terminates or kills a process by its PID on the guest and returns the process's status.
    The process is terminated by sending a SIGTERM to the process. The status of the process is returned as a dict
    containing the stdout, stderr, and exit code of the process. If the process is still running (i.e. it ignored the
    SIGTERM) the `rc` value will be None and the `exited` value will be False. If the process has exited, the `rc` will
    be returned and `exited` will be True.

    Note: DOES NOT wrap the Process.terminate_process function. This is because the Process version only kills
    processes on the host, not the guest.

    Examples:
    ${stdout}    ${stderr}    ${rc}=    Terminate Guest Process    vm_name    pid
    Should Be Equal As Integers    ${rc}    -15
    Terminate Guest Process    vm_name    pid    kill=${True}
    """

    # pid is stored as an argument in the qemu-agent-command args list, which is expected to be a string
    if isinstance(pid, int):
        pid = str(pid)
    return _do_kill(vm_name, pid, "-15" if not kill else "-9")


def get_guest_process_result(vm_name: str, pid: int) -> (DotDict, bool):
    """
    :param vm_name:        The name of the VM to execute the command on
    :type vm_name:         str
    :param pid:            The process ID returned by qemu-agent-command.execute.guest-exec
    :type pid:             int
    :return:               DotDict with keys ``stdout``, ``stderr``, ``rc``, and boolean ``exited``.
    :rtype:                (DotDict, bool)
    :raises ValueError:    If the VM name or process ID is not specified
    :raises RuntimeError:  If guest-agent-command returns a non-zero exit code

    ``get_guest_process_result`` gets the results of the qemu-agent-command for a given process ID, which is returned by
    the qemu-agent-command.execute.guest-exec call immediately after execution. The PID is used to retrieve that
    process's stdout, stderr, and exit code. If the process is still running, the stdout, stderr, and exit code will be
    None and the boolean return value will be False. If the process has exited, the exit code will be returned and the
    boolean return value will be True.
    """
    if not pid:
        raise ValueError('PID is not specified')
    return DotDict(_do_guest_exec_status(vm_name, pid))


def wait_for_guest_process(vm_name: str, pid: int, timeout: int = None, on_timeout: str = "continue") -> (DotDict, bool):
    """
    :param vm_name:         The name of the VM to execute the command on
    :type vm_name:          str
    :param pid:             The process ID returned by qemu-agent-command.execute.guest-exec. This is the PID of the
                            command executed on the guest.
    :type pid:              int
    :param timeout:         The maximum amount of time to wait for the process to complete, in seconds.  If None,
                            wait indefinitely, (default).
    :type timeout:          int
    :param on_timeout:      The action to take if the timeout is reached.
                            documentation for more information. Default: "continue"
    :type on_timeout:       str
    :return:                DotDict with keys ``stdout``, ``stderr``, ``rc``, and boolean ``exited``.
    :rtype:                 (DotDict, bool)
    :raises RuntimeError:   If the VM name or process ID is not specified

    ``wait_for_guest_process`` is analogous to Process.wait_for_process(). The status of the command is retrieved using
    the qemu-agent-command.execute.guest-exec-status call.  If the process does not complete within the timeout, the
    ``on_timeout`` value will determine how to handle it.

    The ``on_timeout`` parameter can be one of the following values:
    | = Value = |               = Action =               |
    | continue  | The process is left running (default). |
    | terminate | The process is gracefully terminated.  |
    | kill      | The process is forcefully stopped.     |

    Examples:
    # Process ends cleanly
    ${stdout}    ${stderr}    ${rc}=    Wait For Guest Process    vm_name    pid
    Should Be Equal As Integers    ${rc}    0
    # Process does not end by timeout
    ${stdout}    ${stderr}    ${rc}    ${exited}=    Wait For Guest Process    vm_name    pid    timeout=10
    Should Not Be True    ${exited}
    # Kill process on timeout
    ${stdout}    ${stderr}    ${rc}    ${exited}=    Wait For Guest Process    vm_name    pid    timeout=10    on_timeout=kill
    Should Be True    ${exited}
    Should Be Equal as Integers    ${rc}    -9
    """
    if not vm_name:
        raise ValueError('vm name is not specified')
    if not pid:
        raise ValueError('pid is not specified')

    BuiltIn().log("waiting for process, timeout=%s, on_timeout=%s" % (timeout, on_timeout))
    timeout = timestr_to_secs(timeout) if timeout is not None else None
    status, exited = _do_guest_exec_status(vm_name, pid)
    while not exited:
        if timeout is not None:
            timeout -= 1
            if timeout <= 0:
                if on_timeout == 'terminate':
                    BuiltIn().log(f'process {pid} on {vm_name} timed out, terminating', 'WARN')
                    terminate_guest_process(vm_name, pid)
                elif on_timeout == 'kill':
                    BuiltIn().log(f'process {pid} on {vm_name} timed out, killing', 'WARN')
                    terminate_guest_process(vm_name, pid, kill=True)
                elif on_timeout == 'continue':
                    BuiltIn().log(f'process {pid} on {vm_name} timed out, continuing', 'WARN')
                    break
                else:
                    raise ValueError(f'invalid on_timeout value: {on_timeout}')
                status, exited = _do_guest_exec_status(vm_name, pid)
                break
        BuiltIn().sleep(1)
        status, exited = _do_guest_exec_status(vm_name, pid)

    BuiltIn().log(f'process {pid} on {vm_name} exited, returning result: {status}')
    return DotDict(status), exited


def run_guest_process(vm_name: str, cmd: str, *args, timeout: int = None, on_timeout: str = "continue") -> (DotDict, bool):
    """
    :param vm_name:     The name of the VM to execute the command on
    :type vm_name:      str
    :param cmd:         The absolute path to a command on the guest, e.g. "/bin/ls"
    :type cmd:          str
    :param args:        The arguments to pass to the command, separated into a list of strings, e.g. ["-l", "/tmp"]
                        Command arguments which take a value must be passed as a single string, e.g. ["-f /tmp""]
    :type args:         list
    :param timeout:     The maximum amount of time to wait for the process to complete, in seconds.  If None,
                        wait indefinitely (default).
    :type timeout:      int
    :param on_timeout:  The action to take if the timeout is reached.
    :type on_timeout:   str
    :return:            The stdout, stderr, and exit code of the guest process for the given PID
    :rtype:             (DotDict, bool)
    :raises             RuntimeError: If the VM name or command path is not specified

    ``run_guest_process`` excepts a given command and optional arg list to execute on a given VM using the
    qemu-agent-command. The command is executed by using virsh qemu-guest-command. This is a blocking call unless
    qemu-agent-timeout is set to anything but the default (must be configured externally).

    Usage: ${stdout}    ${stderr}    ${rc}=    Run Guest Process    vm_name    cmd    *args
    Examples:
    ${stdout}    ${stderr}    ${rc}=    Run Guest Process    vm-host-1    /bin/ls    -l    /tmp
    Log Many   ${stdout}    ${stderr}
    Should Be Equal As Integers    ${rc}    0

    ${stdout}    ${stderr}    ${rc}    ${exited}=    Run Guest Process    vm-host-1    /bin/sleep    30s   timeout=10
    Should Be True    ${exited}
    """

    if not vm_name:
        raise ValueError('vm name is not specified')
    if not cmd:
        raise ValueError('cmd is not specified')

    pid = _do_guest_exec(vm_name, cmd, *args)
    return wait_for_guest_process(vm_name, pid, timeout, on_timeout)


def start_guest_process(vm_name: str, cmd: str, *args) -> int:
    """
    :param vm_name:         The name of the VM to execute the command on
    :type vm_name:          str
    :param cmd:             The command to execute on the guest, e.g. "/bin/ls".  Must be a path.
    :type cmd:              str
    :param args:            The arguments to pass to the command, separated into a list of strings, e.g. ["-l", "/tmp"]
                            Command arguments which take a value must be passed as a single string, e.g. ["-f /tmp""]
    :type args:             list
    :return:                The guest's process ID of the command
    :rtype:                 int | None
    :raises ValueError      If the VM name or command path is not specified
    :raises RuntimeError:   If the qemu-agent-command returns a non-zero exit code

    ``start_guest_process`` is analogous to Process.start_process in that it does not wait for a guest process to exit.
    The command is executed on a VM using the qemu-agent-command.  To retrieve the guest process's status, use the
    PID returned by start_guest_process with get_guest_process_result.

    Examples:
    ${pid}=    Start Guest Process    vm-host-1    /bin/ls    -l    /tmp
    ${stdout}    ${stderr}    ${rc}=    Get Guest Process Result    vm-host-1    ${pid}
    Log Many    ${stdout}    ${stderr}
    Should Be Equal As Integers    ${rc}    0
    """
    if not vm_name:
        raise ValueError('vm name is not specified')
    if not cmd:
        raise ValueError('cmd is not specified')

    content = _do_guest_exec(vm_name, cmd, *args)
    return content
