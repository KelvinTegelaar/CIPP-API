function Send-CippConsoleLog {
    <#
    .SYNOPSIS
        Send console log message to Application Insights
    .DESCRIPTION
        Helper function to send console output to Application Insights telemetry
    .PARAMETER Message
        The message to log
    .PARAMETER Level
        The log level (Debug, Verbose, Information, Warning, Error)
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Debug', 'Verbose', 'Information', 'Warning', 'Error')]
        [string]$Level
    )

    if ($global:TelemetryClient) {
        try {
            # Map level names to numeric values for comparison
            $levelMap = @{
                'Debug'       = 0
                'Verbose'     = 1
                'Information' = 2
                'Warning'     = 3
                'Error'       = 4
            }

            $currentLevelValue = $levelMap[$Level]
            $minLevelValue = $levelMap[$global:CippConsoleLogMinLevel]

            # Check if this level should be logged
            if ($null -ne $minLevelValue -and $currentLevelValue -ge $minLevelValue) {
                $props = New-Object 'System.Collections.Generic.Dictionary[string,string]'
                $props['Message'] = $Message
                $props['Level'] = $Level
                $props['Timestamp'] = (Get-Date).ToString('o')

                # Add InvocationId if available (from AsyncLocal storage)
                if ($script:CippInvocationIdStorage -and $script:CippInvocationIdStorage.Value) {
                    $props['InvocationId'] = $script:CippInvocationIdStorage.Value
                }

                $global:TelemetryClient.TrackEvent('CIPP.ConsoleLog', $props, $null)
            }
        } catch {
            # Silently fail to avoid infinite loops
        }
    }
}
