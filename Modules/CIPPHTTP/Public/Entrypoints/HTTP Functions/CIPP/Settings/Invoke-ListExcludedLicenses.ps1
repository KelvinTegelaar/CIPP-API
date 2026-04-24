function Invoke-ListExcludedLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $Table = Get-CIPPTable -TableName ExcludedLicenses
        $Rows = Get-CIPPAzDataTableEntity @Table

        # If no excluded licenses exist, initialize them
        if ($Rows.Count -lt 1) {
            Write-Information 'Excluded licenses table is empty. Initializing from config file.'
            $null = Initialize-CIPPExcludedLicenses -Headers $Headers -APIName $APIName
            $Rows = Get-CIPPAzDataTableEntity @Table
        }

        $Results = @($Rows)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Results = "Failed to list excluded licenses. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -headers $Headers -message $Results -Sev 'Error' -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode ?? [HttpStatusCode]::OK
            Body       = [pscustomobject]@{ 'Results' = $Results }
        })
}
