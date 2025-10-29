
function Invoke-ExecOffloadFunctions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'Config'

    if ($Request.Query.Action -eq 'ListCurrent') {
        $CurrentState = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"
        $VersionTable = Get-CippTable -tablename 'Version'
        $Version = Get-CIPPAzDataTableEntity @VersionTable -Filter "RowKey ne 'Version'"
        $MainVersion = $Version | Where-Object { $_.RowKey -eq $env:WEBSITE_SITE_NAME }
        $OffloadVersions = $Version | Where-Object { $_.RowKey -match '-' }

        $Alerts = [System.Collections.Generic.List[string]]::new()

        $CanEnable = $false
        if (!$OffloadVersions.Version) {
            $Alerts.Add('No offloaded function apps have been registered. If you''ve just deployed one, this can take up to 15 minutes.')
        } else {
            $CanEnable = $true
        }

        foreach ($Offload in $OffloadVersions) {
            $FunctionName = $Offload.RowKey
            if ([semver]$Offload.Version -ne [semver]$MainVersion.Version) {
                $CanEnable = $false
                $Alerts.Add("The version of $FunctionName ($($Offload.Version)) does not match the current version of $($MainVersion.Version).")
            }
        }

        $VersionTable = $Version | Select-Object @{n = 'Name'; e = { $_.RowKey } }, @{n = 'Version'; e = { $_.Version } }, @{n = 'Default'; e = { $_.RowKey -notmatch '-' } }

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
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ results = $Results }
            })
    }
}
