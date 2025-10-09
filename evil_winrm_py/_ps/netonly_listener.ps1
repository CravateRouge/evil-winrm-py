# This script is part of evil-winrm-py project https://github.com/adityatelange/evil-winrm-py
# This script runs in the nested PowerShell process created by CreateProcessWithLogonW
# It creates a named pipe server and listens for commands to execute

param (
    [Parameter(Mandatory=$true)]
    [string]$PipeName
)

# Function to execute command and return results as JSON
function Invoke-CommandInContext {
    param (
        [string]$CommandText,
        [string]$CommandType  # "Command" or "Script"
    )
    
    try {
        $output = @()
        $errors = @()
        
        # Execute the command/script
        if ($CommandType -eq "Script") {
            $scriptBlock = [ScriptBlock]::Create($CommandText)
            $output = & $scriptBlock 2>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    $errors += $_
                } else {
                    $_
                }
            }
        } else {
            # Execute as command
            $output = Invoke-Expression $CommandText 2>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    $errors += $_
                } else {
                    $_
                }
            }
        }
        
        # Convert output to strings
        $outputStrings = $output | Out-String -Stream | Where-Object { $_ }
        $errorStrings = $errors | ForEach-Object { $_.ToString() }
        
        [PSCustomObject]@{
            Type = "Success"
            Output = $outputStrings
            Errors = $errorStrings
        }
    }
    catch {
        [PSCustomObject]@{
            Type = "Error"
            Message = $_.Exception.Message
            Details = $_.Exception.ToString()
        }
    }
}

# Main listener loop
try {
    $pipeSecurity = New-Object System.IO.Pipes.PipeSecurity
    $pipeAccessRule = New-Object System.IO.Pipes.PipeAccessRule(
        "Everyone",
        [System.IO.Pipes.PipeAccessRights]::FullControl,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $pipeSecurity.AddAccessRule($pipeAccessRule)
    
    # Keep listening for commands
    $keepRunning = $true
    while ($keepRunning) {
        # Create named pipe server
        $pipeServer = New-Object System.IO.Pipes.NamedPipeServerStream(
            $PipeName,
            [System.IO.Pipes.PipeDirection]::InOut,
            1,  # Max instances
            [System.IO.Pipes.PipeTransmissionMode]::Byte,
            [System.IO.Pipes.PipeOptions]::None,
            1024,  # Input buffer
            1024,  # Output buffer
            $pipeSecurity
        )
        
        # Wait for client connection (with timeout)
        $asyncResult = $pipeServer.BeginWaitForConnection($null, $null)
        $waitHandle = $asyncResult.AsyncWaitHandle
        
        # Wait for connection or timeout (30 seconds)
        if ($waitHandle.WaitOne(30000)) {
            $pipeServer.EndWaitForConnection($asyncResult)
            
            # Read command from pipe
            $reader = New-Object System.IO.StreamReader($pipeServer)
            $requestJson = $reader.ReadLine()
            
            if ($requestJson) {
                $request = $requestJson | ConvertFrom-Json
                
                # Check for exit command
                if ($request.Action -eq "Exit") {
                    $keepRunning = $false
                    $response = [PSCustomObject]@{
                        Type = "Success"
                        Message = "Exiting listener"
                    }
                }
                # Execute command
                elseif ($request.Action -eq "Execute") {
                    $response = Invoke-CommandInContext -CommandText $request.Command -CommandType $request.CommandType
                }
                # Status check
                elseif ($request.Action -eq "Status") {
                    $response = [PSCustomObject]@{
                        Type = "Success"
                        Message = "Listener is active"
                        ProcessId = $PID
                    }
                }
                else {
                    $response = [PSCustomObject]@{
                        Type = "Error"
                        Message = "Unknown action: $($request.Action)"
                    }
                }
                
                # Send response back
                $writer = New-Object System.IO.StreamWriter($pipeServer)
                $writer.AutoFlush = $true
                $responseJson = $response | ConvertTo-Json -Compress -Depth 10
                $writer.WriteLine($responseJson)
            }
            
            # Clean up
            if ($reader) { $reader.Dispose() }
            if ($writer) { $writer.Dispose() }
        }
        
        # Clean up pipe
        $pipeServer.Dispose()
    }
}
catch {
    # Log error to a file for debugging
    $errorFile = Join-Path $env:TEMP "netonly_listener_error.txt"
    "Error in listener: $($_.Exception.Message)" | Out-File -FilePath $errorFile -Append
    $_.Exception.ToString() | Out-File -FilePath $errorFile -Append
}
finally {
    if ($pipeServer) {
        $pipeServer.Dispose()
    }
}
