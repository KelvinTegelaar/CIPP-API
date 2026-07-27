function Invoke-CIPPStandardTeamsDisableResourceAccounts {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsDisableResourceAccounts
    .SYNOPSIS
        (Label) Block sign-in for Teams resource accounts
    .DESCRIPTION
        (Helptext) Blocks sign-in for all Teams resource accounts used by Auto Attendants and Call Queues. Microsoft's guidance is to block sign-in for resource accounts as they do not require an interactive login to function.
        (DocsDescription) Teams resource accounts (the accounts backing Auto Attendants and Call Queues) do not require interactive sign-in to function. If sign-in is enabled and the password is reset, the account can be logged into directly, which presents a security risk. Microsoft's guidance is to block sign-in for these accounts. Accounts that are synced from on-premises AD are excluded, as account state is managed in the on-premises AD.
    .NOTES
        CAT
            Teams Standards
        TAG
            "NIST CSF 2.0 (PR.AA-01)"
        EXECUTIVETEXT
            Prevents direct login to the service accounts that power phone system features like Auto Attendants and Call Queues. These accounts work without anyone signing into them, so blocking sign-in removes an unnecessary attack surface while keeping the phone system fully functional.
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-07-17
        POWERSHELLEQUIVALENT
            Get-CsOnlineApplicationInstance & Update-MgUser
        RECOMMENDEDBY
            "Microsoft"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsDisableResourceAccounts' -TenantFilter $Tenant -Preset Teams
    if ($TestResult -eq $false) {
        return $true
    }

    try {
        # Teams.PlatformService returns the Auto Attendant / Call Queue resource accounts along
        # with the applicationId that distinguishes the two. Graph's admin/teams/userConfigurations
        # does not surface resource accounts at all, so this surface is the only source.
        $ResourceAccounts = [System.Collections.Generic.List[object]]::new()
        $SkipToken = $null
        do {
            $QueryParameters = @{ pageSize = 100 }
            if ($SkipToken) { $QueryParameters['skipToken'] = $SkipToken }
            $Page = New-TeamsRequestV2 -TenantFilter $Tenant -Path 'Teams.PlatformService/v2/ApplicationInstances' -QueryParameters $QueryParameters
            foreach ($Instance in @($Page.applicationInstances)) { $ResourceAccounts.Add($Instance) }
            $SkipToken = $Page.skipToken
        } while ($SkipToken)

        # Cross-reference the cached user objects for sign-in state; cloud-only accounts only,
        # as the account state of synced accounts is managed in the on-premises AD.
        $AllUsers = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users'
        $EnabledUserIds = ($AllUsers | Where-Object {
                $_.accountEnabled -eq $true -and
                $_.onPremisesSyncEnabled -ne $true
            }).id

        $ApplicationTypes = @{
            'ce933385-9390-45d1-9512-c8d228074e07' = 'Auto Attendant'
            '11cd3e2e-fccb-42ad-ad00-878b93575e07' = 'Call Queue'
        }

        $EnabledResourceAccounts = foreach ($Account in $ResourceAccounts) {
            if ($Account.objectId -and $EnabledUserIds -contains $Account.objectId) {
                [PSCustomObject]@{
                    DisplayName       = $Account.displayName
                    UserPrincipalName = $Account.userPrincipalName
                    ObjectId          = $Account.objectId
                    ApplicationType   = $ApplicationTypes[[string]$Account.applicationId] ?? 'Custom'
                }
            }
        }
        $EnabledResourceAccounts = @($EnabledResourceAccounts)
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the TeamsDisableResourceAccounts state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($EnabledResourceAccounts.Count -gt 0) {
            $UpdateDB = $false
            $int = 0
            $BulkRequests = foreach ($Account in $EnabledResourceAccounts) {
                @{
                    id        = $int++
                    method    = 'PATCH'
                    url       = "users/$($Account.ObjectId)"
                    body      = @{ accountEnabled = $false }
                    'headers' = @{
                        'Content-Type' = 'application/json'
                    }
                }
            }

            try {
                $BulkResults = New-GraphBulkRequest -tenantid $Tenant -Requests @($BulkRequests)

                for ($i = 0; $i -lt $BulkResults.Count; $i++) {
                    $Result = $BulkResults[$i]
                    $Account = $EnabledResourceAccounts[$i]

                    if ($Result.status -eq 200 -or $Result.status -eq 204) {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Blocked sign-in for Teams resource account $($Account.DisplayName) ($($Account.UserPrincipalName))." -sev Info
                        $UpdateDB = $true
                    } else {
                        $ErrorMsg = if ($Result.body.error.message) { $Result.body.error.message } else { "Unknown error (Status: $($Result.status))" }
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to block sign-in for Teams resource account $($Account.DisplayName) ($($Account.UserPrincipalName)): $ErrorMsg" -sev Error
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to process bulk sign-in block for Teams resource accounts: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }

            # Refresh user cache after remediation only if changes were made
            if ($UpdateDB) {
                try {
                    Set-CIPPDBCacheUsers -TenantFilter $Tenant
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to refresh user cache after remediation: $($_.Exception.Message)" -sev Warning
                }
            }
        } elseif ($ResourceAccounts.Count -eq 0) {
            # Distinct from "all blocked": Teams classifies an account as a resource account based
            # on licensing, so an account carrying user licences (or none) drops out of this list
            # entirely. Saying "already blocked" there would be a false pass.
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No Teams resource accounts were returned for this tenant, so there was nothing to evaluate. If Auto Attendants or Call Queues exist, check that their resource accounts hold the Microsoft Teams Phone Resource Account license.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Sign-in is already blocked for all Teams resource accounts.' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($EnabledResourceAccounts.Count -gt 0) {
            Write-StandardsAlert -message "Teams resource accounts with sign-in enabled: $($EnabledResourceAccounts.Count)" -object $EnabledResourceAccounts -tenant $Tenant -standardName 'TeamsDisableResourceAccounts' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Teams resource accounts with sign-in enabled: $($EnabledResourceAccounts.Count)" -sev Info
        } elseif ($ResourceAccounts.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No Teams resource accounts were returned for this tenant, so there was nothing to evaluate.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Sign-in is blocked for all Teams resource accounts.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            TeamsDisableResourceAccounts = @($EnabledResourceAccounts)
        }
        $ExpectedValue = [PSCustomObject]@{
            TeamsDisableResourceAccounts = @()
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsDisableResourceAccounts' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'TeamsDisableResourceAccounts' -FieldValue $EnabledResourceAccounts -StoreAs json -Tenant $Tenant
    }
}
