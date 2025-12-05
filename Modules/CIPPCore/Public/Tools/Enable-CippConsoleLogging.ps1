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

    # Store the original functions
    if (-not $global:CippOriginalWriteFunctions) {
        $global:CippOriginalWriteFunctions = @{
            Information = Get-Command Write-Information -CommandType Cmdlet
            Warning     = Get-Command Write-Warning -CommandType Cmdlet
            Error       = Get-Command Write-Error -CommandType Cmdlet
            Verbose     = Get-Command Write-Verbose -CommandType Cmdlet
            Debug       = Get-Command Write-Debug -CommandType Cmdlet
            Host        = Get-Command Write-Host -CommandType Cmdlet
        }
    }

    # Define log level enum
    enum CippConsoleLogLevel {
        Debug = 0
        Verbose = 1
        Information = 2
        Warning = 3
        Error = 4
    }

    # Set minimum log level from environment variable (default: Information)
    $configuredLevel = $env:CIPP_CONSOLE_LOG_LEVEL
    $global:CippConsoleLogMinLevel = if ($configuredLevel) {
        try {
            [CippConsoleLogLevel]$configuredLevel
        } catch {
            [CippConsoleLogLevel]::Information
        }
    } else {
        [CippConsoleLogLevel]::Information
    }

    # Helper function to send log to Application Insights
    $global:SendCippConsoleLog = {
        param([string]$Message, [CippConsoleLogLevel]$Level)

        if ($global:TelemetryClient) {
            try {
                # Check if this level should be logged
                if ($Level -ge $global:CippConsoleLogMinLevel) {
                    $props = New-Object 'System.Collections.Generic.Dictionary[string,string]'
                    $props['Message'] = $Message
                    $props['Level'] = $Level.ToString()
                    $props['Timestamp'] = (Get-Date).ToString('o')

                    $global:TelemetryClient.TrackEvent('CIPP.ConsoleLog', $props, $null)
                }
            } catch {
                # Silently fail to avoid infinite loops
            }
        }
    }

    # Override Write-Information
    function global:Write-Information {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
            [object]$MessageData,
            [string[]]$Tags
        )

        # Send to telemetry
        & $global:SendCippConsoleLog -Message ($MessageData | Out-String).Trim() -Level ([CippConsoleLogLevel]::Information)

        # Call original function
        & $global:CippOriginalWriteFunctions.Information.ScriptBlock @PSBoundParameters
    }

    # Override Write-Warning
    function global:Write-Warning {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
            [string]$Message
        )

        # Send to telemetry
        & $global:SendCippConsoleLog -Message $Message -Level ([CippConsoleLogLevel]::Warning)

        # Call original function
        & $global:CippOriginalWriteFunctions.Warning.ScriptBlock @PSBoundParameters
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
        & $global:SendCippConsoleLog -Message $errorMessage -Level ([CippConsoleLogLevel]::Error)

        # Call original function
        & $global:CippOriginalWriteFunctions.Error.ScriptBlock @PSBoundParameters
    }

    # Override Write-Verbose
    function global:Write-Verbose {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
            [string]$Message
        )

        # Send to telemetry
        & $global:SendCippConsoleLog -Message $Message -Level ([CippConsoleLogLevel]::Verbose)

        # Call original function
        & $global:CippOriginalWriteFunctions.Verbose.ScriptBlock @PSBoundParameters
    }

    # Override Write-Debug
    function global:Write-Debug {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
            [string]$Message
        )

        # Send to telemetry
        & $global:SendCippConsoleLog -Message $Message -Level ([CippConsoleLogLevel]::Debug)

        # Call original function
        & $global:CippOriginalWriteFunctions.Debug.ScriptBlock @PSBoundParameters
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
        & $global:SendCippConsoleLog -Message $message -Level ([CippConsoleLogLevel]::Information)

        # Call original function
        & $global:CippOriginalWriteFunctions.Host.ScriptBlock @PSBoundParameters
    }
}
