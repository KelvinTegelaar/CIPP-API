function Invoke-CIPPStandardSetMailboxTimeZone {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SetMailboxTimeZone
    .SYNOPSIS
        (Label) Set mailbox time zone and working hours time zone
    .DESCRIPTION
        (Helptext) Sets the regional time zone and the calendar working-hours time zone for all user, shared, room and equipment mailboxes. Exchange Online creates every mailbox on Pacific Standard Time regardless of tenant region; user mailboxes usually self-correct on first sign-in, but shared, room and equipment mailboxes never do, and any mailbox whose first sign-in ran under a different locale stays wrong. Time zones use Windows time zone key names, for example "E. Australia Standard Time". Applies to Outlook on the web and new Outlook; classic Outlook for Windows reads the working-hours position from the mailbox as well.
        (DocsDescription) Loops through all UserMailbox, SharedMailbox, RoomMailbox and EquipmentMailbox recipients and sets both the regional time zone using \`Set-MailboxRegionalConfiguration -TimeZone\` and the calendar working-hours time zone using \`Set-MailboxCalendarConfiguration -WorkingHoursTimeZone\`. These are two separate properties: setting the regional time zone alone does not move the calendar working-hours block, which is the setting users see as "my calendar says I work the wrong hours". Both are read back and only the property that differs is written, so steady-state runs make no writes. New mailboxes in Exchange Online default to Pacific Standard Time by design, and shared, room and equipment mailboxes never auto-correct because no user signs into them. Use the value in Windows time zone key name format (for example \`E. Australia Standard Time\` for Brisbane, \`AUS Eastern Standard Time\` for Sydney/Melbourne). Because remediation rewrites every mailbox to the configured zone, tenants whose users genuinely span multiple time zones should run this in alert mode rather than remediate. See [Set-MailboxRegionalConfiguration](https://learn.microsoft.com/powershell/module/exchangepowershell/set-mailboxregionalconfiguration) and [Set-MailboxCalendarConfiguration](https://learn.microsoft.com/powershell/module/exchangepowershell/set-mailboxcalendarconfiguration).
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Ensures everyone's mailbox and calendar use the organisation's correct time zone instead of the US default that Microsoft applies to new mailboxes. This removes a common source of missed or mis-scheduled meetings and "my working hours look wrong" tickets, and is especially important for shared and room mailboxes, which never fix themselves.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":true,"required":true,"name":"standards.SetMailboxTimeZone.TimeZone","label":"Time zone (Windows time zone key name)","helperText":"Windows time zone key name applied to both the regional and working-hours time zone. You can type any valid value that is not in this list.","options":[{"label":"E. Australia Standard Time (Brisbane)","value":"E. Australia Standard Time"},{"label":"AUS Eastern Standard Time (Sydney, Melbourne)","value":"AUS Eastern Standard Time"},{"label":"Cen. Australia Standard Time (Adelaide)","value":"Cen. Australia Standard Time"},{"label":"AUS Central Standard Time (Darwin)","value":"AUS Central Standard Time"},{"label":"W. Australia Standard Time (Perth)","value":"W. Australia Standard Time"},{"label":"Tasmania Standard Time (Hobart)","value":"Tasmania Standard Time"},{"label":"New Zealand Standard Time","value":"New Zealand Standard Time"},{"label":"GMT Standard Time (London)","value":"GMT Standard Time"},{"label":"W. Europe Standard Time","value":"W. Europe Standard Time"},{"label":"Central Europe Standard Time","value":"Central Europe Standard Time"},{"label":"Eastern Standard Time (US)","value":"Eastern Standard Time"},{"label":"Central Standard Time (US)","value":"Central Standard Time"},{"label":"Mountain Standard Time (US)","value":"Mountain Standard Time"},{"label":"Pacific Standard Time (US)","value":"Pacific Standard Time"},{"label":"Singapore Standard Time","value":"Singapore Standard Time"},{"label":"China Standard Time","value":"China Standard Time"},{"label":"India Standard Time","value":"India Standard Time"},{"label":"UTC","value":"UTC"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-09-23
        POWERSHELLEQUIVALENT
            Set-MailboxRegionalConfiguration -TimeZone and Set-MailboxCalendarConfiguration -WorkingHoursTimeZone
        RECOMMENDEDBY
        REQUIREDCAPABILITIES
            "EXCHANGE_S_STANDARD"
            "EXCHANGE_S_ENTERPRISE"
            "EXCHANGE_S_STANDARD_GOV"
            "EXCHANGE_S_ENTERPRISE_GOV"
            "EXCHANGE_LITE"
        UPDATECOMMENTBLOCK
            Run the tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'SetMailboxTimeZone' -TenantFilter $Tenant -Preset Exchange #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    $TimeZone = $Settings.TimeZone.value ?? $Settings.TimeZone

    # Input validation. Exchange rejects an unknown zone per mailbox, so a bad value would otherwise
    # spray identical errors across every mailbox; fail once up front instead.
    if ([string]::IsNullOrWhiteSpace($TimeZone) -or $TimeZone -eq 'Select a value') {
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SetMailboxTimeZone: No time zone parameter set' -Sev Error
        return
    }

    $RecipientTypes = @('UserMailbox', 'SharedMailbox', 'RoomMailbox', 'EquipmentMailbox')

    # Cached mailbox objects expose UPN, recipientTypeDetails and WhenSoftDeleted, see Set-CIPPDBCacheMailboxes.ps1
    try {
        $Mailboxes = @(New-CippDbRequest -TenantFilter $Tenant -Type 'Mailboxes' |
                Where-Object { $_.UPN -and -not $_.WhenSoftDeleted -and $_.recipientTypeDetails -in $RecipientTypes } |
                Select-Object -Property @{ Name = 'UserPrincipalName'; Expression = { $_.UPN } })

        if ($Mailboxes.Count -eq 0) {
            # An empty cache would otherwise report as compliant without inspecting anything, so fall back to a live read
            Write-Information "SetMailboxTimeZone: mailbox cache empty for $Tenant, falling back to Get-Mailbox"
            $Filter = ($RecipientTypes | ForEach-Object { "RecipientTypeDetails -eq '$_'" }) -join ' -or '
            $Mailboxes = @(New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{
                    ResultSize = 'Unlimited'
                    Filter     = $Filter
                } -Select 'UserPrincipalName,RecipientTypeDetails' |
                    Where-Object { $_.UserPrincipalName -and $_.UserPrincipalName -notlike 'DiscoverySearchMailbox*' -and $_.UserPrincipalName -notlike 'SystemMailbox*' })
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the mailbox list for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    # Neither Get-MailboxRegionalConfiguration nor Get-MailboxCalendarConfiguration has a server-side
    # filter, so this is one sub-request per mailbox per cmdlet. OperationGuid maps each response back
    # to its UPN because the Identity Exchange returns is a canonical name, not the UPN.
    $Evaluated = [System.Collections.Generic.List[PSObject]]::new()
    $ReadFailures = [System.Collections.Generic.List[PSObject]]::new()

    if ($Mailboxes.Count -gt 0) {
        $RegionalByUpn = @{}
        $WorkingHoursByUpn = @{}
        $RegionalReadFailures = @{}
        $CalendarReadFailures = @{}

        # --- Regional time zone read ---
        $RegionalGuidToUpn = @{}
        $RegionalRequests = @(foreach ($Mailbox in $Mailboxes) {
                $OperationGuid = [Guid]::NewGuid().ToString()
                $RegionalGuidToUpn[$OperationGuid] = $Mailbox.UserPrincipalName
                @{
                    CmdletInput   = @{
                        CmdletName = 'Get-MailboxRegionalConfiguration'
                        Parameters = @{ Identity = $Mailbox.UserPrincipalName }
                    }
                    OperationGuid = $OperationGuid
                }
            })

        # --- Working-hours time zone read ---
        $CalendarGuidToUpn = @{}
        $CalendarRequests = @(foreach ($Mailbox in $Mailboxes) {
                $OperationGuid = [Guid]::NewGuid().ToString()
                $CalendarGuidToUpn[$OperationGuid] = $Mailbox.UserPrincipalName
                @{
                    CmdletInput   = @{
                        CmdletName = 'Get-MailboxCalendarConfiguration'
                        Parameters = @{ Identity = $Mailbox.UserPrincipalName }
                    }
                    OperationGuid = $OperationGuid
                }
            })

        try {
            $RegionalResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray $RegionalRequests -Select 'Identity,TimeZone'
            $CalendarResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray $CalendarRequests -Select 'Identity,WorkingHoursTimeZone'
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not read the mailbox time zone configuration for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            return
        }

        foreach ($Config in @($RegionalResults)) {
            $UPN = if ($Config.OperationGuid -and $RegionalGuidToUpn.ContainsKey($Config.OperationGuid)) { $RegionalGuidToUpn[$Config.OperationGuid] } else { $Config.Identity }
            if ($Config.error) { $RegionalReadFailures[$UPN] = (Get-NormalizedError -Message $Config.error); continue }
            $RegionalByUpn[$UPN] = $Config.TimeZone
        }
        foreach ($Config in @($CalendarResults)) {
            $UPN = if ($Config.OperationGuid -and $CalendarGuidToUpn.ContainsKey($Config.OperationGuid)) { $CalendarGuidToUpn[$Config.OperationGuid] } else { $Config.Identity }
            if ($Config.error) { $CalendarReadFailures[$UPN] = (Get-NormalizedError -Message $Config.error); continue }
            $WorkingHoursByUpn[$UPN] = $Config.WorkingHoursTimeZone
        }

        foreach ($Mailbox in $Mailboxes) {
            $UPN = $Mailbox.UserPrincipalName
            # A mailbox we could not read either config for is unknown, not compliant; surface it as a read failure.
            if (-not $RegionalByUpn.ContainsKey($UPN) -or -not $WorkingHoursByUpn.ContainsKey($UPN)) {
                $Reason = @($RegionalReadFailures[$UPN], $CalendarReadFailures[$UPN] | Where-Object { $_ }) -join '; '
                if ([string]::IsNullOrWhiteSpace($Reason)) { $Reason = 'Response did not contain the time zone properties' }
                $ReadFailures.Add([PSCustomObject]@{ UPN = $UPN; Error = $Reason })
                continue
            }
            $Evaluated.Add([PSCustomObject]@{
                    UPN                  = $UPN
                    TimeZone             = $RegionalByUpn[$UPN]
                    WorkingHoursTimeZone = $WorkingHoursByUpn[$UPN]
                })
        }

        if ($ReadFailures.Count -gt 0) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "SetMailboxTimeZone: could not read the time zone configuration for $($ReadFailures.Count) of $($Mailboxes.Count) mailboxes." -Sev Warning -LogData @($ReadFailures)
        }
    }

    $RegionalDrift = @($Evaluated | Where-Object { $_.TimeZone -ne $TimeZone })
    $CalendarDrift = @($Evaluated | Where-Object { $_.WorkingHoursTimeZone -ne $TimeZone })
    $NonCompliant = @($Evaluated | Where-Object { $_.TimeZone -ne $TimeZone -or $_.WorkingHoursTimeZone -ne $TimeZone })

    # An empty mailbox list or all-failed reads is unknown, not compliant
    $StateIsCorrect = $Evaluated.Count -gt 0 -and $NonCompliant.Count -eq 0 -and $ReadFailures.Count -eq 0

    if ($Settings.remediate -eq $true) {
        if ($Evaluated.Count -eq 0) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SetMailboxTimeZone: No mailbox configuration could be read, so nothing was remediated.' -Sev Warning
        } elseif ($NonCompliant.Count -eq 0) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Mailbox time zone is already $TimeZone for all $($Evaluated.Count) mailboxes." -Sev Info
        } else {
            try {
                # Only write the property that actually differs, so a mailbox with a correct regional
                # zone but wrong working-hours zone gets a single targeted write.
                $GuidToUpn = @{}
                $Request = @(
                    foreach ($Mailbox in $RegionalDrift) {
                        $OperationGuid = [Guid]::NewGuid().ToString()
                        $GuidToUpn[$OperationGuid] = $Mailbox.UPN
                        @{
                            CmdletInput   = @{
                                CmdletName = 'Set-MailboxRegionalConfiguration'
                                Parameters = @{ Identity = $Mailbox.UPN; TimeZone = $TimeZone }
                            }
                            OperationGuid = $OperationGuid
                        }
                    }
                    foreach ($Mailbox in $CalendarDrift) {
                        $OperationGuid = [Guid]::NewGuid().ToString()
                        $GuidToUpn[$OperationGuid] = $Mailbox.UPN
                        @{
                            CmdletInput   = @{
                                CmdletName = 'Set-MailboxCalendarConfiguration'
                                Parameters = @{ Identity = $Mailbox.UPN; WorkingHoursTimeZone = $TimeZone }
                            }
                            OperationGuid = $OperationGuid
                        }
                    }
                )

                $BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray $Request
                $Failures = [System.Collections.Generic.List[PSObject]]::new()
                foreach ($Result in @($BatchResults)) {
                    if ($Result.error) {
                        # Target is often empty on adminapi errors, so prefer the GUID map.
                        $FailedUPN = if ($Result.OperationGuid -and $GuidToUpn.ContainsKey($Result.OperationGuid)) { $GuidToUpn[$Result.OperationGuid] } else { $Result.target }
                        $Failures.Add([PSCustomObject]@{ UPN = $FailedUPN; Error = (Get-NormalizedError -Message $Result.error) })
                    }
                }

                if ($Failures.Count -gt 0) {
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set the mailbox time zone for $($Failures.Count) mailboxes." -Sev Error -LogData @($Failures)
                }
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Set mailbox time zone to $TimeZone for $($NonCompliant.Count) mailboxes ($($RegionalDrift.Count) regional, $($CalendarDrift.Count) working-hours writes, $($Failures.Count) failed)." -Sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set the mailbox time zone. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Mailbox time zone is set to $TimeZone for all mailboxes." -Sev Info
        } elseif ($Evaluated.Count -eq 0) {
            Write-StandardsAlert -message 'Mailbox time zone could not be evaluated: no mailbox configuration was returned' -object @($ReadFailures) -tenant $Tenant -standardName 'SetMailboxTimeZone' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Mailbox time zone could not be evaluated: no mailbox configuration was returned.' -Sev Warning
        } else {
            $AlertMessage = if ($ReadFailures.Count -gt 0) {
                "Mailbox time zone is not set to $TimeZone for $($NonCompliant.Count) mailboxes, and $($ReadFailures.Count) mailboxes could not be read"
            } else {
                "Mailbox time zone is not set to $TimeZone for $($NonCompliant.Count) mailboxes"
            }
            Write-StandardsAlert -message $AlertMessage -object @($NonCompliant) -tenant $Tenant -standardName 'SetMailboxTimeZone' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "$AlertMessage." -Sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $ExpectedValue = [ordered]@{
            TimeZone             = $TimeZone
            WorkingHoursTimeZone = $TimeZone
        }
        # Cap the non-compliant list: entries render as pretty-printed JSON in the alignment card,
        # so a large drifted tenant would otherwise write a huge report row on every run.
        $MaxListed = 50

        $CurrentValue = if ($Evaluated.Count -eq 0) {
            [ordered]@{ state = 'No mailbox configuration could be read' }
        } elseif ($StateIsCorrect -eq $true) {
            $ExpectedValue
        } else {
            $Report = [ordered]@{
                NonCompliantMailboxes = @($NonCompliant | Select-Object -First $MaxListed | ForEach-Object {
                        $Entry = [ordered]@{ Mailbox = $_.UPN }
                        if ($_.TimeZone -ne $TimeZone) {
                            $Entry['TimeZone'] = if ([string]::IsNullOrWhiteSpace($_.TimeZone)) { 'not set' } else { $_.TimeZone }
                        }
                        if ($_.WorkingHoursTimeZone -ne $TimeZone) {
                            $Entry['WorkingHoursTimeZone'] = if ([string]::IsNullOrWhiteSpace($_.WorkingHoursTimeZone)) { 'not set' } else { $_.WorkingHoursTimeZone }
                        }
                        $Entry
                    })
            }
            if ($NonCompliant.Count -gt $MaxListed) {
                $Report['Truncated'] = "$($NonCompliant.Count - $MaxListed) more non-compliant mailboxes not shown"
            }
            if ($ReadFailures.Count -gt 0) {
                $Label = if ($ReadFailures.Count -eq 1) { 'mailbox' } else { 'mailboxes' }
                $Report['Unreadable'] = "$($ReadFailures.Count) $Label could not be read"
            }
            $Report
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.SetMailboxTimeZone' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
    }
}
