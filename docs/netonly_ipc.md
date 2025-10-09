# NetOnlyRunspacePool IPC Mechanism

## Overview

The `NetOnlyRunspacePool` class implements a mechanism to execute PowerShell commands and scripts in a nested process with alternate credentials on the remote host. This is achieved using CreateProcessWithLogonW and a named pipe-based Inter-Process Communication (IPC) system.

## Architecture

### Components

1. **NetOnlyRunspacePool Class** (`evil_winrm_py.py`)
   - Main wrapper class that manages the nested process
   - Provides methods to execute commands and scripts in the nested context
   - Handles cleanup and resource management

2. **Listener Script** (`netonly_listener.ps1`)
   - Runs in the nested PowerShell process
   - Creates a named pipe server
   - Listens for commands and executes them
   - Returns output and errors as JSON

3. **Execute Script** (`netonly_execute.ps1`)
   - Acts as a named pipe client
   - Sends commands to the listener
   - Receives and returns execution results

4. **Bootstrap Script** (`netonly.ps1`)
   - Creates the nested process using CreateProcessWithLogonW
   - Supports both LOGON_NETCREDENTIALS_ONLY (netonly) and LOGON_WITH_PROFILE (interactive) modes

## IPC Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                          Remote Host                            │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Parent PowerShell Session (WinRM)                        │  │
│  │                                                           │  │
│  │  ┌─────────────────┐         ┌──────────────────┐       │  │
│  │  │ NetOnlyRunspace │         │ netonly_execute  │       │  │
│  │  │ Pool (Python)   │────────▶│ .ps1 (Client)    │       │  │
│  │  └─────────────────┘         └──────────────────┘       │  │
│  │                                       │                   │  │
│  └───────────────────────────────────────┼───────────────────┘  │
│                                          │                      │
│                                Named Pipe (IPC)                 │
│                                          │                      │
│  ┌───────────────────────────────────────┼───────────────────┐  │
│  │ Nested PowerShell Process             │                   │  │
│  │ (Created with CreateProcessWithLogonW)│                   │  │
│  │                                       │                   │  │
│  │  ┌──────────────────┐         ┌──────▼──────────┐        │  │
│  │  │ Alternate        │         │ netonly_listener│        │  │
│  │  │ Credentials      │◀────────│ .ps1 (Server)   │        │  │
│  │  │ Context          │         └─────────────────┘        │  │
│  │  └──────────────────┘                                     │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Workflow

1. **Initialization**
   ```python
   netonly_pool = NetOnlyRunspacePool(
       parent_pool=r_pool,
       username="DOMAIN\\user",
       password="password",
       logon_type="netonly"
   )
   ```
   - Generates a unique named pipe name
   - Encodes `netonly_listener.ps1` as base64
   - Calls `netonly.ps1` to create a process with CreateProcessWithLogonW
   - The new process runs the encoded listener script
   - Verifies the listener is active

2. **Command Execution**
   ```python
   output, errors, had_errors = netonly_pool.execute_command("Get-Process")
   ```
   - Creates a PowerShell instance in the parent pool
   - Runs `netonly_execute.ps1` with the command
   - `netonly_execute.ps1` connects to the named pipe
   - Sends command as JSON request to the listener
   - Listener executes the command in nested process context
   - Results are returned as JSON response
   - Output and errors are parsed and returned to caller

3. **Script Execution**
   ```python
   script = "Get-Service | Where-Object { $_.Status -eq 'Running' }"
   output, errors, had_errors = netonly_pool.execute_script(script)
   ```
   - Similar to command execution, but sends script content
   - Listener creates a script block and executes it

4. **Cleanup**
   ```python
   netonly_pool.cleanup()
   ```
   - Sends an "Exit" command to the listener
   - Listener gracefully shuts down
   - Named pipe is closed

## Named Pipe Communication Protocol

### Request Format (JSON)
```json
{
  "Action": "Execute|Status|Exit",
  "Command": "command text",
  "CommandType": "Command|Script"
}
```

