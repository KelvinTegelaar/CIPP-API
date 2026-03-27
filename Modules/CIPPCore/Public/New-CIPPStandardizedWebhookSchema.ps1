function New-CIPPStandardizedWebhookSchema {
    <#
    .SYNOPSIS
        Builds a standardized webhook alert payload.

    .DESCRIPTION
        Converts legacy alert payloads (string/object/array) into a stable, versioned JSON schema
        for webhook consumers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        $Payload,

        [Parameter(Mandatory = $false)]
        [string]$Source = 'CIPP',

        [Parameter(Mandatory = $false)]
        [string]$InvokingCommand
    )

    $NormalizedPayload = $null

    if ($null -eq $Payload) {
        $NormalizedPayload = [pscustomobject]@{}
    } elseif ($Payload -is [string]) {
        if (Test-Json -Json $Payload -ErrorAction SilentlyContinue) {
            $NormalizedPayload = $Payload | ConvertFrom-Json -Depth 50
        } else {
            $NormalizedPayload = [pscustomobject]@{
                message = $Payload
            }
        }
    } else {
        $NormalizedPayload = $Payload
    }

    $AlertCount = if ($NormalizedPayload -is [array]) { $NormalizedPayload.Count } else { 1 }

    $DetectedInvokingCommand = $null

    if ($NormalizedPayload -is [array] -and $NormalizedPayload.Count -gt 0) {
        if ($NormalizedPayload[0].PSObject.Properties.Name -contains 'API') {
            $ApiList = @($NormalizedPayload | Where-Object { $_.API } | Select-Object -ExpandProperty API -Unique)
            if ($ApiList.Count -gt 0) {
                $DetectedInvokingCommand = $ApiList -join ', '
            }
        }
    } elseif ($NormalizedPayload -isnot [string] -and $null -ne $NormalizedPayload) {
        if ($NormalizedPayload.PSObject.Properties.Name -contains 'task' -and $NormalizedPayload.task) {
            if ($NormalizedPayload.task.PSObject.Properties.Name -contains 'command' -and $NormalizedPayload.task.command) {
                $DetectedInvokingCommand = [string]$NormalizedPayload.task.command
            }
        }

        if (-not $DetectedInvokingCommand -and $NormalizedPayload.PSObject.Properties.Name -contains 'TaskInfo' -and $NormalizedPayload.TaskInfo) {
            if ($NormalizedPayload.TaskInfo.PSObject.Properties.Name -contains 'Command' -and $NormalizedPayload.TaskInfo.Command) {
                $DetectedInvokingCommand = [string]$NormalizedPayload.TaskInfo.Command
            }
        }

    }

    $ResolvedInvokingCommand = if (![string]::IsNullOrWhiteSpace($InvokingCommand)) { $InvokingCommand } elseif ($DetectedInvokingCommand) { $DetectedInvokingCommand } else { $null }

    $SchemaObject = [ordered]@{
        schemaVersion = '1.0'
        source        = $Source
        invoking      = $ResolvedInvokingCommand
        title         = $Title
        tenant        = $TenantFilter
        generatedAt   = [datetime]::UtcNow.ToString('o')
        alertCount    = $AlertCount
        payload       = $NormalizedPayload
    }

    return [pscustomobject]$SchemaObject
}
