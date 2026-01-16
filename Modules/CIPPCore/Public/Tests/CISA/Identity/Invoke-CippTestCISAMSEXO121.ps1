function Invoke-CippTestCISAMSEXO121 {
    <#
    .SYNOPSIS
    Tests MS.EXO.12.1 - Allowed senders list SHOULD NOT be used

    .DESCRIPTION
    Checks if tenant allow/block list has allowed senders configured

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    try {
        $AllowBlockList = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoTenantAllowBlockList'

        if ($null -eq $AllowBlockList) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoTenantAllowBlockList cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Allowed sender lists SHOULD NOT be used' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO121' -TenantFilter $Tenant
            return
        }

        $AllowedSenders = $AllowBlockList | Where-Object { $_.Action -eq 'Allow' -and $_.ListType -eq 'Sender' }

        if ($AllowedSenders.Count -eq 0) {
            $Result = '✅ **Pass**: No allowed senders configured in tenant allow/block list.'
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: $($AllowedSenders.Count) allowed sender(s) configured in tenant allow/block list"
            if ($AllowedSenders.Count -gt 10) {
                $Result += ' (showing first 10)'
            }
            $Result += ":`n`n"
            $Result += "| Value | Action | List Type |`n"
            $Result += "| :---- | :----- | :-------- |`n"
            foreach ($Sender in ($AllowedSenders | Select-Object -First 10)) {
                $Result += "| $($Sender.Value) | $($Sender.Action) | $($Sender.ListType) |`n"
            }
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO121' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Allowed sender lists SHOULD NOT be used' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Allowed sender lists SHOULD NOT be used' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO121' -TenantFilter $Tenant
    }
}
