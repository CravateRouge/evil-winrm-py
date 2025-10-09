# NetOnlyRunspacePool Quick Start Guide

## What is NetOnlyRunspacePool?

NetOnlyRunspacePool allows you to execute PowerShell commands in a nested process with alternate credentials on a remote Windows host. This is useful for:

- Running commands with elevated privileges
- Accessing network resources with different credentials
- Testing different user contexts
- COM object privilege escalation scenarios

## Basic Usage in evil-winrm-py Shell

### Entering Interactive Mode

Simply type `interactive` in the evil-winrm-py shell:

```bash
*Evil-WinRM* PS C:\Users\john\Documents> interactive

[+] Process created with PID: 5432 (netonly mode)
[+] Command listener is active

*Evil-WinRM* PS-netonly C:\Users\john\Documents>
```

Notice the prompt changes to `PS-netonly` or `PS-interactive` to indicate you're in the nested session.

### Running Commands

All commands are now executed in the nested process context:

```powershell
*Evil-WinRM* PS-netonly C:\Users\john\Documents> whoami
domain\admin

*Evil-WinRM* PS-netonly C:\Users\john\Documents> Get-Process | Select-Object -First 5
# Output shows processes as seen by the alternate user
```

### Running Scripts

Scripts are automatically routed to the nested process:

```powershell
*Evil-WinRM* PS-netonly C:\Users\john\Documents> runps /path/to/script.ps1
[+] PowerShell script ran successfully.
```

### Exiting Interactive Mode

Type `exit` to return to the normal shell:

```powershell
*Evil-WinRM* PS-netonly C:\Users\john\Documents> exit
*Evil-WinRM* PS C:\Users\john\Documents>
```

## Programmatic Usage

### Creating a NetOnlyRunspacePool

```python
from evil_winrm_py.evil_winrm_py import NetOnlyRunspacePool

# Create the pool with alternate credentials
pool = NetOnlyRunspacePool(
    parent_pool=r_pool,
    username="DOMAIN\\admin",
    password="SecurePassword123!",
    logon_type="netonly"  # or "interactive"
)
```

### Executing Commands

```python
# Execute a single command
output, errors, had_errors = pool.execute_command("Get-Service")

# Print output
for line in output:
    print(line)

# Check for errors
if had_errors:
    for error in errors:
        print(f"ERROR: {error}")
```

### Executing Scripts

```python
# Define a script
script = '''
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Output "Running as: $currentUser"

Get-Process | Sort-Object CPU -Descending | Select-Object -First 5
'''

# Execute the script
output, errors, had_errors = pool.execute_script(script)
```

### Cleanup

Always clean up when done:

```python
pool.cleanup()
```

## Use Cases

### 1. Domain Queries with Admin Credentials

```powershell
*Evil-WinRM* PS-interactive C:\> interactive
*Evil-WinRM* PS-interactive C:\> Get-ADUser -Filter * -Properties LastLogon
# Returns all domain users (requires admin)
```

### 2. Accessing Network Shares

```powershell
*Evil-WinRM* PS-netonly C:\> Test-Path \\dc01\SYSVOL
True

*Evil-WinRM* PS-netonly C:\> Get-ChildItem \\dc01\SYSVOL
# Lists contents of the SYSVOL share
```

### 3. COM Object Access

```powershell
*Evil-WinRM* PS-interactive C:\> $com = New-Object -ComObject MMC20.Application
*Evil-WinRM* PS-interactive C:\> $com.Document.ActiveView
# Works because interactive logon has NT AUTHORITY\Interactive permissions
```

### 4. Privilege Escalation Testing

```powershell
*Evil-WinRM* PS-interactive C:\> whoami /priv
# Check privileges in the interactive context

*Evil-WinRM* PS-interactive C:\> whoami /groups
# Check group memberships
```

## Logon Types

### netonly Mode

- Uses `LOGON_NETCREDENTIALS_ONLY` flag
- Local operations use original credentials
- Network operations use alternate credentials
- Useful for accessing network resources

```bash
evil-winrm-py -i 192.168.1.100 -u user -H hash
*Evil-WinRM* PS> interactive
# Uses netonly mode
```

### interactive Mode

- Uses `LOGON_WITH_PROFILE` flag
- Both local and network operations use alternate credentials
- Full interactive session privileges
- Requires plaintext password

```bash
evil-winrm-py -i 192.168.1.100 -u user -p password
*Evil-WinRM* PS> interactive
# Uses interactive mode
```

## Troubleshooting

### "Listener not responding"

The nested process may have failed to start. Check:
- Credentials are valid
- Remote host has PowerShell 5.1+
- Execution policy allows scripts

### "Pipe connection timeout"

The listener may have crashed. Check:
- Nested process is still running: `Get-Process -Id <PID>`
- Check `%TEMP%\netonly_listener_error.txt` on remote host
- Increase timeout if commands take longer

### "Command returns empty output"

- Verify command works in regular PowerShell first
- Check error output for execution failures
- Some cmdlets may require explicit `-ErrorAction` handling

## Tips and Best Practices

1. **Always Clean Up**: Exit the interactive mode properly with `exit`
2. **Check Errors**: Always check the error output, not just the result
3. **Test First**: Test commands in regular PowerShell before using them in netonly mode
4. **Use Timeouts**: Increase timeout for long-running operations
5. **Avoid Input**: Don't use commands that require user input

## Advanced Features

### Custom Timeout

```python
# Execute with custom timeout (10 minutes)
output, errors, had_errors = pool.execute_command(
    "Get-EventLog -LogName Security",
    timeout=600
)
```

### Batch Operations

```python
# Execute multiple commands in a single script
script = '''
Write-Output "=== User Info ==="
whoami /all

Write-Output "`n=== Network Shares ==="
net share

Write-Output "`n=== Services ==="
Get-Service | Where-Object {$_.Status -eq 'Running'} | Select-Object -First 10
'''

output, errors, had_errors = pool.execute_script(script)
```

### Error Handling

```python
try:
    output, errors, had_errors = pool.execute_command("Get-NonExistentCmdlet")
    if had_errors:
        print("Command failed:")
        for error in errors:
            print(f"  - {error}")
except Exception as e:
    print(f"Exception occurred: {e}")
```

## Performance Notes

- **Command Overhead**: ~10-50ms per command (IPC overhead)
- **Script Upload**: One-time ~100-200ms cost during initialization
- **Large Output**: JSON serialization may slow down large outputs
- **Optimization**: Batch multiple commands into a single script when possible

## Security Notes

- Credentials are NOT transmitted through the named pipe
- Named pipe is local to the machine (not network-accessible)
- Temporary files are automatically cleaned up on exit
- Pipe names include random UUIDs for uniqueness

## Further Reading

- [Detailed IPC Documentation](netonly_ipc.md)
- [Implementation Notes](IMPLEMENTATION_NOTES.md)
- [Usage Guide](usage.md)
- [Example Code](sample/netonly_example.py)

## Support

If you encounter issues:
1. Check the troubleshooting section above
2. Enable debug logging: `--debug` flag
3. Check remote host logs in `%TEMP%\netonly_listener_error.txt`
4. Review the detailed documentation in `docs/netonly_ipc.md`
