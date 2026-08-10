function Invoke-CIPPStandardSetDefaultMailboxFont {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SetDefaultMailboxFont
    .SYNOPSIS
        (Label) Set default mailbox font, size and colour
    .DESCRIPTION
        (Helptext) Sets the default compose font name, size and colour for all user and shared mailboxes. Font size is the 1-7 scale Exchange stores, not a point size. Applies to Outlook on the web and new Outlook only - classic Outlook for Windows/Mac uses its own local font settings and is not affected.
        (DocsDescription) Loops through all UserMailbox and SharedMailbox recipients and sets the Outlook on the web default compose font using \`Set-MailboxMessageConfiguration\`. Mailboxes already matching the configured font are skipped, so steady-state runs make no writes. Font size is the integer 1-7 scale Exchange stores rather than a point size: 3 is the Exchange default and corresponds to 12pt. Note that these settings apply to Outlook on the web and the new Outlook client only; classic Outlook for Windows and Mac read their compose font from local client settings. See [Microsoft's documentation.](https://learn.microsoft.com/powershell/module/exchangepowershell/set-mailboxmessageconfiguration)
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Applies a consistent default font, size and colour to outgoing email so that messages from across the organisation look uniform and on-brand. This affects the web and new Outlook clients; users can still change the font on an individual message.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":true,"required":true,"name":"standards.SetDefaultMailboxFont.DefaultFontName","label":"Default font name","helperText":"Font applied to new messages. You can type a font that is not in this list.","options":[{"label":"Aptos","value":"Aptos"},{"label":"Arial","value":"Arial"},{"label":"Calibri","value":"Calibri"},{"label":"Cambria","value":"Cambria"},{"label":"Georgia","value":"Georgia"},{"label":"Helvetica","value":"Helvetica"},{"label":"Segoe UI","value":"Segoe UI"},{"label":"Tahoma","value":"Tahoma"},{"label":"Times New Roman","value":"Times New Roman"},{"label":"Trebuchet MS","value":"Trebuchet MS"},{"label":"Verdana","value":"Verdana"}]}
            {"type":"number","required":true,"name":"standards.SetDefaultMailboxFont.DefaultFontSize","label":"Default font size (1-7)","defaultValue":3,"helperText":"Exchange stores a 1-7 size scale, not a point size. 3 is the Exchange default and corresponds to 12pt; lower is smaller, higher is larger.","validators":{"min":{"value":1,"message":"Minimum value is 1"},"max":{"value":7,"message":"Maximum value is 7"}}}
            {"type":"textField","required":true,"name":"standards.SetDefaultMailboxFont.DefaultFontColor","label":"Default font colour","placeholder":"#000000","helperText":"Six-digit hex colour in the #xxxxxx format, for example #000000. Exchange stores six digits, so shorthand such as #000 is not accepted."}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-08-04
        POWERSHELLEQUIVALENT
            Set-MailboxMessageConfiguration -DefaultFontName -DefaultFontSize -DefaultFontColor
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
    $TestResult = Test-CIPPStandardLicense -StandardName 'SetDefaultMailboxFont' -TenantFilter $Tenant -Preset Exchange #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    $FontName = $Settings.DefaultFontName.value ?? $Settings.DefaultFontName
    $FontColor = $Settings.DefaultFontColor
    $FontSize = 0
    $SizeParsed = [int]::TryParse([string]$Settings.DefaultFontSize, [ref]$FontSize)

    # Input validation
    if ([string]::IsNullOrWhiteSpace($FontName) -or [string]::IsNullOrWhiteSpace($FontColor)) {
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SetDefaultMailboxFont: Font name and colour must both be set' -Sev Error
        return
    }
    # DefaultFontSize is the 1-7 scale Exchange stores, not a point size. 3 is the default (12pt).
    if ($SizeParsed -eq $false -or $FontSize -lt 1 -or $FontSize -gt 7) {
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "SetDefaultMailboxFont: '$($Settings.DefaultFontSize)' is not a valid font size. Exchange accepts an integer between 1 and 7" -Sev Error
        return
    }
    # Exchange stores colours as #xxxxxx; accepting #abc would never match the read-back and rewrite every mailbox on every run
    if ($FontColor -notmatch '^#[0-9A-Fa-f]{6}$') {
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "SetDefaultMailboxFont: '$FontColor' is not a valid hex colour. Exchange expects the #xxxxxx format" -Sev Error
        return
    }

    # Cached mailbox objects expose UPN, recipientTypeDetails and WhenSoftDeleted, see Set-CIPPDBCacheMailboxes.ps1
    try {
        $Mailboxes = @(New-CippDbRequest -TenantFilter $Tenant -Type 'Mailboxes' |
                Where-Object { $_.UPN -and -not $_.WhenSoftDeleted -and $_.recipientTypeDetails -in @('UserMailbox', 'SharedMailbox') } |
                Select-Object -Property @{ Name = 'UserPrincipalName'; Expression = { $_.UPN } })

        if ($Mailboxes.Count -eq 0) {
            # An empty cache would otherwise report as compliant without inspecting anything, so fall back to a live read
            Write-Information "SetDefaultMailboxFont: mailbox cache empty for $Tenant, falling back to Get-Mailbox"
            $Mailboxes = @(New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{
                    ResultSize = 'Unlimited'
                    Filter     = "RecipientTypeDetails -eq 'UserMailbox' -or RecipientTypeDetails -eq 'SharedMailbox'"
                } -Select 'UserPrincipalName,RecipientTypeDetails' |
                    Where-Object { $_.UserPrincipalName -and $_.UserPrincipalName -notlike 'DiscoverySearchMailbox*' -and $_.UserPrincipalName -notlike 'SystemMailbox*' })
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the mailbox list for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    # Get-MailboxMessageConfiguration has no server-side filter, so this is one sub-request per mailbox.
    # OperationGuid maps each response back to its UPN - the Identity Exchange returns is a canonical name.
    $Evaluated = [System.Collections.Generic.List[PSObject]]::new()
    $ReadFailures = [System.Collections.Generic.List[PSObject]]::new()

    if ($Mailboxes.Count -gt 0) {
        $UPNByOperationGuid = @{}
        $ConfigRequests = @(foreach ($Mailbox in $Mailboxes) {
                $OperationGuid = [Guid]::NewGuid().ToString()
                $UPNByOperationGuid[$OperationGuid] = $Mailbox.UserPrincipalName
                @{
                    CmdletInput   = @{
                        CmdletName = 'Get-MailboxMessageConfiguration'
                        Parameters = @{ Identity = $Mailbox.UserPrincipalName }
                    }
                    OperationGuid = $OperationGuid
                }
            })

        try {
            $ConfigResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray $ConfigRequests -Select 'Identity,DefaultFontName,DefaultFontSize,DefaultFontColor'
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not read the mailbox message configuration for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            return
        }

        foreach ($Config in @($ConfigResults)) {
            $UPN = if ($Config.OperationGuid -and $UPNByOperationGuid.ContainsKey($Config.OperationGuid)) {
                $UPNByOperationGuid[$Config.OperationGuid]
            } else {
                $Config.Identity
            }

            if ($Config.error) {
                $ReadFailures.Add([PSCustomObject]@{ UPN = $UPN; Error = (Get-NormalizedError -Message $Config.error) })
                continue
            }
            # Coercing a missing size to 0 would mark the mailbox non-compliant forever, so treat it as a failed read
            if ($null -eq $Config.DefaultFontSize) {
                $ReadFailures.Add([PSCustomObject]@{ UPN = $UPN; Error = 'Response did not contain DefaultFontSize' })
                continue
            }

            $Evaluated.Add([PSCustomObject]@{
                    UPN              = $UPN
                    DefaultFontName  = $Config.DefaultFontName
                    DefaultFontSize  = [int]$Config.DefaultFontSize
                    DefaultFontColor = $Config.DefaultFontColor
                })
        }

        if ($ReadFailures.Count -gt 0) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "SetDefaultMailboxFont: could not read the message configuration for $($ReadFailures.Count) of $($Mailboxes.Count) mailboxes." -Sev Warning -LogData @($ReadFailures)
        }
    }

    $NonCompliant = @($Evaluated | Where-Object {
            $_.DefaultFontName -ne $FontName -or $_.DefaultFontSize -ne $FontSize -or $_.DefaultFontColor -ne $FontColor
        })

    # An empty mailbox list or all-failed reads is unknown, not compliant
    $StateIsCorrect = $Evaluated.Count -gt 0 -and $NonCompliant.Count -eq 0 -and $ReadFailures.Count -eq 0

    if ($Settings.remediate -eq $true) {
        if ($Evaluated.Count -eq 0) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SetDefaultMailboxFont: No mailbox configuration could be read, so nothing was remediated.' -Sev Warning
        } elseif ($NonCompliant.Count -eq 0) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Default mailbox font is already $FontName / size $FontSize / $FontColor for all $($Evaluated.Count) mailboxes." -Sev Info
        } else {
            try {
                $UPNByOperationGuid = @{}
                $Request = @(foreach ($Mailbox in $NonCompliant) {
                        $OperationGuid = [Guid]::NewGuid().ToString()
                        $UPNByOperationGuid[$OperationGuid] = $Mailbox.UPN
                        @{
                            CmdletInput   = @{
                                CmdletName = 'Set-MailboxMessageConfiguration'
                                Parameters = @{
                                    Identity         = $Mailbox.UPN
                                    DefaultFontName  = $FontName
                                    DefaultFontSize  = $FontSize
                                    DefaultFontColor = $FontColor
                                }
                            }
                            OperationGuid = $OperationGuid
                        }
                    })

                $BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray $Request
                $Failures = [System.Collections.Generic.List[PSObject]]::new()
                foreach ($Result in @($BatchResults)) {
                    if ($Result.error) {
                        # Target is often empty on adminapi errors, so prefer the GUID map.
                        $FailedUPN = if ($Result.OperationGuid -and $UPNByOperationGuid.ContainsKey($Result.OperationGuid)) {
                            $UPNByOperationGuid[$Result.OperationGuid]
                        } else {
                            $Result.target
                        }
                        $Failures.Add([PSCustomObject]@{ UPN = $FailedUPN; Error = (Get-NormalizedError -Message $Result.error) })
                    }
                }

                if ($Failures.Count -gt 0) {
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set the default mailbox font for $($Failures.Count) mailboxes." -Sev Error -LogData @($Failures)
                }
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Set default mailbox font to $FontName / size $FontSize / $FontColor for $($NonCompliant.Count - $Failures.Count) mailboxes." -Sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set the default mailbox font. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Default mailbox font is set to $FontName / size $FontSize / $FontColor for all mailboxes." -Sev Info
        } elseif ($Evaluated.Count -eq 0) {
            Write-StandardsAlert -message 'Default mailbox font could not be evaluated: no mailbox configuration was returned' -object @($ReadFailures) -tenant $Tenant -standardName 'SetDefaultMailboxFont' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Default mailbox font could not be evaluated: no mailbox configuration was returned.' -Sev Warning
        } else {
            $AlertMessage = if ($ReadFailures.Count -gt 0) {
                "Default mailbox font is not set correctly for $($NonCompliant.Count) mailboxes, and $($ReadFailures.Count) mailboxes could not be read"
            } else {
                "Default mailbox font is not set correctly for $($NonCompliant.Count) mailboxes"
            }
            Write-StandardsAlert -message $AlertMessage -object @($NonCompliant) -tenant $Tenant -standardName 'SetDefaultMailboxFont' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "$AlertMessage." -Sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $ExpectedValue = [ordered]@{
            DefaultFontName  = $FontName
            DefaultFontSize  = $FontSize
            DefaultFontColor = $FontColor
        }
        # Drifting tenants report the non-compliant mailboxes with only the settings that differ.
        # NOTE: DelegateSentItems and calDefault store their full non-compliant lists uncapped, but
        # this list is deliberately capped: these entries are larger (up to four values per mailbox)
        # and render as pretty-printed JSON in the alignment card, so a large tenant would write a
        # huge report row on every run and make the card unusable.
        $MaxListed = 50

        $CurrentValue = if ($Evaluated.Count -eq 0) {
            [ordered]@{ state = 'No mailbox configuration could be read' }
        } elseif ($StateIsCorrect -eq $true) {
            $ExpectedValue
        } else {
            $Report = [ordered]@{
                NonCompliantMailboxes = @($NonCompliant | Select-Object -First $MaxListed | ForEach-Object {
                        $Entry = [ordered]@{ Mailbox = $_.UPN }
                        if ($_.DefaultFontName -ne $FontName) {
                            $Entry['DefaultFontName'] = if ([string]::IsNullOrWhiteSpace($_.DefaultFontName)) { 'not set' } else { $_.DefaultFontName }
                        }
                        if ($_.DefaultFontSize -ne $FontSize) {
                            $Entry['DefaultFontSize'] = $_.DefaultFontSize
                        }
                        if ($_.DefaultFontColor -ne $FontColor) {
                            $Entry['DefaultFontColor'] = if ([string]::IsNullOrWhiteSpace($_.DefaultFontColor)) { 'not set' } else { $_.DefaultFontColor }
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

        Set-CIPPStandardsCompareField -FieldName 'standards.SetDefaultMailboxFont' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
    }
}
