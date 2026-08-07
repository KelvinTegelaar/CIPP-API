function Invoke-CIPPBaselineCATemplate {
    <#
    .SYNOPSIS
        CATemplate executor: deploys the referenced Conditional Access template to one tenant.
    .DESCRIPTION
        Looks the template up in the template store by GUID (the %caTemplate% variable
        carries the picker's GUID; RowKey first, then the GUID column, then displayName for
        legacy configs) and deploys it through the existing New-CIPPCAPolicy machinery:
        displayName replacement (users/groups/locations resolved per tenant), the
        configured state ('donotchange' keeps the existing policy's state), optional
        Security Defaults disable and optional group creation. The spec arrives fully
        rendered.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter
    )

    $TemplateRef = "$($Remediate.caTemplate)"
    $Table = Get-CippTable -tablename 'templates'
    $SafeRef = ConvertTo-CIPPODataFilterValue -Value $TemplateRef
    $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CATemplate' and RowKey eq '$SafeRef'" | Select-Object -First 1
    if (-not $Template) {
        $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CATemplate'" | Where-Object {
            $_.GUID -eq $TemplateRef -or $(try { ($_.JSON | ConvertFrom-Json).displayName } catch { $null }) -eq $TemplateRef
        } | Select-Object -First 1
    }
    if (-not $Template) { throw "Conditional Access template '$TemplateRef' was not found in the template store." }

    $State = if ("$($Remediate.state)" -in @('', 'donotchange')) { 'donotchange' } else { "$($Remediate.state)" }
    $null = New-CIPPCAPolicy -RawJSON $Template.JSON -TenantFilter $TenantFilter -State $State -Overwrite $true -ReplacePattern 'displayName' -DisableSD ([bool]($Remediate.disableSD -eq $true)) -CreateGroups ([bool]($Remediate.createGroups -eq $true)) -APIName 'Baselines'
}
