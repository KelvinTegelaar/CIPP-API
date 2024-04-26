using namespace System.Net

Function Invoke-ListServiceHealth {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    if ($Request.query.tenantFilter -eq 'AllTenants') {
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
        $TenantName = $Request.query.displayName
        $TenantID = $Request.query.tenantFilter
        $DefaultDomainName = $Request.query.defaultDomainName
        $ResultHealthSummary = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/admin/serviceAnnouncement/issues?`$filter=endDateTime eq null" -tenantid $TenantID
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
