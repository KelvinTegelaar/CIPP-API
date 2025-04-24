using namespace System.Net

Function Invoke-ListServiceHealth {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    if ($TenantFilter -eq 'AllTenants') {
        $ResultHealthSummary = Get-Tenants | ForEach-Object -Parallel {
            Import-Module '.\Modules\AzBobbyTables'
            Import-Module '.\Modules\CIPPCore'
            $TenantName = $_.displayName
            Write-Host "Processed Service Health for $TenantName via AllTenants"
            $prop = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/admin/serviceAnnouncement/issues?`$filter=endDateTime eq null" -tenantid $_.defaultDomainName
            $prop | Add-Member -NotePropertyName 'tenant' -NotePropertyValue $TenantName
            $prop | Add-Member -NotePropertyName 'defaultDomainName' -NotePropertyValue $_.defaultDomainName
            $prop
        }
    } else {
        $TenantName = $Request.Query.displayName
        $DefaultDomainName = $Request.Query.defaultDomainName
        $ResultHealthSummary = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/admin/serviceAnnouncement/issues?`$filter=endDateTime eq null" -tenantid $TenantFilter
        $ResultHealthSummary | Add-Member -NotePropertyName 'tenant' -NotePropertyValue $TenantName
        $ResultHealthSummary | Add-Member -NotePropertyName 'defaultDomainName' -NotePropertyValue $DefaultDomainName
        Write-Host "Processed Service Health for $TenantName"
    }
    $Results = foreach ($h in $ResultHealthSummary) {
        [PSCustomObject]@{
            TenantName        = $h.tenant
            DefaultDomainName = $h.defaultDomainName
            issueId           = $h.ID
            service           = $h.service
            type              = $h.feature
            desc              = $h.impactDescription
        }
    }

    $StatusCode = [HttpStatusCode]::OK

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })

}
