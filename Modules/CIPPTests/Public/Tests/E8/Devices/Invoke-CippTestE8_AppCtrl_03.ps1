function Invoke-CippTestE8_AppCtrl_03 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Application Control, ML2) - Microsoft recommended block list is implemented
    #>
    param($Tenant)
    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_AppCtrl_03' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm Microsoft''s **recommended block rules** (LOLBins such as bash, bginfo, cdb, msbuild, powershell_ise.exe, etc.) are deployed via WDAC. The block list is published as XML at `https://aka.ms/wdac-block-rules` and is delivered through an Intune WDAC policy XML file.' -Risk 'High' -Name 'Microsoft recommended WDAC block rules are deployed' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML2 - Application Control'
}
