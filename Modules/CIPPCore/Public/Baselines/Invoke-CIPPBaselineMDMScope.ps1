function Invoke-CIPPBaselineMDMScope {
    <#
    .SYNOPSIS
        MDMScope executor: writes the Intune MDM enrollment URLs and user scope.
    .DESCRIPTION
        The classic's write, quirks included: everything goes DELEGATED with the
        Accept-Language 0 header this endpoint demands; the URLs and appliesTo must PATCH
        in SEPARATE requests (Graph rejects simultaneous patches of both); and 'selected'
        scope assigns the custom group via an includedGroups $ref rather than an appliesTo
        write.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $AppliesTo = "$($Remediate.appliesTo)"
    if ($AppliesTo -notin @('all', 'none', 'selected')) { return }
    $Uri = 'https://graph.microsoft.com/beta/policies/mobileDeviceManagementPolicies/0000000a-0000-0000-c000-000000000000'
    $Headers = @{ 'Accept-Language' = 0 }

    $UrlBody = @{
        termsOfUseUrl = 'https://portal.manage.microsoft.com/TermsofUse.aspx'
        discoveryUrl  = 'https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc'
        complianceUrl = 'https://portal.manage.microsoft.com/?portalAction=Compliance'
    } | ConvertTo-Json
    $null = New-GraphPostRequest -tenantid $TenantFilter -uri $Uri -type PATCH -body $UrlBody -asApp $false -AddedHeaders $Headers -ContentType 'application/json; charset=utf-8'

    if ($AppliesTo -ne 'selected') {
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri $Uri -type PATCH -body (@{ appliesTo = $AppliesTo } | ConvertTo-Json) -asApp $false -AddedHeaders $Headers -ContentType 'application/json; charset=utf-8'
    } else {
        $CustomGroup = "$($Remediate.customGroup)"
        $EscapedGroup = $CustomGroup -replace "'", "''"
        $GroupId = "$((New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$top=999&`$select=id,displayName&`$filter=displayName eq '$EscapedGroup'" -tenantid $TenantFilter -asApp $true).id | Select-Object -First 1)"
        if ([string]::IsNullOrWhiteSpace($GroupId)) { throw "Could not resolve the custom MDM scope group '$CustomGroup'." }
        $RefBody = @{ '@odata.id' = "https://graph.microsoft.com/odata/groups('$GroupId')" } | ConvertTo-Json
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri "$Uri/includedGroups/`$ref" -type POST -body $RefBody -asApp $false -AddedHeaders $Headers -ContentType 'application/json; charset=utf-8'
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Set the MDM enrollment scope to $AppliesTo." -Sev 'Info'
}
