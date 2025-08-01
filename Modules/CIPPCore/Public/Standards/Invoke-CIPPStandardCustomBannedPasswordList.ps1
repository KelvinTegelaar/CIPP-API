function Invoke-CIPPStandardCustomBannedPasswordList {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) CustomBannedPasswordList
    .SYNOPSIS
        (Label) Update Entra ID Custom Banned Password List
    .DESCRIPTION
        (Helptext) Updates the Entra ID custom banned password list with organization-specific terms. Requires Entra ID P1 or P2 licenses. Enter words separated by commas or new lines. Each word must be 4-16 characters long. Maximum 1,000 words allowed.
        (DocsDescription) Updates the Entra ID custom banned password list with organization-specific terms that should be blocked from user passwords. This supplements the global banned password list maintained by Microsoft. The custom list is limited to 1,000 key base terms of 4-16 characters each. Entra ID will block variations and combinations of these terms in user passwords.
    .NOTES
        CAT
            Global Standards
        TAG
            "CIS M365 5.0 (5.2.3.2)"
        ADDEDCOMPONENT
            {"type":"textArea","name":"standards.CustomBannedPasswordList.BannedWords","label":"Banned Words List","placeholder":"Enter banned words separated by commas or new lines (4-16 characters each, max 1000 words)","required":true,"rows":10}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-06-28
        POWERSHELLEQUIVALENT
            Get-MgBetaDirectorySetting, New-MgBetaDirectorySetting, Update-MgBetaDirectorySetting
        RECOMMENDEDBY
            "CIS", "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    Write-Host "All params received: $Tenant, $tenant, $($Settings | ConvertTo-Json -Depth 10 -Compress)"
    $PasswordRuleTemplateId = '5cf42378-d67d-4f36-ba46-e8b86229381d'
    # Parse and validate banned words from input
    $BannedWordsInput = $Settings.BannedWords
    if ([string]::IsNullOrWhiteSpace($BannedWordsInput)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'CustomBannedPasswordList: No banned words provided' -sev Error
        return
    }

    # Split input by commas, newlines, or semicolons and clean up
    $BannedWordsList = $BannedWordsInput -split '[,;\r\n]+' | ForEach-Object { ($_.Trim()) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    # Validate word count
    if ($BannedWordsList.Count -gt 1000) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "CustomBannedPasswordList: Too many banned words provided ($($BannedWordsList.Count)). Maximum allowed is 1000." -sev Error
        return
    }

    # Validate word length (4-16 characters), remove duplicates and invalid words
    $ValidBannedWordsList = [System.Collections.Generic.List[string]]::new()
    $InvalidWords = [System.Collections.Generic.List[string]]::new()

    foreach ($Word in $BannedWordsList) {
        if ($Word.Length -ge 4 -and $Word.Length -le 16) {
            $ValidBannedWordsList.Add($Word)
        } else {
            $InvalidWords.Add($Word)
        }
    }
    $BannedWordsList = $ValidBannedWordsList | Select-Object -Unique

    # Alert if invalid words are found
    if ($InvalidWords.Count -gt 0) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "CustomBannedPasswordList: Invalid words found in input (must be 4-16 characters). Please remove the following words: $($InvalidWords -join ', ')" -sev Warning
    }

    # Get existing directory settings for password rules
    try {
        $ExistingSettings = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/settings' -tenantid $Tenant | Where-Object { $_.templateId -eq $PasswordRuleTemplateId }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to get existing Custom Banned Password List: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate Custom Banned Password List'

        if ($null -eq $ExistingSettings) {
            Write-Host 'No existing Custom Banned Password List found, creating new one'
            # Create new directory setting with default values if it doesn't exist
            try {
                $Body = @{
                    templateId = $PasswordRuleTemplateId
                    values     = @(
                        @{
                            name  = 'EnableBannedPasswordCheck'
                            value = 'True'
                        }
                        @{
                            name  = 'BannedPasswordList'
                            value = $BannedWordsList -join ([char]9)
                        }
                        @{
                            name  = 'LockoutDurationInSeconds'
                            value = '60'
                        }
                        @{
                            name  = 'LockoutThreshold'
                            value = '10'
                        }
                        @{
                            name  = 'EnableBannedPasswordCheckOnPremises'
                            value = 'False'
                        }
                        @{
                            name  = 'BannedPasswordCheckOnPremisesMode'
                            value = 'Audit'
                        }
                    )
                }
                $JsonBody = ConvertTo-Json -Depth 10 -InputObject $Body -Compress

                $ExistingSettings = New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/settings' -Type POST -Body $JsonBody
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Custom Banned Password List created with $($BannedWordsList.Count) words." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Custom Banned Password List: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-Host 'Existing Custom Banned Password List found, updating it'
            # Update existing directory setting
            try {
                # Get the current passwords and check if all the new words are already in the list
                $CurrentBannedWords = $ExistingSettings.values | Where-Object { $_.name -eq 'BannedPasswordList' }
                $CurrentBannedWords = $CurrentBannedWords.value -split ([char]9)

                # Check if the new words are already in the list
                $NewBannedWords = $BannedWordsList | Where-Object { $CurrentBannedWords -notcontains $_ }
                if ($NewBannedWords.Count -eq 0 -and ($ExistingSettings.values | Where-Object { $_.name -eq 'EnableBannedPasswordCheck' }).value -eq 'True') {
                    Write-Host 'No new words to add'
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Custom Banned Password List is already configured with $($CurrentBannedWords.Count) words." -sev Info
                } else {
                    Write-Host "$($NewBannedWords.Count) new words to add"
                    $AllBannedWords = [System.Collections.Generic.List[string]]::new()
                    $NewBannedWords | ForEach-Object { $AllBannedWords.Add($_) }
                    $CurrentBannedWords | ForEach-Object { $AllBannedWords.Add($_) }
                    $AllBannedWords = $AllBannedWords | Select-Object -Unique -First 1000 | Where-Object { $_ -ne $null }

                    $Body = @{
                        values = @(
                            @{
                                name  = 'EnableBannedPasswordCheck'
                                value = 'True'
                            }
                            @{
                                name  = 'BannedPasswordList'
                                value = $AllBannedWords -join ([char]9)
                            }
                            @{
                                name  = 'LockoutDurationInSeconds'
                                value = ($ExistingSettings.values | Where-Object { $_.name -eq 'LockoutDurationInSeconds' }).value
                            }
                            @{
                                name  = 'LockoutThreshold'
                                value = ($ExistingSettings.values | Where-Object { $_.name -eq 'LockoutThreshold' }).value
                            }
                            @{
                                name  = 'EnableBannedPasswordCheckOnPremises'
                                value = ($ExistingSettings.values | Where-Object { $_.name -eq 'EnableBannedPasswordCheckOnPremises' }).value
                            }
                            @{
                                name  = 'BannedPasswordCheckOnPremisesMode'
                                value = ($ExistingSettings.values | Where-Object { $_.name -eq 'BannedPasswordCheckOnPremisesMode' }).value
                            }
                        )
                    }

                    $JsonBody = ConvertTo-Json -Depth 10 -InputObject $Body -Compress
                    $null = New-GraphPostRequest -tenantid $Tenant -Uri "https://graph.microsoft.com/beta/settings/$($ExistingSettings.id)" -Type PATCH -Body $JsonBody
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Custom Banned Password List updated with $($NewBannedWords.Count) new words." -sev Info
                }

            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update Custom Banned Password List: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($null -eq $ExistingSettings) {
            Write-StandardsAlert -message 'Custom Banned Password List is not configured' -object @{Status = 'Not Configured'; WordCount = 0 } -tenant $tenant -standardName 'CustomBannedPasswordList' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Custom Banned Password List is not configured' -sev Info
        } else {
            $BannedPasswordCheckEnabled = $ExistingSettings.values | Where-Object { $_.name -eq 'EnableBannedPasswordCheck' }
            $CurrentBannedWords = $ExistingSettings.values | Where-Object { $_.name -eq 'BannedPasswordList' }
            $CurrentBannedWords = if ($CurrentBannedWords.value) { ($CurrentBannedWords.value -split ([char]9)) } else { @() }

            # Find missing words from input
            $MissingInputWords = $BannedWordsList | Where-Object { $CurrentBannedWords -notcontains $_ }

            if ($MissingInputWords.Count -gt 0) {
                Write-StandardsAlert -message "Custom Banned Password List is missing $($MissingInputWords.Count) input words: $($MissingInputWords -join ', ')" -object @{Status = 'Configured but Missing Input Words'; MissingWords = $MissingInputWords; Enabled = $BannedPasswordCheckEnabled.value } -tenant $tenant -standardName 'CustomBannedPasswordList' -standardId $Settings.standardId
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Custom Banned Password List is missing $($MissingInputWords.Count) input words: $($MissingInputWords -join ', ')" -sev Info
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Custom Banned Password List contains all input words ($($BannedWordsList.Count))." -sev Info
            }
        }
    }

    if ($Settings.report -eq $true) {
        if ($null -eq $ExistingSettings) {
            $BannedPasswordState = @{
                Status            = 'Not Configured'
                Enabled           = $false
                WordCount         = 0
                Compliant         = $false
                MissingInputWords = $BannedWordsList
            }
        } else {
            $BannedPasswordCheckEnabled = $ExistingSettings.values | Where-Object { $_.name -eq 'EnableBannedPasswordCheck' }
            $CurrentBannedWords = $ExistingSettings.values | Where-Object { $_.name -eq 'BannedPasswordList' }
            $CurrentBannedWords = if ($CurrentBannedWords.value) { ($CurrentBannedWords.value -split ([char]9)) } else { @() }
            $CurrentWordCount = $CurrentBannedWords.Count

            # Find missing words from input
            $MissingInputWords = $BannedWordsList | Where-Object { $CurrentBannedWords -notcontains $_ }

            $BannedPasswordState = @{
                Status            = 'Configured'
                Enabled           = $BannedPasswordCheckEnabled.value -eq 'True'
                WordCount         = $CurrentWordCount
                Compliant         = ($BannedPasswordCheckEnabled.value -eq 'True' -and $MissingInputWords.Count -eq 0)
                MissingInputWords = $MissingInputWords
            }
        }

        Add-CIPPBPAField -FieldName 'CustomBannedPasswordList' -FieldValue $BannedPasswordState -StoreAs json -Tenant $tenant
        Set-CIPPStandardsCompareField -FieldName 'standards.CustomBannedPasswordList' -FieldValue $BannedPasswordState.Compliant -Tenant $tenant
    }


}
