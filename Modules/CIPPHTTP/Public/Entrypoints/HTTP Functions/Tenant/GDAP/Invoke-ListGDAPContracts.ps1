function Invoke-ListGDAPContracts {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.Read
    .DESCRIPTION
        Lists Microsoft partner contracts (customer tenant relationships) from the Graph API.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Top = [int]($Request.Query.'$top' ?? 300)
    $Uri = "https://graph.microsoft.com/beta/contracts?`$top=$Top"

    try {
        # Enumerate as every configured partner, tagging results with their source partner
        $Partners = @(Get-CIPPPartnerTenantList)
        $Results = foreach ($Partner in $Partners) {
            try {
                $PartnerResults = New-GraphGetRequest -Uri $Uri -tenantid $Partner.partnerTenantId -NoAuthCheck $true -ComplexFilter
                foreach ($Result in $PartnerResults) {
                    $Result | Add-Member -MemberType NoteProperty -Name 'partnerTenantId' -Value $Partner.partnerTenantId -Force
                    $Result | Add-Member -MemberType NoteProperty -Name 'partnerDisplayName' -Value $Partner.displayName -Force -PassThru
                }
            } catch {
                if ($Partners.Count -eq 1) { throw }
                Write-LogMessage -API $APIName -headers $Request.Headers -message "Failed to list contracts for partner $($Partner.partnerTenantId): $($_.Exception.Message)" -sev Warning
            }
        }

        $Body = @{
            Results  = @($Results)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $env:TenantID -headers $Request.Headers -message "Failed to list GDAP contracts: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $Body = @{ Results = @(); Error = $ErrorMessage.NormalizedError }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
