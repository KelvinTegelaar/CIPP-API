function Measure-CippTask {
    <#
    .SYNOPSIS
        Measure and track CIPP task execution with Application Insights telemetry
    .DESCRIPTION
        Wraps task execution in a timer, sends custom event to Application Insights with duration and metadata
    .PARAMETER TaskName
        The name of the task being executed (e.g., "New-CIPPTemplateRun")
    .PARAMETER Script
        The scriptblock to execute and measure
    .PARAMETER Metadata
        Optional hashtable of metadata to include in telemetry (e.g., Command, Tenant, TaskInfo)
    .PARAMETER EventName
        Optional custom event name (default: "CIPP.TaskCompleted")
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Measure-CippTask -TaskName "ApplyTemplate" -Script {
            # Task logic here
        } -Metadata @{
            Command = "New-CIPPTemplateRun"
            Tenant = "contoso.onmicrosoft.com"
        }
    .EXAMPLE
        Measure-CippTask -TaskName "DisableGuests" -EventName "CIPP.StandardCompleted" -Script {
            # Standard logic here
        } -Metadata @{
            Standard = "DisableGuests"
            Tenant = "contoso.onmicrosoft.com"
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskName,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Script,

        [Parameter(Mandatory = $false)]
        [hashtable]$Metadata,

        [Parameter(Mandatory = $false)]
        [string]$EventName = 'CIPP.TaskCompleted'
    )

    # Initialize tracking variables
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = $null
    $errorOccurred = $false
    $errorMessage = $null

    try {
        # Execute the actual task (use dot-sourcing to preserve parent scope variables)
        $result = . $Script
    } catch {
        $errorOccurred = $true
        $errorMessage = $_.Exception.Message
        # Re-throw to preserve original error behavior
        throw
    } finally {
        # Stop the timer
        $sw.Stop()
        $durationMs = [int]$sw.Elapsed.TotalMilliseconds

        # Send telemetry if TelemetryClient is available
        if ($global:TelemetryClient) {
            try {
                # Build properties dictionary for customDimensions
                $props = New-Object 'System.Collections.Generic.Dictionary[string,string]'
                $props['TaskName'] = $TaskName
                $props['Success'] = (-not $errorOccurred).ToString()
                $props['RawPropsAsJson'] = ($Metadata | ConvertTo-Json -Compress)
                if ($errorOccurred) {
                    $props['ErrorMessage'] = $errorMessage
                }

                # Add all metadata to properties
                if ($Metadata) {
                    foreach ($key in $Metadata.Keys) {
                        $value = $Metadata[$key]
                        # Convert value to string, handling nulls
                        if ($null -ne $value) {
                            $props[$key] = [string]$value
                        } else {
                            $props[$key] = ''
                        }
                    }
                }

                # Metrics dictionary for customMeasurements
                $metrics = New-Object 'System.Collections.Generic.Dictionary[string,double]'
                $metrics['DurationMs'] = [double]$durationMs

                # Send custom event to Application Insights
                $global:TelemetryClient.TrackEvent($EventName, $props, $metrics)
                $global:TelemetryClient.Flush()

                Write-Verbose "Telemetry sent for task '$TaskName' to event '$EventName' (${durationMs}ms)"
            } catch {
                Write-Warning "Failed to send telemetry for task '${TaskName}': $($_.Exception.Message)"
            }
        } else {
            Write-Verbose "TelemetryClient not initialized, skipping telemetry for task '$TaskName'"
        }
    }

    return $result
}
