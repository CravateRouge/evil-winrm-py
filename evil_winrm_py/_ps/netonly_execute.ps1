# This script is part of evil-winrm-py project https://github.com/adityatelange/evil-winrm-py
# It sends commands to the nested PowerShell process via named pipe
# This uses named pipes for IPC between the parent and nested processes

param (
    [Parameter(Mandatory=$true)]
    [string]$PipeName,
    
    [Parameter(Mandatory=$false)]
    [string]$Command,
    
    [Parameter(Mandatory=$false)]
    [string]$Script,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Execute", "Status", "Exit")]
    [string]$Action = "Execute",
    
    [Parameter(Mandatory=$false)]
    [int]$TimeoutSeconds = 300
)

try {
    # Determine command type and text
    $commandType = "Command"
    $commandText = $Command
    
    if ($Action -eq "Execute") {
        if ($Script) {
            $commandType = "Script"
            $commandText = $Script
        }
        elseif (-not $Command) {
            [PSCustomObject]@{
                Type = "Error"
                Message = "Either Command or Script parameter is required for Execute action"
            } | ConvertTo-Json -Compress | Write-Output
            exit 1
        }
    }
    
    # Create the request object
    $request = [PSCustomObject]@{
        Action = $Action
        Command = $commandText
        CommandType = $commandType
    }
    
    # Convert to JSON
    $requestJson = $request | ConvertTo-Json -Compress
    
    # Connect to named pipe
    $pipeClient = New-Object System.IO.Pipes.NamedPipeClientStream(
        ".",  # Local machine
        $PipeName,
        [System.IO.Pipes.PipeDirection]::InOut,
        [System.IO.Pipes.PipeOptions]::None
    )
    
    # Connect with timeout
    $pipeClient.Connect($TimeoutSeconds * 1000)
    
    if (-not $pipeClient.IsConnected) {
        [PSCustomObject]@{
            Type = "Error"
            Message = "Failed to connect to named pipe: $PipeName"
        } | ConvertTo-Json -Compress | Write-Output
        exit 1
    }
    
    # Send request
    $writer = New-Object System.IO.StreamWriter($pipeClient)
    $writer.AutoFlush = $true
    $writer.WriteLine($requestJson)
    
    # Read response
    $reader = New-Object System.IO.StreamReader($pipeClient)
    $responseJson = $reader.ReadLine()
    
    # Clean up
    $reader.Dispose()
    $writer.Dispose()
    $pipeClient.Dispose()
    
    # Output response
    if ($responseJson) {
        Write-Output $responseJson
    } else {
        [PSCustomObject]@{
            Type = "Error"
            Message = "No response received from pipe"
        } | ConvertTo-Json -Compress | Write-Output
        exit 1
    }
}
catch {
    [PSCustomObject]@{
        Type = "Error"
        Message = "Failed to communicate with pipe: $($_.Exception.Message)"
        Details = $_.Exception.ToString()
    } | ConvertTo-Json -Compress | Write-Output
    exit 1
}
finally {
    if ($pipeClient) {
        $pipeClient.Dispose()
    }
}
