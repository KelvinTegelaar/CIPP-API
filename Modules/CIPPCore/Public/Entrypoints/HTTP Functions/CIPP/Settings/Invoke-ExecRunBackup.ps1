using namespace System.Net

function Invoke-ExecRunBackup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $CSVfile = New-CIPPBackup -BackupType 'CIPP' -Headers $Headers
        $Body = [pscustomobject]@{
            'Results' = @{
                resultText = 'Created backup'
                state      = 'success'
            }
            backup    = $CSVfile.BackupData
        } | ConvertTo-Json -Depth 5 -Compress

        Write-LogMessage -headers $Headers -API $APIName -message 'Created CIPP backup' -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Body = [pscustomobject]@{
            'Results' = @(
                @{
                    resultText = 'Failed to create backup'
                    state      = 'error'
                }
            )
        } | ConvertTo-Json -Depth 5 -Compress
        Write-LogMessage -headers $Headers -API $APIName -message 'Failed to create CIPP backup' -Sev 'Error' -LogData (Get-CippException -Exception $_)
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Body }
    }
}
