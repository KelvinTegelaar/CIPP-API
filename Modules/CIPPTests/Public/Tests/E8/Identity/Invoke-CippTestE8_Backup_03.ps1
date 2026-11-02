function Invoke-CippTestE8_Backup_03 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Regular Backups, ML1) - OneDrive Known Folder Move (KFM) is configured
    #>
    param($Tenant)
    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_Backup_03' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm OneDrive Known Folder Move is configured to redirect Desktop, Documents, and Pictures to OneDrive on all Windows endpoints. Configure via Intune Settings catalog: *OneDrive > Silently move Windows known folders to OneDrive*.' -Risk 'Medium' -Name 'OneDrive Known Folder Move (KFM) is enforced' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Regular Backups'
}