### Response Format (JSON)
```json
{
  "Type": "Success|Error",
  "Output": ["line1", "line2", ...],
  "Errors": ["error1", "error2", ...],
  "Message": "status message"
}
```

## Security Considerations

1. **Named Pipe Permissions**
   - The listener creates a named pipe with "Everyone" access
   - This is necessary for cross-process communication on the same host
   - Pipe is local to the machine (not network-accessible)

2. **Credential Handling**
   - Credentials are passed to CreateProcessWithLogonW via the parent session
   - No credentials are stored in the named pipe or transmitted over it
   - Only commands and results flow through the pipe

3. **Resource Cleanup**
   - Always call `cleanup()` when done to properly terminate the listener
   - The interactive shell automatically calls cleanup on exit
   - Orphaned processes will timeout after 30 seconds of inactivity

## Limitations

1. **Interactive Commands**
   - Commands requiring user input are not supported
   - Use non-interactive switches where possible

2. **Long-Running Commands**
   - Default timeout is 300 seconds (5 minutes)
   - Can be adjusted via the `timeout` parameter
   - Very long operations should be run as background jobs

3. **Output Buffering**
   - Output is collected after command completion
   - Streaming output during execution is not supported

## Integration with evil-winrm-py

The NetOnlyRunspacePool is seamlessly integrated into evil-winrm-py:

1. **Automatic Routing**
   - When in interactive mode, `run_ps_cmd()` automatically detects NetOnlyRunspacePool
   - Commands are transparently routed to the nested process
   - No code changes needed for existing commands

2. **Interactive Shell**
   - Use the `interactive` command to enter netonly/interactive mode
   - Prompt shows `PS-netonly` or `PS-interactive` to indicate mode
   - All commands execute in the nested process context

3. **File Operations**
   - Upload/download operations use the parent pool (not routed)
   - Script execution via `runps` is routed to nested process
   - Function loading via `loadps` is routed to nested process

## Example Usage Scenarios

### Scenario 1: Running as Different User
```python
# Connect with initial credentials
r_pool = RunspacePool(...)

# Create nested session with elevated credentials
netonly_pool = NetOnlyRunspacePool(
    r_pool,
    username="DOMAIN\\admin",
    password="admin_password",
    logon_type="netonly"
)

# Execute command as admin
output, errors, had_errors = netonly_pool.execute_command(
    "Get-ADUser -Identity 'username' -Properties *"
)
```

### Scenario 2: Interactive Mode
```bash
# In evil-winrm-py shell
*Evil-WinRM* PS C:\> interactive

[+] Process created with PID: 1234 (netonly mode)
[+] Command listener is active

*Evil-WinRM* PS-netonly C:\> whoami
domain\admin

*Evil-WinRM* PS-netonly C:\> exit
```

### Scenario 3: Script Execution with Alternate Credentials
```python
script = '''
$cred = Get-Credential # Will use the alternate credentials
New-PSDrive -Name "X" -PSProvider FileSystem -Root "\\\\server\\share" -Credential $cred
Get-ChildItem X:\\
'''

output, errors, had_errors = netonly_pool.execute_script(script)
```

## Troubleshooting

### Listener Not Starting
- Check that credentials are valid
- Verify PowerShell remoting is working
- Check remote host logs in `%TEMP%\netonly_listener_error.txt`

### Pipe Connection Timeout
- Listener may have crashed or exited
- Check if nested process is still running: `Get-Process -Id <PID>`
- Increase timeout value if commands take longer to execute

### Commands Return Empty Output
- Verify command syntax in a regular PowerShell session first
- Check error output for execution failures
- Some cmdlets may require explicit `-ErrorAction` handling

## Performance Considerations

- Named pipe communication adds minimal overhead (~10-50ms per command)
- Script compilation happens in the nested process (one-time cost)
- Large output is transmitted as JSON (may impact performance)
- Consider breaking large scripts into smaller chunks

## Future Enhancements

Possible improvements to the IPC mechanism:
- Streaming output for long-running commands
- Support for progress callbacks
- Binary data transfer optimization
- Multiple parallel command execution
- Persistent sessions across multiple interactive mode entries
