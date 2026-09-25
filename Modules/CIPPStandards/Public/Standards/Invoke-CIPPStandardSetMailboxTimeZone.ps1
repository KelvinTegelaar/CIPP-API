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
        (DocsDescription) Loops through all UserMailbox, SharedMailbox, RoomMailbox and EquipmentMailbox recipients and sets both the regional time zone using \`Set-MailboxRegionalConfiguration -TimeZone\` and the calendar working-hours time zone using \`Set-MailboxCalendarConfiguration -WorkingHoursTimeZone\`. These are two separate properties: setting the regional time zone alone does not move the calendar working-hours block, which is the setting users see as "my calendar says I work the wrong hours". Both are read back and only the property that differs is written, so steady-state runs make no writes. New mailboxes in Exchange Online default to Pacific Standard Time by design, and shared, room and equipment mailboxes never auto-correct because no user signs into them. Use the value in Windows time zone key name format (for example \`E. Australia Standard Time\` for Brisbane, \`AUS Eastern Standard Time\` for Sydney/Melbourne). Because remediation rewrites every mailbox to the configured zone, tenants whose users genuinely span multiple time zones should run this in alert mode rather than remediate. Two exclusion options narrow the scope: **Exclude these users** takes a list of UPNs (for example permanent overseas staff) that are never touched, and **Skip mailboxes whose user is currently in Vacation Mode** drops any user who is a live member of a CIPP "Vacation Exclusion - ..." security group, so a traveller who deliberately set a local time zone is not reset while they are away. Excluded mailboxes are removed from evaluation entirely, so they are never reported, alerted, or remediated. See [Set-MailboxRegionalConfiguration](https://learn.microsoft.com/powershell/module/exchangepowershell/set-mailboxregionalconfiguration) and [Set-MailboxCalendarConfiguration](https://learn.microsoft.com/powershell/module/exchangepowershell/set-mailboxcalendarconfiguration).
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Ensures everyone's mailbox and calendar use the organisation's correct time zone instead of the US default that Microsoft applies to new mailboxes. This removes a common source of missed or mis-scheduled meetings and "my working hours look wrong" tickets, and is especially important for shared and room mailboxes, which never fix themselves.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":true,"required":true,"name":"standards.SetMailboxTimeZone.TimeZone","label":"Time zone (Windows time zone key name)","helperText":"Windows time zone key name applied to both the regional and working-hours time zone. All Windows time zones are listed; you can also type any other valid value.","options":[{"label":"(UTC-12:00) International Date Line West","value":"Dateline Standard Time"},{"label":"(UTC-11:00) Co-ordinated Universal Time-11","value":"UTC-11"},{"label":"(UTC-10:00) Aleutian Islands","value":"Aleutian Standard Time"},{"label":"(UTC-10:00) Hawaii","value":"Hawaiian Standard Time"},{"label":"(UTC-09:30) Marquesas Islands","value":"Marquesas Standard Time"},{"label":"(UTC-09:00) Alaska","value":"Alaskan Standard Time"},{"label":"(UTC-09:00) Co-ordinated Universal Time-09","value":"UTC-09"},{"label":"(UTC-08:00) Baja California","value":"Pacific Standard Time (Mexico)"},{"label":"(UTC-08:00) Co-ordinated Universal Time-08","value":"UTC-08"},{"label":"(UTC-08:00) Pacific Time (US & Canada)","value":"Pacific Standard Time"},{"label":"(UTC-07:00) Arizona","value":"US Mountain Standard Time"},{"label":"(UTC-07:00) La Paz, Mazatlan","value":"Mountain Standard Time (Mexico)"},{"label":"(UTC-07:00) Mountain Time (US & Canada)","value":"Mountain Standard Time"},{"label":"(UTC-07:00) Yukon","value":"Yukon Standard Time"},{"label":"(UTC-06:00) Central America","value":"Central America Standard Time"},{"label":"(UTC-06:00) Central Time (US & Canada)","value":"Central Standard Time"},{"label":"(UTC-06:00) Easter Island","value":"Easter Island Standard Time"},{"label":"(UTC-06:00) Guadalajara, Mexico City, Monterrey","value":"Central Standard Time (Mexico)"},{"label":"(UTC-06:00) Saskatchewan","value":"Canada Central Standard Time"},{"label":"(UTC-05:00) Bogota, Lima, Quito, Rio Branco","value":"SA Pacific Standard Time"},{"label":"(UTC-05:00) Chetumal","value":"Eastern Standard Time (Mexico)"},{"label":"(UTC-05:00) Eastern Time (US & Canada)","value":"Eastern Standard Time"},{"label":"(UTC-05:00) Haiti","value":"Haiti Standard Time"},{"label":"(UTC-05:00) Havana","value":"Cuba Standard Time"},{"label":"(UTC-05:00) Indiana (East)","value":"US Eastern Standard Time"},{"label":"(UTC-05:00) Turks and Caicos","value":"Turks And Caicos Standard Time"},{"label":"(UTC-04:00) Atlantic Time (Canada)","value":"Atlantic Standard Time"},{"label":"(UTC-04:00) Caracas","value":"Venezuela Standard Time"},{"label":"(UTC-04:00) Cuiaba","value":"Central Brazilian Standard Time"},{"label":"(UTC-04:00) Georgetown, La Paz, Manaus, San Juan","value":"SA Western Standard Time"},{"label":"(UTC-04:00) Santiago","value":"Pacific SA Standard Time"},{"label":"(UTC-03:30) Newfoundland","value":"Newfoundland Standard Time"},{"label":"(UTC-03:00) Araguaina","value":"Tocantins Standard Time"},{"label":"(UTC-03:00) Asuncion","value":"Paraguay Standard Time"},{"label":"(UTC-03:00) Brasilia","value":"E. South America Standard Time"},{"label":"(UTC-03:00) Cayenne, Fortaleza","value":"SA Eastern Standard Time"},{"label":"(UTC-03:00) City of Buenos Aires","value":"Argentina Standard Time"},{"label":"(UTC-03:00) Montevideo","value":"Montevideo Standard Time"},{"label":"(UTC-03:00) Punta Arenas","value":"Magallanes Standard Time"},{"label":"(UTC-03:00) Saint Pierre and Miquelon","value":"Saint Pierre Standard Time"},{"label":"(UTC-03:00) Salvador","value":"Bahia Standard Time"},{"label":"(UTC-02:00) Co-ordinated Universal Time-02","value":"UTC-02"},{"label":"(UTC-02:00) Mid-Atlantic - Old","value":"Mid-Atlantic Standard Time"},{"label":"(UTC-03:00) Greenland","value":"Greenland Standard Time"},{"label":"(UTC-01:00) Azores","value":"Azores Standard Time"},{"label":"(UTC-01:00) Cabo Verde Is.","value":"Cape Verde Standard Time"},{"label":"(UTC) Coordinated Universal Time","value":"UTC"},{"label":"(UTC+00:00) Dublin, Edinburgh, Lisbon, London","value":"GMT Standard Time"},{"label":"(UTC+00:00) Monrovia, Reykjavik","value":"Greenwich Standard Time"},{"label":"(UTC+00:00) Sao Tome","value":"Sao Tome Standard Time"},{"label":"(UTC+01:00) Casablanca","value":"Morocco Standard Time"},{"label":"(UTC+01:00) Amsterdam, Berlin, Bern, Rome, Stockholm, Vienna","value":"W. Europe Standard Time"},{"label":"(UTC+01:00) Belgrade, Bratislava, Budapest, Ljubljana, Prague","value":"Central Europe Standard Time"},{"label":"(UTC+01:00) Brussels, Copenhagen, Madrid, Paris","value":"Romance Standard Time"},{"label":"(UTC+01:00) Sarajevo, Skopje, Warsaw, Zagreb","value":"Central European Standard Time"},{"label":"(UTC+01:00) West Central Africa","value":"W. Central Africa Standard Time"},{"label":"(UTC+02:00) Athens, Bucharest","value":"GTB Standard Time"},{"label":"(UTC+02:00) Beirut","value":"Middle East Standard Time"},{"label":"(UTC+02:00) Cairo","value":"Egypt Standard Time"},{"label":"(UTC+02:00) Chisinau","value":"E. Europe Standard Time"},{"label":"(UTC+02:00) Gaza, Hebron","value":"West Bank Standard Time"},{"label":"(UTC+02:00) Harare, Pretoria","value":"South Africa Standard Time"},{"label":"(UTC+02:00) Helsinki, Kyiv, Riga, Sofia, Tallinn, Vilnius","value":"FLE Standard Time"},{"label":"(UTC+02:00) Jerusalem","value":"Israel Standard Time"},{"label":"(UTC+02:00) Juba","value":"South Sudan Standard Time"},{"label":"(UTC+02:00) Kaliningrad","value":"Kaliningrad Standard Time"},{"label":"(UTC+02:00) Khartoum","value":"Sudan Standard Time"},{"label":"(UTC+02:00) Tripoli","value":"Libya Standard Time"},{"label":"(UTC+02:00) Windhoek","value":"Namibia Standard Time"},{"label":"(UTC+02:00) Damascus","value":"Syria Standard Time"},{"label":"(UTC+03:00) Amman","value":"Jordan Standard Time"},{"label":"(UTC+03:00) Baghdad","value":"Arabic Standard Time"},{"label":"(UTC+03:00) Istanbul","value":"Turkey Standard Time"},{"label":"(UTC+03:00) Kuwait, Riyadh","value":"Arab Standard Time"},{"label":"(UTC+03:00) Minsk","value":"Belarus Standard Time"},{"label":"(UTC+03:00) Moscow, St Petersburg","value":"Russian Standard Time"},{"label":"(UTC+03:00) Nairobi","value":"E. Africa Standard Time"},{"label":"(UTC+03:00) Volgograd","value":"Volgograd Standard Time"},{"label":"(UTC+03:30) Tehran","value":"Iran Standard Time"},{"label":"(UTC+04:00) Abu Dhabi, Muscat","value":"Arabian Standard Time"},{"label":"(UTC+04:00) Astrakhan, Ulyanovsk","value":"Astrakhan Standard Time"},{"label":"(UTC+04:00) Baku","value":"Azerbaijan Standard Time"},{"label":"(UTC+04:00) Izhevsk, Samara","value":"Russia Time Zone 3"},{"label":"(UTC+04:00) Port Louis","value":"Mauritius Standard Time"},{"label":"(UTC+04:00) Saratov","value":"Saratov Standard Time"},{"label":"(UTC+04:00) Tbilisi","value":"Georgian Standard Time"},{"label":"(UTC+04:00) Yerevan","value":"Caucasus Standard Time"},{"label":"(UTC+04:30) Kabul","value":"Afghanistan Standard Time"},{"label":"(UTC+05:00) Ashgabat, Tashkent","value":"West Asia Standard Time"},{"label":"(UTC+05:00) Astana","value":"Qyzylorda Standard Time"},{"label":"(UTC+05:00) Ekaterinburg","value":"Ekaterinburg Standard Time"},{"label":"(UTC+05:00) Islamabad, Karachi","value":"Pakistan Standard Time"},{"label":"(UTC+05:30) Chennai, Kolkata, Mumbai, New Delhi","value":"India Standard Time"},{"label":"(UTC+05:30) Sri Jayawardenepura","value":"Sri Lanka Standard Time"},{"label":"(UTC+05:45) Kathmandu","value":"Nepal Standard Time"},{"label":"(UTC+06:00) Bishkek","value":"Central Asia Standard Time"},{"label":"(UTC+06:00) Dhaka","value":"Bangladesh Standard Time"},{"label":"(UTC+06:00) Omsk","value":"Omsk Standard Time"},{"label":"(UTC+06:30) Yangon (Rangoon)","value":"Myanmar Standard Time"},{"label":"(UTC+07:00) Bangkok, Hanoi, Jakarta","value":"SE Asia Standard Time"},{"label":"(UTC+07:00) Barnaul, Gorno-Altaysk","value":"Altai Standard Time"},{"label":"(UTC+07:00) Hovd","value":"W. Mongolia Standard Time"},{"label":"(UTC+07:00) Krasnoyarsk","value":"North Asia Standard Time"},{"label":"(UTC+07:00) Novosibirsk","value":"N. Central Asia Standard Time"},{"label":"(UTC+07:00) Tomsk","value":"Tomsk Standard Time"},{"label":"(UTC+08:00) Beijing, Chongqing, Hong Kong SAR, Urumqi","value":"China Standard Time"},{"label":"(UTC+08:00) Irkutsk","value":"North Asia East Standard Time"},{"label":"(UTC+08:00) Kuala Lumpur, Singapore","value":"Singapore Standard Time"},{"label":"(UTC+08:00) Perth","value":"W. Australia Standard Time"},{"label":"(UTC+08:00) Taipei","value":"Taipei Standard Time"},{"label":"(UTC+08:00) Ulaanbaatar","value":"Ulaanbaatar Standard Time"},{"label":"(UTC+08:45) Eucla","value":"Aus Central W. Standard Time"},{"label":"(UTC+09:00) Chita","value":"Transbaikal Standard Time"},{"label":"(UTC+09:00) Osaka, Sapporo, Tokyo","value":"Tokyo Standard Time"},{"label":"(UTC+09:00) Pyongyang","value":"North Korea Standard Time"},{"label":"(UTC+09:00) Seoul","value":"Korea Standard Time"},{"label":"(UTC+09:00) Yakutsk","value":"Yakutsk Standard Time"},{"label":"(UTC+09:30) Adelaide","value":"Cen. Australia Standard Time"},{"label":"(UTC+09:30) Darwin","value":"AUS Central Standard Time"},{"label":"(UTC+10:00) Brisbane","value":"E. Australia Standard Time"},{"label":"(UTC+10:00) Canberra, Melbourne, Sydney","value":"AUS Eastern Standard Time"},{"label":"(UTC+10:00) Guam, Port Moresby","value":"West Pacific Standard Time"},{"label":"(UTC+10:00) Hobart","value":"Tasmania Standard Time"},{"label":"(UTC+10:00) Vladivostok","value":"Vladivostok Standard Time"},{"label":"(UTC+10:30) Lord Howe Island","value":"Lord Howe Standard Time"},{"label":"(UTC+11:00) Bougainville Island","value":"Bougainville Standard Time"},{"label":"(UTC+11:00) Chokurdakh","value":"Russia Time Zone 10"},{"label":"(UTC+11:00) Magadan","value":"Magadan Standard Time"},{"label":"(UTC+11:00) Norfolk Island","value":"Norfolk Standard Time"},{"label":"(UTC+11:00) Sakhalin","value":"Sakhalin Standard Time"},{"label":"(UTC+11:00) Solomon Is., New Caledonia","value":"Central Pacific Standard Time"},{"label":"(UTC+12:00) Anadyr, Petropavlovsk-Kamchatsky","value":"Russia Time Zone 11"},{"label":"(UTC+12:00) Auckland, Wellington","value":"New Zealand Standard Time"},{"label":"(UTC+12:00) Co-ordinated Universal Time+12","value":"UTC+12"},{"label":"(UTC+12:00) Fiji","value":"Fiji Standard Time"},{"label":"(UTC+12:00) Petropavlovsk-Kamchatsky - Old","value":"Kamchatka Standard Time"},{"label":"(UTC+12:45) Chatham Islands","value":"Chatham Islands Standard Time"},{"label":"(UTC+13:00) Co-ordinated Universal Time+13","value":"UTC+13"},{"label":"(UTC+13:00) Nuku'alofa","value":"Tonga Standard Time"},{"label":"(UTC+13:00) Samoa","value":"Samoa Standard Time"},{"label":"(UTC+14:00) Kiritimati Island","value":"Line Islands Standard Time"}]}
            {"type":"switch","name":"standards.SetMailboxTimeZone.ExcludeVacationMode","label":"Skip mailboxes whose user is currently in Vacation Mode","defaultValue":false}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"name":"standards.SetMailboxTimeZone.ExcludedUsers","label":"Exclude these users (user principal names)","helperText":"UPNs of users whose mailbox time zone must never be changed, for example permanent overseas staff. Press enter after each address. These mailboxes are dropped from evaluation entirely, so they are never reported, alerted, or remediated."}
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

    # Both settings are optional; absent (the standard configured before the frontend exposed them)
    # simply means no exclusions. A switch arrives as a plain boolean, a creatable multi-select as
    # a { value = @(...) } wrapper, matching every other standard's read pattern.
    $ExcludeVacationMode = $Settings.ExcludeVacationMode -eq $true
    $ExcludedUsers = @(($Settings.ExcludedUsers.value ?? $Settings.ExcludedUsers) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

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

    # --- Exclusions -------------------------------------------------------------------------------
    # Two independent, UPN-keyed (case-insensitive) exclusion sources, both dropping a mailbox from
    # evaluation entirely so it is never reported, alerted, or remediated:
    #   1. ExcludedUsers      - explicit UPNs the admin never wants touched (e.g. permanent overseas
    #                           staff whose local time zone is correct for them).
    #   2. ExcludeVacationMode - users inside a live CIPP vacation window. CIPP vacation mode adds the
    #                           user to a security group named "Vacation Exclusion - <policy>" for the
    #                           duration (see Invoke-ExecCAExclusion), so membership of any such group
    #                           marks a traveller who may have deliberately set a local time zone.
    $ExcludedUpns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Excluded in $ExcludedUsers) { [void]$ExcludedUpns.Add($Excluded.Trim()) }
    $ExcludedMailboxCount = 0

    if ($ExcludeVacationMode) {
        try {
            # $count=true forces advanced-query semantics so startswith on displayName is reliable;
            # -ComplexFilter supplies the ConsistencyLevel: eventual header that pairing requires.
            $VacationFilter = [System.Uri]::EscapeDataString("startswith(displayName,'Vacation Exclusion - ')")
            $VacationGroups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups?`$filter=$VacationFilter&`$select=id,displayName&`$count=true" -tenantid $Tenant -ComplexFilter | Where-Object { $_.id })

            if ($VacationGroups.Count -gt 0) {
                # Transitive members, cast to users, so a nested group in a vacation exclusion still resolves.
                $MemberRequests = foreach ($Group in $VacationGroups) {
                    @{ id = $Group.id; method = 'GET'; url = "groups/$($Group.id)/transitiveMembers/microsoft.graph.user?`$select=userPrincipalName&`$top=999" }
                }
                $MemberResponses = @(New-GraphBulkRequest -tenantid $Tenant -Requests @($MemberRequests) -asapp $true -Version 'v1.0')
                foreach ($Response in $MemberResponses) {
                    if ([int]$Response.status -lt 200 -or [int]$Response.status -gt 299) {
                        throw "membership lookup for vacation group $($Response.id) returned $($Response.status) $($Response.body.error.message)"
                    }
                    foreach ($Upn in @($Response.body.value.userPrincipalName | Where-Object { $_ })) { [void]$ExcludedUpns.Add($Upn) }
                }
            }
        } catch {
            # A partial or failed vacation lookup means we cannot tell who is away, and resetting a
            # vacationing user's time zone is exactly what this option exists to prevent. Refuse to run
            # rather than risk it - mirrors PlannerBlockTaskDelete's partial-scope guard.
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "SetMailboxTimeZone: could not determine vacation-mode membership for $Tenant, skipping this run to avoid resetting an away user's time zone. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            return
        }
    }

    if ($ExcludedUpns.Count -gt 0 -and $Mailboxes.Count -gt 0) {
        $ExcludedMailboxCount = @($Mailboxes | Where-Object { $ExcludedUpns.Contains($_.UserPrincipalName) }).Count
        if ($ExcludedMailboxCount -gt 0) {
            $Mailboxes = @($Mailboxes | Where-Object { -not $ExcludedUpns.Contains($_.UserPrincipalName) })
            Write-Information "SetMailboxTimeZone: excluded $ExcludedMailboxCount mailbox(es) from evaluation for $Tenant (explicit exclusions and/or active vacation mode)."
        }
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
            if ($ExcludedMailboxCount -gt 0) {
                $Label = if ($ExcludedMailboxCount -eq 1) { 'mailbox' } else { 'mailboxes' }
                $Report['Excluded'] = "$ExcludedMailboxCount $Label excluded (explicit exclusions and/or active vacation mode)"
            }
            $Report
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.SetMailboxTimeZone' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
    }
}
