function Invoke-ListAgent365Packages {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    .DESCRIPTION
        Lists Microsoft Agent 365 / Copilot packages (agents and Microsoft 365 apps) in the tenant
        catalog via the Package Management API. Requires a Microsoft Agent 365 license on the tenant.
        Uses delegated auth: the Package Management API currently fails under application context
        (424 Failed Dependency on GET, partial on LIST). Agents are NOT returned by the default list,
        so this also queries supportedHosts=Copilot and merges the results (deduped by id). An explicit
        OData $filter (Filter query parameter) overrides the default merge.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $Filter = $Request.Query.Filter ?? $Request.Body.Filter

    $BaseUri = 'https://graph.microsoft.com/beta/copilot/admin/catalog/packages'
    if (-not [string]::IsNullOrWhiteSpace($Filter)) {
        $Uris = @("$BaseUri`?`$filter=$Filter")
    } else {
        # The default catalog list omits agents, so also pull agents (supportedHosts=Copilot) and merge.
        $Uris = @(
            $BaseUri
            "$BaseUri`?`$filter=supportedHosts/any(x:x eq 'Copilot')"
        )
    }

    $Packages = [System.Collections.Generic.List[object]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($Uri in $Uris) {
        try {
            $Result = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter
            foreach ($Package in $Result) {
                if ($Package.id -and $Seen.Add([string]$Package.id)) {
                    $Packages.Add($Package)
                }
            }
            $StatusCode = [HttpStatusCode]::OK
            $Results = @($Packages)
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Results = $ErrorMessage.Message
            $statusCode = [HttpStatusCode]::InternalServerError
            Write-LogMessage -API 'Agent365Packages' -tenant $TenantFilter -message "Could not list Agent 365 packages (a Microsoft Agent 365 license is required). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = $statusCode
            Body       = $Results
        })
}
