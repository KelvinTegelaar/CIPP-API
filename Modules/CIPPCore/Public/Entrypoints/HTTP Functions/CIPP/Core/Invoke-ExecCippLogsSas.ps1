function Invoke-ExecCippLogsSas {
    <#
    .SYNOPSIS
        Generate a read-only SAS token for the CippLogs table
    .DESCRIPTION
        Creates a long-lived, read-only SAS URL for the CippLogs Azure Storage table.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APIName -message 'Generating CippLogs readonly SAS token' -Sev Info

    try {
        $conn = @{}
        foreach ($part in ($env:AzureWebJobsStorage -split ';')) {
            $p = $part.Trim()
            if ($p -match '^(.+?)=(.+)$') { $conn[$matches[1]] = $matches[2] }
        }

        $Days = [int]($Request.Body.Days ?? $Request.Query.Days ?? 365)
        if ($Days -lt 1 -or $Days -gt 3650) {
            throw 'Days must be between 1 and 3650'
        }

        $Sas = New-CIPPAzServiceSAS `
            -AccountName $conn['AccountName'] `
            -AccountKey $conn['AccountKey'] `
            -Service 'table' `
            -ResourcePath 'CippLogs' `
            -Permissions 'r' `
            -ExpiryTime ([DateTime]::UtcNow.AddDays($Days))

        $SASTable = Get-CIPPTable -TableName 'CippSASTokens'
        $Entity = @{
            PartitionKey = 'SAS'
            RowKey       = 'CippLogs'
            Permissions  = 'r'
            ExpiryTime   = $Sas.ExpiryTime
        }
        Add-CIPPAzDataTableEntity @SASTable -Entity $Entity -Force

        $Body = @{
            Results = @{
                SASUrl    = $Sas.ResourceUri + $Sas.Token + '&$format=application/json;odata=nometadata'
                ExpiresOn = $Sas.Query['se']
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to generate CippLogs readonly SAS token: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Body = @{ Results = "Failed to generate readonly SAS token: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
