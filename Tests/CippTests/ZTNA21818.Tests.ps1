BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $RepoRoot 'Modules/CIPPTests/Public/Tests/ZTNA/Identity/Invoke-CippTestZTNA21818.ps1')

    $script:RuleIds = @(
        'Notification_Admin_Admin_Eligibility', 'Notification_Requestor_Admin_Eligibility', 'Notification_Approver_Admin_Eligibility'
        'Notification_Admin_Admin_Assignment', 'Notification_Requestor_Admin_Assignment', 'Notification_Approver_Admin_Assignment'
        'Notification_Admin_EndUser_Assignment', 'Notification_Requestor_EndUser_Assignment', 'Notification_Approver_EndUser_Assignment'
    )
    function New-Rule($Id, $Default = $true, $Recipients = @()) { [pscustomobject]@{ id = $Id; isDefaultRecipientsEnabled = $Default; notificationRecipients = $Recipients } }
    function Get-CippDbRole { param($TenantFilter, [switch]$IncludePrivilegedRoles) @([pscustomobject]@{ roleTemplateId = 'ga'; displayName = 'Global Administrator' }) }
    function Get-CIPPTestData { param($TenantFilter, $Type) @([pscustomobject]@{ scopeId = '/'; scopeType = 'DirectoryRole'; roleDefinitionId = 'ga'; rules = $script:Rules }) }
    function Add-CippTestResult { param($TenantFilter, $TestId, $TestType, $Status, $ResultMarkdown, $Risk, $Name, $UserImpact, $ImplementationEffort, $Category) $script:Result = @{ Status = $Status; Markdown = "$ResultMarkdown" } }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) $true }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
}

Describe 'ZTNA21818 PIM notification recipients' {
    It 'passes on the Microsoft default (default recipients on, no extra recipients)' {
        $script:Rules = foreach ($Id in $script:RuleIds) { New-Rule $Id }
        Invoke-CippTestZTNA21818 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
    }

    It 'passes when default recipients are off but an extra recipient is set' {
        $script:Rules = foreach ($Id in $script:RuleIds) { New-Rule $Id $false @('soc@contoso.com') }
        Invoke-CippTestZTNA21818 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
    }

    It 'fails when a rule notifies nobody' {
        $script:Rules = foreach ($Id in $script:RuleIds) { if ($Id -eq 'Notification_Admin_EndUser_Assignment') { New-Rule $Id $false } else { New-Rule $Id } }
        Invoke-CippTestZTNA21818 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
        $script:Result.Markdown | Should -Match 'Role activation alert'
    }

    It 'returns Investigate when a notification rule is missing from the cache' {
        $script:Rules = foreach ($Id in $script:RuleIds) { if ($Id -ne 'Notification_Approver_EndUser_Assignment') { New-Rule $Id } }
        Invoke-CippTestZTNA21818 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Investigate'
        $script:Result.Markdown | Should -Match 'Global Administrator: Notification_Approver_EndUser_Assignment'
    }
}
