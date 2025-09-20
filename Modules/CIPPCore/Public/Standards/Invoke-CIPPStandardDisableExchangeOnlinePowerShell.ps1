function Invoke-CIPPStandardDisableExchangeOnlinePowerShell {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableExchangeOnlinePowerShell
    .SYNOPSIS
        (Label) Disable Exchange Online PowerShell for non-admin users
    .DESCRIPTION
        (Helptext) Disables the ability for non-admin users to use Exchange Online PowerShell. Only administrators will be able to use PowerShell to connect to Exchange Online.
        (DocsDescription) Disables the ability for non-admin users to use Exchange Online PowerShell. This helps prevent attackers from using PowerShell to run malicious commands, access file systems, registry, and distribute ransomware throughout networks. Only administrators will be able to use PowerShell to connect to Exchange Online, aligning with a least privileged access approach to security.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS"
            "PowerShell"
            "Security"
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-06-19
        POWERSHELLEQUIVALENT
            Get-User -ResultSize Unlimited -Filter 'RemotePowerShellEnabled -eq $true' | ForEach-Object { Set-User -Identity $_.Identity -RemotePowerShellEnabled $false }
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DisableExchangeOnlinePowerShell' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableExchangeOnlinePowerShell'

    try {

        $AdminUsers = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?$expand=principal' -tenantid $Tenant).principal.userPrincipalName
        $UsersWithPowerShell = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-User' -Select 'userPrincipalName, identity, guid, remotePowerShellEnabled' | Where-Object { $_.RemotePowerShellEnabled -eq $true -and $_.userPrincipalName -notin $AdminUsers }
        $PowerShellEnabledCount = ($UsersWithPowerShell | Measure-Object).Count
        $StateIsCorrect = $PowerShellEnabledCount -eq 0
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not check Exchange Online PowerShell status. $($ErrorMessage.NormalizedError)" -sev Error
        $StateIsCorrect = $null
    }

    if ($Settings.remediate -eq $true) {
        if ($PowerShellEnabledCount -gt 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Started disabling Exchange Online PowerShell for $PowerShellEnabledCount users." -sev Info

            $Request = $UsersWithPowerShell | ForEach-Object {
                @{
                    CmdletInput = @{
                        CmdletName = 'Set-User'
                        Parameters = @{Identity = $_.Guid; RemotePowerShellEnabled = $false }
                    }
                }
            }

            $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request)
            $SuccessCount = 0
            $BatchResults | ForEach-Object {
                if ($_.error) {
                    $ErrorMessage = Get-NormalizedError -Message $_.error
                    Write-Host "Failed to disable Exchange Online PowerShell for $($_.target). Error: $ErrorMessage"
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to disable Exchange Online PowerShell for $($_.target). Error: $ErrorMessage" -sev Error
                } else {
                    $SuccessCount++
                }
            }

            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully disabled Exchange Online PowerShell for $SuccessCount out of $PowerShellEnabledCount users." -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Exchange Online PowerShell is already disabled for all non-admin users' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Exchange Online PowerShell is disabled for all non-admin users.' -sev Info
        } else {
            Write-StandardsAlert -message "Exchange Online PowerShell is enabled for $PowerShellEnabledCount users" -object @{UsersWithPowerShellEnabled = $PowerShellEnabledCount } -tenant $tenant -standardName 'DisableExchangeOnlinePowerShell' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Exchange Online PowerShell is enabled for $PowerShellEnabledCount users." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $state = $StateIsCorrect ?? @{UsersWithPowerShellEnabled = $PowerShellEnabledCount }
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableExchangeOnlinePowerShell' -FieldValue $state -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'ExchangeOnlinePowerShellDisabled' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
