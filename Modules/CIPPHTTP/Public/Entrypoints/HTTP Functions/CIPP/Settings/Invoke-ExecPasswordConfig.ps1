function Invoke-ExecPasswordConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $StatusCode = [HttpStatusCode]::OK
    $Table = Get-CIPPTable -TableName Settings
    $PasswordSettings = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'settings' and RowKey eq 'settings'"

    $results = try {
        if ($Request.Query.List) {
            if (-not $PasswordSettings) {
                # Return default values if not set
                @{
                    passwordType        = 'Classic'
                    charCount           = 14
                    includeUppercase    = $true
                    includeLowercase    = $true
                    includeDigits       = $true
                    includeSpecialChars = $true
                    specialCharSet      = '$%&*#'
                    wordCount           = 4
                    separator           = '-'
                    capitalizeWords     = $false
                    appendNumber        = $false
                    appendSpecialChar   = $false
                }
            } else {
                # Migrate legacy 'Correct-Battery-Horse' type to 'Passphrase'
                $storedType = if ($PasswordSettings.passwordType) { $PasswordSettings.passwordType } else { 'Classic' }
                $needsMigration = $storedType -eq 'Correct-Battery-Horse'
                if ($needsMigration) {
                    $storedType = 'Passphrase'
                }

                $resolvedConfig = @{
                    passwordType        = $storedType
                    charCount           = if ($PasswordSettings.charCount -and [int]::TryParse("$($PasswordSettings.charCount)", [ref]$null)) { [int]$PasswordSettings.charCount } else { 14 }
                    includeUppercase    = if ($null -ne $PasswordSettings.includeUppercase) { [bool]$PasswordSettings.includeUppercase } else { $true }
                    includeLowercase    = if ($null -ne $PasswordSettings.includeLowercase) { [bool]$PasswordSettings.includeLowercase } else { $true }
                    includeDigits       = if ($null -ne $PasswordSettings.includeDigits) { [bool]$PasswordSettings.includeDigits } else { $true }
                    includeSpecialChars = if ($null -ne $PasswordSettings.includeSpecialChars) { [bool]$PasswordSettings.includeSpecialChars } else { $true }
                    specialCharSet      = if ($PasswordSettings.specialCharSet) { $PasswordSettings.specialCharSet } else { '$%&*#' }
                    wordCount           = if ($PasswordSettings.wordCount -and [int]::TryParse("$($PasswordSettings.wordCount)", [ref]$null)) { [int]$PasswordSettings.wordCount } else { 4 }
                    separator           = if ($null -ne $PasswordSettings.separator) { $PasswordSettings.separator } else { '-' }
                    capitalizeWords     = if ($null -ne $PasswordSettings.capitalizeWords) { [bool]$PasswordSettings.capitalizeWords } else { $false }
                    appendNumber        = if ($null -ne $PasswordSettings.appendNumber) { [bool]$PasswordSettings.appendNumber } else { $false }
                    appendSpecialChar   = if ($null -ne $PasswordSettings.appendSpecialChar) { [bool]$PasswordSettings.appendSpecialChar } else { $false }
                }

                # Persist migrated config so legacy type is upgraded in storage
                if ($needsMigration) {
                    $MigratedEntity = @{
                        'PartitionKey'        = 'settings'
                        'RowKey'              = 'settings'
                        'passwordType'        = $resolvedConfig.passwordType
                        'charCount'           = "$($resolvedConfig.charCount)"
                        'includeUppercase'    = $resolvedConfig.includeUppercase
                        'includeLowercase'    = $resolvedConfig.includeLowercase
                        'includeDigits'       = $resolvedConfig.includeDigits
                        'includeSpecialChars' = $resolvedConfig.includeSpecialChars
                        'specialCharSet'      = $resolvedConfig.specialCharSet
                        'wordCount'           = "$($resolvedConfig.wordCount)"
                        'separator'           = $resolvedConfig.separator
                        'capitalizeWords'     = $resolvedConfig.capitalizeWords
                        'appendNumber'        = $resolvedConfig.appendNumber
                        'appendSpecialChar'   = $resolvedConfig.appendSpecialChar
                    }
                    Add-CIPPAzDataTableEntity @Table -Entity $MigratedEntity -Force | Out-Null
                    Write-LogMessage -headers $Request.Headers -API $APIName -message "Migrated legacy password type 'Correct-Battery-Horse' to 'Passphrase'" -Sev 'Info'
                }

                $resolvedConfig
            }
        } else {


            # Password type validation
            $pwType = if ($null -ne $Request.Body.passwordType) { "$($Request.Body.passwordType)" } else { '' }
            # Accept legacy type name and normalize to new name
            if ($pwType -eq 'Correct-Battery-Horse') {
                $pwType = 'Passphrase'
            }
            if ($pwType -notin @('Classic', 'Passphrase')) {
                $StatusCode = [HttpStatusCode]::BadRequest
                throw 'Please select a valid password type (Classic or Passphrase)'
            }

            $includeUppercase = [bool]$Request.Body.includeUppercase
            $includeLowercase = [bool]$Request.Body.includeLowercase
            $includeDigits = [bool]$Request.Body.includeDigits
            $includeSpecialChars = [bool]$Request.Body.includeSpecialChars
            $capitalizeWords = [bool]$Request.Body.capitalizeWords
            $appendNumber = [bool]$Request.Body.appendNumber
            $appendSpecialChar = [bool]$Request.Body.appendSpecialChar

            # Char count validation (classic only)
            $charCount = 0
            if ($pwType -eq 'Classic') {
                if (-not [int]::TryParse("$($Request.Body.charCount)", [ref]$charCount)) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    throw 'Password length must be a valid number'
                } elseif ($charCount -lt 8 -or $charCount -gt 256) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    throw 'Password length must be between 8 and 256 characters'
                }
            } else {
                # Still parse for storage, but don't reject invalid values for the inactive mode
                if ([int]::TryParse("$($Request.Body.charCount)", [ref]$charCount)) { } else { $charCount = 14 }
            }

            # Word count validation (passphrase only)
            $wordCount = 0
            if ($pwType -eq 'Passphrase') {
                if (-not [int]::TryParse("$($Request.Body.wordCount)", [ref]$wordCount)) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    throw 'Word count must be a valid number'
                } elseif ($wordCount -lt 3 -or $wordCount -gt 10) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    throw 'Word count must be between 3 and 10 words'
                }
            } else {
                if ([int]::TryParse("$($Request.Body.wordCount)", [ref]$wordCount)) { } else { $wordCount = 4 }
            }

            # Special character set validation with enhanced security
            $specialCharSet = if ($null -ne $Request.Body.specialCharSet) { "$($Request.Body.specialCharSet)" } else { '' }
            # Define safe and easily typable special character set including forward slash
            $allowedSpecialPattern = '^[!@#$%^&*()\-_=+/]+$'
            if ($includeSpecialChars -or $appendSpecialChar) {
                if ([string]::IsNullOrEmpty($specialCharSet)) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    throw 'Special characters cannot be empty when enabled'
                } elseif ($specialCharSet.Length -gt 32) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    throw 'Special characters set must be 32 characters or fewer'
                } elseif ($specialCharSet -match '[\x00-\x1F\x7F]') {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    throw 'Special characters cannot contain control characters'
                } elseif ($specialCharSet -notmatch $allowedSpecialPattern) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    throw 'Special characters contain invalid symbols. Only safe typable characters allowed: !@#$%^&*()-_=+/'
                }
            }

            # Separator validation with enhanced security - allow space or empty
            $separator = if ($null -ne $Request.Body.separator) { "$($Request.Body.separator)" } else { '' }
            if ($separator.Length -gt 5) {
                $StatusCode = [HttpStatusCode]::BadRequest
                throw 'Separator must be 5 characters or fewer'
            }
            # Allow empty separator or single space, otherwise validate against safe characters
            if ($separator -ne '' -and $separator -ne ' ') {
                # Use the same validation pattern as special characters for consistency
                if ($separator -match '[\x00-\x1F\x7F]') {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    throw 'Separator cannot contain control characters'
                }
                if ($separator -match '[\u2000-\u200F\u2028-\u202F\u205F\u3000]') {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    throw 'Separator cannot contain Unicode whitespace characters'
                }
                if ($separator -notmatch $allowedSpecialPattern) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    throw 'Separator contains invalid symbols. Only safe typable characters allowed: !@#$%^&*()-_=+/ (or space/empty)'
                }
            }

            # Microsoft 365 complexity validation: at least 3 of 4 character types
            if ($pwType -eq 'Classic') {
                $enabledCount = 0
                if ($includeUppercase) { $enabledCount++ }
                if ($includeLowercase) { $enabledCount++ }
                if ($includeDigits) { $enabledCount++ }
                if ($includeSpecialChars) { $enabledCount++ }
                if ($enabledCount -lt 3) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    throw 'Classic passwords must include at least 3 of these 4 types: uppercase letters, lowercase letters, numbers, and special characters'
                }
            } else {
                # Passphrase complexity validation
                $hasLower = $true   # words always contain lowercase
                $hasUpper = $capitalizeWords
                $hasDigits = $appendNumber
                $hasSpecial = $appendSpecialChar

                # Check if separator contains special characters or digits - validate actual content
                if ($separator) {
                    $HasSpecialSeparator = $separator -match '[!@#$%^&*()_+\-=[\]{};:,.<>/?|~]'
                    $HasDigitSeparator = $separator -match '\d'
                    if ($HasSpecialSeparator) {
                        $hasSpecial = $true
                    }
                    if ($HasDigitSeparator) {
                        $hasDigits = $true
                    }
                }

                $ppTypes = @($hasLower, $hasUpper, $hasDigits, $hasSpecial).Where({ $_ }).Count
                if ($ppTypes -lt 3) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    throw 'Passphrases must include at least 3 of these 4 types: lowercase letters (from words), uppercase letters (capitalization), numbers (appended), and special characters (appended)'
                }
            }

            # ── Persist validated config ──────────────────────────────────────
            $PasswordConfig = @{
                'PartitionKey'        = 'settings'
                'RowKey'              = 'settings'
                'passwordType'        = $pwType
                'charCount'           = "$charCount"
                'includeUppercase'    = $includeUppercase
                'includeLowercase'    = $includeLowercase
                'includeDigits'       = $includeDigits
                'includeSpecialChars' = $includeSpecialChars
                'specialCharSet'      = $specialCharSet
                'wordCount'           = "$wordCount"
                'separator'           = $separator
                'capitalizeWords'     = $capitalizeWords
                'appendNumber'        = $appendNumber
                'appendSpecialChar'   = $appendSpecialChar
            }

            Add-CIPPAzDataTableEntity @Table -Entity $PasswordConfig -Force | Out-Null
            Write-LogMessage -headers $Request.Headers -API $APIName -message 'Successfully set password configuration' -Sev 'Info'
            'Successfully set the configuration'
        }
    } catch {
        if ($StatusCode -eq [HttpStatusCode]::OK) {
            $StatusCode = [HttpStatusCode]::InternalServerError
        }
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to set password configuration: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        "Failed to set configuration: $($ErrorMessage.NormalizedError)"
    }

    $body = [pscustomobject]@{'Results' = if ($null -ne $results) { $results } else { 'Operation completed' } }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })

}
