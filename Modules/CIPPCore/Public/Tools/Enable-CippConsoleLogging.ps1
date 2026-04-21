# Define log level enum at script scope
enum CippConsoleLogLevel {
    Debug = 0
    Verbose = 1
    Information = 2
    Warning = 3
    Error = 4
}

function Enable-CippConsoleLogging {
    <#
    .SYNOPSIS
        Enable console output logging to Application Insights
    .DESCRIPTION
        Overrides Write-Information, Write-Warning, Write-Error, Write-Verbose, and Write-Debug
        functions to send telemetry to Application Insights while maintaining normal console output
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Enable-CippConsoleLogging

        # Now all Write-* calls will be logged to Application Insights
        Write-Information "This will be logged"
        Write-Warning "This warning will be logged"
    #>
    [CmdletBinding()]
    param()

    # Initialize AsyncLocal storage for InvocationId (thread-safe)
    if (-not $script:CippInvocationIdStorage) {
        $script:CippInvocationIdStorage = [System.Threading.AsyncLocal[string]]::new()
    }

    # Set minimum log level from environment variable (default: Information)
    $validLevels = @('Debug', 'Verbose', 'Information', 'Warning', 'Error')
    $configuredLevel = $env:CIPP_CONSOLE_LOG_LEVEL
    $global:CippConsoleLogMinLevel = if ($configuredLevel -and $configuredLevel -in $validLevels) {
        $configuredLevel
    } else {
        'Information'
    }

    if ($env:CIPP_CONSOLE_LOG_LEVEL -eq 'Debug') {
        $global:DebugPreference = 'Continue'
    }

    # Override Write-Information
    function global:Write-Information {
        [CmdletBinding()]
        param(
            [Parameter(Position = 0, ValueFromPipeline)]
            [object]$MessageData,
            [string[]]$Tags
        )

        # Only process and call original if MessageData is provided
        if ($PSBoundParameters.ContainsKey('MessageData') -and $MessageData) {
            # Send to telemetry
            if (-not [string]::IsNullOrWhiteSpace(($MessageData | Out-String).Trim())) {
                # If tag is supplied, include it in the log message
                $LogMessage = if ($Tags -and $Tags.Count -gt 0) {
                    '[{0}] {1}' -f ($Tags -join ','), ($MessageData | Out-String).Trim()
                } else {
                    ($MessageData | Out-String).Trim()
                }
                Send-CippConsoleLog -Message $LogMessage -Level 'Information'
            }

            # Call original function
            Microsoft.PowerShell.Utility\Write-Information @PSBoundParameters
        }
    }

    # Override Write-Warning
    function global:Write-Warning {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
            [string]$Message
        )

        # Send to telemetry
        if ($Message -and -not [string]::IsNullOrWhiteSpace($Message)) {
            Send-CippConsoleLog -Message $Message -Level 'Warning'
        }

        # Call original function
        Microsoft.PowerShell.Utility\Write-Warning @PSBoundParameters
    }

    # Override Write-Error
    function global:Write-Error {
        [CmdletBinding()]
        param(
            [Parameter(Position = 0, ValueFromPipeline)]
            [object]$Message,
            [object]$Exception,
            [object]$ErrorRecord,
            [string]$ErrorId,
            [System.Management.Automation.ErrorCategory]$Category,
            [object]$TargetObject,
            [string]$RecommendedAction,
            [string]$CategoryActivity,
            [string]$CategoryReason,
            [string]$CategoryTargetName,
            [string]$CategoryTargetType
        )

        # Send to telemetry
        $errorMessage = if ($Message) { ($Message | Out-String).Trim() }
        elseif ($Exception) { $Exception.Message }
        elseif ($ErrorRecord) { $ErrorRecord.Exception.Message }
        else { 'Unknown error' }

        if ($errorMessage -and -not [string]::IsNullOrWhiteSpace($errorMessage)) {
            Send-CippConsoleLog -Message $errorMessage -Level 'Error'
        }

        # Call original function
        Microsoft.PowerShell.Utility\Write-Error @PSBoundParameters
    }

    # Override Write-Verbose
    function global:Write-Verbose {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
            [string]$Message
        )

        # Send to telemetry
        if ($Message -and -not [string]::IsNullOrWhiteSpace($Message)) {
            Send-CippConsoleLog -Message $Message -Level 'Verbose'
        }

        # Call original function
        Microsoft.PowerShell.Utility\Write-Verbose @PSBoundParameters
    }

    # Override Write-Debug
    function global:Write-Debug {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
            [string]$Message
        )

        # Send to telemetry
        if ($Message -and -not [string]::IsNullOrWhiteSpace($Message)) {
            Send-CippConsoleLog -Message $Message -Level 'Debug'
        }

        # Call original function
        Microsoft.PowerShell.Utility\Write-Debug @PSBoundParameters
    }

    # Override Write-Host
    function global:Write-Host {
        [CmdletBinding()]
        param(
            [Parameter(Position = 0, ValueFromPipeline)]
            [object]$Object,
            [switch]$NoNewline,
            [object]$Separator,
            [System.ConsoleColor]$ForegroundColor,
            [System.ConsoleColor]$BackgroundColor
        )

        # Send to telemetry
        $message = if ($Object) { ($Object | Out-String).Trim() } else { '' }
        if ($message -and -not [string]::IsNullOrWhiteSpace($message)) {
            Send-CippConsoleLog -Message $message -Level 'Information'
        }

        # Call original function
        Microsoft.PowerShell.Utility\Write-Host @PSBoundParameters
    }
}
