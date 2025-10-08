Function Invoke-RemoveQuarantinePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Spamfilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Query.TenantFilter ?? $Request.Body.TenantFilter
    $PolicyName = $Request.Query.Name ?? $Request.Body.Name
    $Identity = $Request.Query.Identity ?? $Request.Body.Identity

    try {
        $Params = @{
            Identity = ($Identity -eq "00000000-0000-0000-0000-000000000000" ? $PolicyName : $Identity)
        }

        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-QuarantinePolicy' -cmdParams $Params -useSystemMailbox $true

        $Result = "Deleted Quarantine policy '$($PolicyName)'"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove Quarantine policy '$($PolicyName)' - $($ErrorMessage.NormalizedError -replace '\|Microsoft.Exchange.Management.Tasks.ValidationException\|', '')"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    $StatusCode = [HttpStatusCode]::OK

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
