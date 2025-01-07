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

    $CippBackupParams = @{}
    if ($Request.Query.Type) {
        $CippBackupParams.Type = $Request.Query.Type
    }
    if ($Request.Query.TenantFilter) {
        $CippBackupParams.TenantFilter = $Request.Query.TenantFilter
    }
    if ($Request.Query.NameOnly) {
        $CippBackupParams.NameOnly = $true
    }
    if ($Request.Query.BackupName) {
        $CippBackupParams.Name = $Request.Query.BackupName
    }

    $Result = Get-CIPPBackup @CippBackupParams
    Write-Host ($Result | ConvertTo-Json)
    if ($request.Query.NameOnly) {
        $Result = $Result | Select-Object @{Name = 'BackupName'; exp = { $_.RowKey } }, Timestamp | Sort-Object Timestamp -Descending
    }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API 'Alerts' -message $request.body.text -Sev $request.body.Severity
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Result)
        })

}
