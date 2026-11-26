function Invoke-CippTestCyberIns_20 {
    <#
    .SYNOPSIS
    Cyber Insurance Q20 - Backup credentials are separate from admin accounts
    #>
    param($Tenant)

    $Meta = @{ TenantFilter = $Tenant; TestId = 'CyberIns_20'; TestType = 'Identity'; Risk = 'High'; Name = 'Backup credentials are separate from admin accounts'; UserImpact = 'Low'; ImplementationEffort = 'Medium'; Category = 'Cyber Insurance' }

    try {
        $Apps = Get-CIPPTestData -TenantFilter $Tenant -Type 'ServicePrincipals'
        if (-not $Apps) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No enterprise application data found for this tenant. Sync the report data first.'
            return
        }

        $BackupApps = @{}
        foreach ($App in $Apps) {
            if ($App.accountEnabled -eq $true -and $App.displayName -match 'backup|veeam|dropsuite|cove data|datto|acronis|axcient|druva|keepit|skykick|afi\.ai') {
                $BackupApps[[string]$App.id] = @{ Name = [string]$App.displayName; Users = 0; Admins = [System.Collections.Generic.List[string]]::new() }
            }
        }

        $Intro = "A backup portal is only visible here when it signs in through Entra ID. This question needs an MSP attestation confirming backup credentials are separate from production and admin accounts.`n`n"
        if ($BackupApps.Count -eq 0) {
            Add-CippTestResult @Meta -Status 'Informational' -ResultMarkdown ($Intro + 'No enterprise app with a backup product name was found in this tenant.')
            return
        }

        $AdminIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Role in (Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles')) {
            foreach ($Member in $Role.members) { if ($Member.id) { $null = $AdminIds.Add([string]$Member.id) } }
        }

        foreach ($Assignment in (Get-CIPPTestData -TenantFilter $Tenant -Type 'AppRoleAssignments')) {
            $App = $BackupApps[[string]$Assignment.resourceId]
            if (-not $App -or $Assignment.principalType -ne 'User') { continue }
            $App.Users++
            if ($AdminIds.Contains([string]$Assignment.principalId)) { $App.Admins.Add([string]$Assignment.principalDisplayName) }
        }

        $Result = [System.Text.StringBuilder]::new($Intro)
        $null = $Result.Append("Enterprise apps that look like backup products, matched on name:`n`n| App | Users assigned | Of whom hold a directory role |`n| :-- | :-- | :-- |`n")
        $AdminsAssigned = 0
        foreach ($App in $BackupApps.Values) {
            $AdminsAssigned = $AdminsAssigned + $App.Admins.Count
            $AdminList = if ($App.Admins.Count -gt 0) { "$($App.Admins.Count): $($App.Admins -join ', ')" } else { '0' }
            $null = $Result.Append("| $($App.Name -replace '\|', '\|') | $($App.Users) | $($AdminList -replace '\|', '\|') |`n")
        }

        $Status = if ($AdminsAssigned -gt 0) { 'Investigate' } else { 'Informational' }
        Add-CippTestResult @Meta -Status $Status -ResultMarkdown $Result.ToString()
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CyberIns_20: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Meta -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
