function Get-CIPPBaselineGlobalSecureAccessProfileTemplateState {
    <#
    .SYNOPSIS
        Prepare hook for GlobalSecureAccessProfileTemplate: does the tenant match this security profile template?
    .DESCRIPTION
        Compares the instance's security profile template, and the filtering policy templates it
        links, with the NetworkAccessFiltering cache through the same compare a deploy uses. Every
        finding that is not a match is listed in differences, so a conflict a deploy would refuse
        shows here too. The templates are carried on Current for the executor. An unknown template
        is a configuration error, never compliant.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $Reference = "$($Item.Variables.profileTemplate.value ?? $Item.Variables.profileTemplate)"
    $Table = Get-CippTable -tablename 'templates'
    $Row = if ($Reference) { Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GSASecurityProfileTemplate' and RowKey eq '$(ConvertTo-CIPPODataFilterValue -Value $Reference -Type String)'" | Select-Object -First 1 }
    if (-not $Row) {
        return @{ Current = $null; ConfigError = $true; NoDataReason = "the security profile template '$($Item.Variables.profileTemplate.label ?? $Reference)' was not found in the template store" }
    }
    $ProfileTemplate = $Row.JSON | ConvertFrom-Json -Depth 20
    $PolicyTemplates = @{}
    foreach ($PolicyRow in @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GSAFilteringPolicyTemplate'")) { $PolicyTemplates[$PolicyRow.RowKey] = $PolicyRow.JSON | ConvertFrom-Json -Depth 20 }

    $TenantRows = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'NetworkAccessFiltering').Where({ $_ })
    $Findings = @(Compare-CIPPGSAFilteringProfile -ProfileTemplate $ProfileTemplate -PolicyTemplates $PolicyTemplates -TenantRows $TenantRows)
    $Labels = @{ profile = 'security profile'; policy = 'filtering policy'; category = 'web category'; link = 'link' }
    $Differences = @($Findings.Where({ $_.state -ne 'match' }).ForEach({ "$($Labels[$_.object]) '$($_.name)': $($_.detail)" }) | Sort-Object)

    $Current = [pscustomobject]@{ differences = $Differences }
    $Current | Add-Member -NotePropertyName 'templateBody' -NotePropertyValue $ProfileTemplate
    $Current | Add-Member -NotePropertyName 'policyTemplates' -NotePropertyValue $PolicyTemplates
    @{ Expected = [pscustomobject]@{ differences = @() }; Current = $Current }
}
