function Invoke-CippTestE8_Backup_02 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Regular Backups, ML1) - SharePoint Online retains versions and recycle bin items
    #>
    param($Tenant)
    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_Backup_02' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm SharePoint Online sites have versioning enabled (default minimum 100 versions) and the second-stage recycle bin retention is at least 93 days. Site-level versioning is configured per library and is not exposed centrally; review via SharePoint admin centre or PnP PowerShell.' -Risk 'Medium' -Name 'SharePoint Online versioning and recycle bin retention is configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Regular Backups'
}
