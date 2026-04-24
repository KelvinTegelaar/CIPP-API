function Invoke-ListGDAPContracts {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Top = [int]($Request.Query.'$top' ?? 300)
    $Uri = "https://graph.microsoft.com/beta/contracts?`$top=$Top"

    try {
        $Results = New-GraphGetRequest -Uri $Uri -tenantid $env:TenantID -NoAuthCheck $true -NoPagination $true -ComplexFilter

        $Body = @{
            Results  = @($Results)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $env:TenantID -headers $Request.Headers -message "Failed to list GDAP contracts: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $Body = @{ Results = @(); Error = $ErrorMessage.NormalizedError }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
