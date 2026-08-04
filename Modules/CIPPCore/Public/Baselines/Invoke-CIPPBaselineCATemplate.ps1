function Invoke-CIPPBaselineCATemplate {
    <#
    .SYNOPSIS
        CATemplate executor: deploys the named Conditional Access template to one tenant.
    .DESCRIPTION
        Looks the template up in the template store (by GUID, or by displayName since the
        %caTemplate% variable usually carries the name) and deploys it through the existing
        New-CIPPCAPolicy machinery with the configured state. The spec arrives fully rendered.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter
    )

    $TemplateName = $Remediate.caTemplate
    $Table = Get-CippTable -tablename 'templates'
    $SafeName = ConvertTo-CIPPODataFilterValue -Value $TemplateName
    $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CATemplate' and RowKey eq '$SafeName'" | Select-Object -First 1
    if (-not $Template) {
        $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CATemplate'" | Where-Object {
            $(try { ($_.JSON | ConvertFrom-Json).displayName } catch { $null }) -eq $TemplateName
        } | Select-Object -First 1
    }
    if (-not $Template) { throw "Conditional Access template '$TemplateName' was not found in the template store." }
    $null = New-CIPPCAPolicy -RawJSON $Template.JSON -TenantFilter $TenantFilter -State $Remediate.state -Overwrite $true -ReplacePattern 'displayName' -APIName 'Baselines'
}
