using namespace System.Net

Function Invoke-ExecListBackup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Backup.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Type = $Request.Query.Type
    $TenantFilter = $Request.Query.tenantFilter
    $NameOnly = $Request.Query.NameOnly
    $BackupName = $Request.Query.BackupName

    $CippBackupParams = @{}
    if ($Type) {
        $CippBackupParams.Type = $Type
    }
    if ($TenantFilter) {
        $CippBackupParams.TenantFilter = $TenantFilter
    }
    if ($NameOnly) {
        $CippBackupParams.NameOnly = $true
    }
    if ($BackupName) {
        $CippBackupParams.Name = $BackupName
    }

    $Result = Get-CIPPBackup @CippBackupParams

    if ($NameOnly) {
        $Result = $Result | Select-Object @{Name = 'BackupName'; exp = { $_.RowKey } }, Timestamp | Sort-Object Timestamp -Descending
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Result)
        })

}
