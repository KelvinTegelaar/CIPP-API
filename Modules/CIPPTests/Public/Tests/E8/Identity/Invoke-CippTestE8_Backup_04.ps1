function Invoke-CippTestE8_Backup_04 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Regular Backups, ML2) - A tested backup and restore process exists for Microsoft 365 data
    #>
    param($Tenant)
    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_Backup_04' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm a third-party (or Microsoft 365 Backup) solution is in place for mailboxes, OneDrive, SharePoint, and Teams data, and that restore tests are performed at least quarterly with documented results. Microsoft retention is **not** a backup — it does not protect against admin deletion or compliance policy changes.' -Risk 'High' -Name 'Microsoft 365 data is backed up by a tested process (ISM-1547)' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'E8 ML2 - Regular Backups'
}
