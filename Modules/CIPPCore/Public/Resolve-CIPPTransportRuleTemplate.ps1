function Resolve-CIPPTransportRuleTemplate {
    <#
    .SYNOPSIS
        Returns a copy of a transport rule template with %variables% resolved for a tenant.
    .DESCRIPTION
        Every string property, and every string inside an array property, goes through
        Get-CIPPTextReplacement. Other values pass through; nested objects are walked.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Template, $TenantFilter)

    if ($Template -is [string]) { return (Get-CIPPTextReplacement -Text $Template -TenantFilter $TenantFilter) }
    if ($Template -is [System.Management.Automation.PSCustomObject]) {
        $Copy = [ordered]@{}
        foreach ($Property in $Template.PSObject.Properties) {
            $Copy[$Property.Name] = Resolve-CIPPTransportRuleTemplate -Template $Property.Value -TenantFilter $TenantFilter
        }
        return [PSCustomObject]$Copy
    }
    if ($Template -is [array]) {
        $Items = [System.Collections.Generic.List[object]]::new()
        foreach ($Item in $Template) { $Items.Add((Resolve-CIPPTransportRuleTemplate -Template $Item -TenantFilter $TenantFilter)) }
        return , $Items.ToArray()
    }
    return $Template
}
