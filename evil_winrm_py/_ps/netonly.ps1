# This script is part of evil-winrm-py project https://github.com/adityatelange/evil-winrm-py
# It creates a process using CreateProcessWithLogonW with LOGON_NETCREDENTIALS_ONLY flag.
# This allows the process to run with network-only credentials (similar to runas /netonly).

param (
    [Parameter(Mandatory=$true)]
    [string]$Username,
    
    [Parameter(Mandatory=$true)]
    [string]$Password,
    
    [Parameter(Mandatory=$false)]
    [string]$Domain = ".",
    
    [Parameter(Mandatory=$false)]
    [string]$CommandLine = "powershell.exe -NoExit -Command `"Write-Host 'NetOnly session started'`""
)

# Define P/Invoke signatures for CreateProcessWithLogonW
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class ProcessWithLogon
{
    // Constants
    public const int LOGON_WITH_PROFILE = 0x00000001;
    public const int LOGON_NETCREDENTIALS_ONLY = 0x00000002;
    
    public const int CREATE_DEFAULT_ERROR_MODE = 0x04000000;
    public const int CREATE_NEW_CONSOLE = 0x00000010;
    public const int CREATE_NEW_PROCESS_GROUP = 0x00000200;
    public const int CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    
    // STARTUPINFO structure
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO
    {
        public Int32 cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public Int32 dwX;
        public Int32 dwY;
        public Int32 dwXSize;
        public Int32 dwYSize;
        public Int32 dwXCountChars;
        public Int32 dwYCountChars;
        public Int32 dwFillAttribute;
        public Int32 dwFlags;
        public Int16 wShowWindow;
        public Int16 cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }
    
    // PROCESS_INFORMATION structure
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION
    {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }
    
    // CreateProcessWithLogonW P/Invoke signature
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateProcessWithLogonW(
        string lpUsername,
        string lpDomain,
        string lpPassword,
        int dwLogonFlags,
        string lpApplicationName,
        string lpCommandLine,
        int dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation
    );
    
    // CloseHandle to clean up handles
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
    
    // GetLastError
    [DllImport("kernel32.dll")]
    public static extern uint GetLastError();
}
"@

try {
    # Initialize STARTUPINFO structure
    $startupInfo = New-Object ProcessWithLogon+STARTUPINFO
    $startupInfo.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($startupInfo)
    
    # Initialize PROCESS_INFORMATION structure
    $processInfo = New-Object ProcessWithLogon+PROCESS_INFORMATION
    
    # Set creation flags - LOGON_NETCREDENTIALS_ONLY is the key flag here
    $logonFlags = [ProcessWithLogon]::LOGON_NETCREDENTIALS_ONLY
    $creationFlags = [ProcessWithLogon]::CREATE_NEW_CONSOLE
    
    # Call CreateProcessWithLogonW
    $success = [ProcessWithLogon]::CreateProcessWithLogonW(
        $Username,
        $Domain,
        $Password,
        $logonFlags,
        $null,  # lpApplicationName (null means use command line)
        $CommandLine,
        $creationFlags,
        [IntPtr]::Zero,  # lpEnvironment (null means inherit)
        $null,  # lpCurrentDirectory (null means inherit)
        [ref]$startupInfo,
        [ref]$processInfo
    )
    
    if ($success) {
        # Return success information as JSON
        [PSCustomObject]@{
            Type = "Success"
            Message = "Process created successfully with LOGON_NETCREDENTIALS_ONLY"
            ProcessId = $processInfo.dwProcessId
            ThreadId = $processInfo.dwThreadId
            ProcessHandle = $processInfo.hProcess.ToInt64()
            ThreadHandle = $processInfo.hThread.ToInt64()
        } | ConvertTo-Json -Compress | Write-Output
        
        # Clean up handles
        [ProcessWithLogon]::CloseHandle($processInfo.hProcess) | Out-Null
        [ProcessWithLogon]::CloseHandle($processInfo.hThread) | Out-Null
    }
    else {
        $errorCode = [ProcessWithLogon]::GetLastError()
        [PSCustomObject]@{
            Type = "Error"
            Message = "Failed to create process with CreateProcessWithLogonW"
            ErrorCode = $errorCode
        } | ConvertTo-Json -Compress | Write-Output
        exit 1
    }
}
catch {
    [PSCustomObject]@{
        Type = "Error"
        Message = "Exception occurred: $($_.Exception.Message)"
        Details = $_.Exception.ToString()
    } | ConvertTo-Json -Compress | Write-Output
    exit 1
}
