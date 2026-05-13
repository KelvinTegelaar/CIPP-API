Function Invoke-RemoveRetentionCompliancePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.RetentionCompliancePolicy.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $Identity = $Request.Query.Identity ?? $Request.Body.Identity ?? $Request.Body.Name
    $ForceRemoval = $Request.Body.ForceDeletion -eq $true

    try {
        $Params = @{
            Identity = $Identity
        }
        if ($ForceRemoval) { $Params['ForceDeletion'] = $true }

        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-RetentionCompliancePolicy' -cmdParams $Params -Compliance -AsApp -useSystemMailbox $true
        $Result = "Deleted Retention compliance policy $Identity"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete Retention compliance policy $Identity - $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
