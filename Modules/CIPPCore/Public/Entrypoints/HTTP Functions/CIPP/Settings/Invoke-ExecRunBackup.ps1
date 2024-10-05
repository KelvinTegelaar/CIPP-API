using namespace System.Net

Function Invoke-ExecRunBackup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $CSVfile = New-CIPPBackup -BackupType 'CIPP'
    $body = [pscustomobject]@{
        'Results' = 'Created backup'
        backup    = $CSVfile.BackupData
    } | ConvertTo-Json -Depth 5 -Compress
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
