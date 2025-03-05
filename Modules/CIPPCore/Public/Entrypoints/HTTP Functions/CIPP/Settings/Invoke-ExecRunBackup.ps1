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

    $APIName = $Request.Params.CIPPEndpoint

    try {
        $CSVfile = New-CIPPBackup -BackupType 'CIPP' -Headers $Request.Headers
        $body = [pscustomobject]@{
            'Results' = @{
                resultText = 'Created backup'
                state      = 'success'
            }
            backup    = $CSVfile.BackupData
        } | ConvertTo-Json -Depth 5 -Compress

        Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Created CIPP backup' -Sev 'Info'

    } catch {
        $body = [pscustomobject]@{
            'Results' = @(
                @{
                    resultText = 'Failed to create backup'
                    state      = 'error'
                }
            )
        } | ConvertTo-Json -Depth 5 -Compress
        Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Failed to create CIPP backup' -Sev 'Error' -LogData (Get-CippException -Exception $_)
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
