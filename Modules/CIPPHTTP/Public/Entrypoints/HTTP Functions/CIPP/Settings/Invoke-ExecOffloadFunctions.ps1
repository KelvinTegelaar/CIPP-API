
function Invoke-ExecOffloadFunctions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $Table = Get-CippTable -tablename 'Config'

    if ($Request.Query.Action -eq 'ListCurrent') {
        $CurrentState = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"
        $VersionTable = Get-CippTable -tablename 'Version'
        $Version = Get-CIPPAzDataTableEntity @VersionTable -Filter "RowKey ne 'Version'"
        $MainVersion = $Version | Where-Object { $_.RowKey -eq $env:WEBSITE_SITE_NAME }
        # The main app's row is keyed by WEBSITE_SITE_NAME, which the container runtime does not
        # set, so fall back to the running build rather than comparing against an empty string.
        $MainVersionString = if ($MainVersion.Version) { $MainVersion.Version } elseif ($env:APP_VERSION) { $env:APP_VERSION } else { $null }
        $OffloadVersions = $Version | Where-Object { Test-CippOffloadFunctionApp -SiteName $_.RowKey }

        $Alerts = [System.Collections.Generic.List[string]]::new()

        $CanEnable = $false
        if (!$OffloadVersions.Version) {
            $Alerts.Add('No offloaded function apps have been registered. If you''ve just deployed one, this can take up to 15 minutes.')
        } else {
            $CanEnable = $true
        }

        foreach ($Offload in $OffloadVersions) {
            $FunctionName = $Offload.RowKey
            if (-not $MainVersionString) {
                $CanEnable = $false
                $Alerts.Add("The version of $FunctionName ($($Offload.Version)) could not be checked because the current version is unknown.")
            } elseif ([semver]$Offload.Version -ne [semver]$MainVersionString) {
                $CanEnable = $false
                $Alerts.Add("The version of $FunctionName ($($Offload.Version)) does not match the current version of $MainVersionString.")
            }
        }

        $VersionTable = $Version | Select-Object @{n = 'Name'; e = { $_.RowKey } }, @{n = 'Version'; e = { $_.Version } }, @{n = 'Default'; e = { -not (Test-CippOffloadFunctionApp -SiteName $_.RowKey) } }

        $CurrentState = if (!$CurrentState) {
            [PSCustomObject]@{
                OffloadFunctions = $false
                Version          = @($VersionTable)
                Alerts           = $Alerts
                CanEnable        = $CanEnable
            }
        } else {
            [PSCustomObject]@{
                OffloadFunctions = $CurrentState.state
                Version          = @($VersionTable)
                Alerts           = $Alerts
                CanEnable        = $CanEnable
            }
        }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $CurrentState
            })
    } else {
        if ($env:CIPP_HOSTED -eq 'true') {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = @{ results = 'Offload function configuration is not available on hosted instances. Please contact the helpdesk to make changes' }
                })
        }

        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = 'OffloadFunctions'
            RowKey       = 'OffloadFunctions'
            state        = $request.Body.OffloadFunctions
        } -Force

        if ($Request.Body.OffloadFunctions) {
            $Results = 'Enabled Offload Functions'
        } else {
            $Results = 'Disabled Offload Functions'
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Results -Sev 'Info'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ results = $Results }
            })
    }
}

