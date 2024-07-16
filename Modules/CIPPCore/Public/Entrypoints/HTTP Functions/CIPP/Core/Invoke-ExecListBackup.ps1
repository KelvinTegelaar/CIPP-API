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

    $Result = Get-CIPPBackup -type $Request.query.Type -TenantFilter $Request.query.TenantFilter
    if ($request.query.NameOnly) {
        $Result = $Result | Select-Object RowKey, timestamp
    }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API 'Alerts' -message $request.body.text -Sev $request.body.Severity
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Result)
        })

}
