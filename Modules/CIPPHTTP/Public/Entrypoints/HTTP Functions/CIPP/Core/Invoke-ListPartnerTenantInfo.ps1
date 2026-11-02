function Invoke-ListPartnerTenantInfo {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Reports whether the CIPP host tenant is a Microsoft Partner tenant, so the frontend can
        decide whether partner-only flows (GDAP onboarding, reseller invites, GDAP permission
        checks) apply to this instance.

        Marked AnyTenant deliberately. This answers a question about the CIPP instance, not
        about a tenant the caller wants to act on, and Get-CippPartnerTenantInfo pins the lookup
        to $env:TenantID. Without the flag, Test-CIPPAccess falls back to $env:TenantID as the
        tenant filter and denies any custom role that blocks the partner tenant, which silently
        greys out partner-only UI for roles that are otherwise fully permitted.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $StatusCode = [HttpStatusCode]::OK
        $Body = Get-CippPartnerTenantInfo
    } catch {
        Write-LogMessage -API 'ListPartnerTenantInfo' -message "Failed to retrieve partner tenant info: $($_.Exception.Message)" -LogData (Get-CippException -Exception $_) -sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{
            error   = $_.Exception.Message
            details = $_.Exception
        }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }
}
