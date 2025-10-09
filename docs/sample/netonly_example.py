#!/usr/bin/env python3
"""
Example usage of NetOnlyRunspacePool for command execution with alternate credentials.

This example demonstrates how to:
1. Create a NetOnlyRunspacePool with alternate credentials
2. Execute commands in the nested process
3. Execute scripts in the nested process
4. Properly clean up resources

Note: This is a conceptual example. You'll need a live WinRM connection to actually run it.
"""

from pypsrp.powershell import RunspacePool
from evil_winrm_py.evil_winrm_py import NetOnlyRunspacePool

def main():
    # Step 1: Establish initial WinRM connection
    # This would typically be done with your authentication method
    # For this example, we assume r_pool is already established
    
    # Example connection setup (pseudo-code):
    # r_pool = RunspacePool(
    #     connection_info=...
    # )
    
    # Step 2: Create NetOnlyRunspacePool with alternate credentials
    print("[*] Creating NetOnlyRunspacePool with alternate credentials...")
    
    netonly_pool = NetOnlyRunspacePool(
        parent_pool=r_pool,
        username="DOMAIN\\admin",  # Alternate credentials
        password="SecurePassword123!",
        logon_type="netonly"  # or "interactive"
    )
    
    # The initialization will:
    # - Create a nested PowerShell process with the alternate credentials
    # - Set up a named pipe for IPC
    # - Verify the listener is active
    
    # Step 3: Execute a simple command
    print("\n[*] Executing command: whoami /all")
    
    output, errors, had_errors = netonly_pool.execute_command("whoami /all")
    
    if not had_errors:
        print("[+] Command executed successfully:")
        for line in output:
            print(f"    {line}")
    else:
        print("[-] Command failed:")
        for error in errors:
            print(f"    ERROR: {error}")
    
    # Step 4: Execute a more complex script
    print("\n[*] Executing script to check domain access...")
    
    script = '''
    # Get current user context
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-Output "Running as: $currentUser"
    
    # Try to query Active Directory
    try {
        $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
        Write-Output "Domain: $($domain.Name)"
        Write-Output "Domain Controller: $($domain.PdcRoleOwner.Name)"
    } catch {
        Write-Output "Error accessing domain: $($_.Exception.Message)"
    }
    
    # List running processes (limited output)
    Write-Output "`nTop 5 processes by CPU:"
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | Format-Table Name, CPU, Id -AutoSize
    '''
    
    output, errors, had_errors = netonly_pool.execute_script(script)
    
    if not had_errors:
        print("[+] Script executed successfully:")
        for line in output:
            print(f"    {line}")
    else:
        print("[-] Script failed:")
        for error in errors:
            print(f"    ERROR: {error}")
    
    # Step 5: Test network operations with alternate credentials
    print("\n[*] Testing network operations with alternate credentials...")
    
    network_script = '''
    # Test accessing a network share with alternate credentials
    try {
        $sharePath = "\\\\dc01\\SYSVOL"
        $testAccess = Test-Path $sharePath
        if ($testAccess) {
            Write-Output "Successfully accessed: $sharePath"
            Get-ChildItem $sharePath | Select-Object -First 3 | Format-Table Name, LastWriteTime
        } else {
            Write-Output "Cannot access: $sharePath"
        }
    } catch {
        Write-Output "Error: $($_.Exception.Message)"
    }
    '''
    
    output, errors, had_errors = netonly_pool.execute_script(network_script)
    
    if not had_errors:
        print("[+] Network test completed:")
        for line in output:
            print(f"    {line}")
    else:
        print("[-] Network test failed:")
        for error in errors:
            print(f"    ERROR: {error}")
    
    # Step 6: Clean up resources
    print("\n[*] Cleaning up...")
    netonly_pool.cleanup()
    print("[+] Cleanup complete!")

if __name__ == "__main__":
    # Note: This is a conceptual example
    # In practice, you would need to establish a real WinRM connection first
    print("=" * 60)
    print("NetOnlyRunspacePool Example")
    print("=" * 60)
    print()
    print("This is a conceptual example demonstrating the API.")
    print("To run this, you need a live WinRM connection.")
    print()
    print("See the evil-winrm-py documentation for connection setup.")
    print("=" * 60)
    
    # Uncomment the following line if you have a real connection:
    # main()
