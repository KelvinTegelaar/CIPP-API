function New-passwordString {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param (
        [int]$count = 14
    )
    try {
    $SettingsTable = Get-CippTable -tablename 'Settings'
    $Settings = Get-CIPPAzDataTableEntity @SettingsTable -Filter "PartitionKey eq 'settings' and RowKey eq 'settings'"

    # Ensure Settings is not null to prevent null reference exceptions
    if (-not $Settings) {
        $Settings = @{}
    }

    $PasswordType = $Settings.passwordType

    # Debug logging
    Write-Verbose "Password generation - PasswordType: '$PasswordType'"
    Write-Verbose "Password generation - Settings object: $($Settings | ConvertTo-Json -Compress)"

    # Handle null/empty password type - default to Classic for safety
    if ([string]::IsNullOrEmpty($PasswordType)) {
        $PasswordType = 'Classic'
        Write-Verbose "Password generation - PasswordType was null/empty, defaulting to Classic"
    }

    # Migrate legacy password type name
    if ($PasswordType -eq 'Correct-Battery-Horse') {
        $PasswordType = 'Passphrase'
        Write-Verbose "Password generation - Migrated legacy type 'Correct-Battery-Horse' to 'Passphrase'"
    }

    # Helper functions for consistent data conversion
    function ConvertTo-Bool ($raw) {
        if ($null -eq $raw) { return $false }
        $stringValue = "$raw"
        return ($stringValue -eq 'true' -or $stringValue -eq '1' -or $stringValue -eq 'yes')
    }

    function ConvertTo-Int ($raw, $defaultValue) {
        if ($null -eq $raw) { return $defaultValue }
        if ([int]::TryParse("$raw", [ref]$null)) {
            return [int]$raw
        }
        return $defaultValue
    }

    # Cryptographically secure random integer - replaces Get-Random for password security
    function Get-CryptoRandomInt {
        param(
            [int]$Maximum,
            [int]$Minimum = 0
        )
        return [System.Security.Cryptography.RandomNumberGenerator]::GetInt32($Minimum, $Maximum)
    }

    function Get-SafeWordsPath {
        # Try multiple path resolution methods for better reliability
        $possiblePaths = @()

        if ($env:AzureWebJobsScriptRoot) {
            $possiblePaths += Join-Path $env:AzureWebJobsScriptRoot 'words.txt'
        }
        $possiblePaths += Join-Path $PSScriptRoot '..\..\..\..\words.txt'
        $possiblePaths += Join-Path $PSScriptRoot '..\..\..\..\..\words.txt'

        foreach ($path in $possiblePaths) {
            if ($path -and (Test-Path $path)) {
                return $path
            }
        }

        throw "Passphrase word list (words.txt) not found in any expected location"
    }

    # Microsoft 365 compliance validation
    function Test-Microsoft365Compliance {
        param(
            [int]$Length,
            [bool]$HasUpper,
            [bool]$HasLower,
            [bool]$HasDigits,
            [bool]$HasSpecial
        )

        # Length validation
        if ($Length -lt 8 -or $Length -gt 256) {
            throw "Password length must be between 8 and 256 characters for Microsoft 365 compliance"
        }

        # Complexity validation - need at least 3 of 4 character types
        $EnabledTypes = @()
        if ($HasLower) { $EnabledTypes += "lowercase" }
        if ($HasUpper) { $EnabledTypes += "uppercase" }
        if ($HasDigits) { $EnabledTypes += "digits" }
        if ($HasSpecial) { $EnabledTypes += "special" }

        if ($EnabledTypes.Count -lt 3) {
            throw "Microsoft 365 requires at least 3 of 4 character types: uppercase, lowercase, digits, and special characters"
        }
    }

    if ($PasswordType -eq 'Passphrase') {
        Write-Verbose "Password generation - Using Passphrase mode"
        $WordCount = ConvertTo-Int $Settings.wordCount 4
        $Separator = if ($null -ne $Settings.separator) { $Settings.separator } else { '-' }
        $Capitalize = ConvertTo-Bool $Settings.capitalizeWords
        $AppendNum = ConvertTo-Bool $Settings.appendNumber
        $AppendSpecial = ConvertTo-Bool $Settings.appendSpecialChar

        # Validate and sanitize separator - basic checks only since config validates on save
        if ($Separator -match '[\x00-\x1F\x7F]') {
            throw "Separator cannot contain control characters"
        }
        if ($Separator -match '^\s+$') {
            throw "Separator cannot be only whitespace"
        }

        # Basic validation for special character set - config validates on save
        $SpecialSetFromConfig = $Settings.specialCharSet
        if ($SpecialSetFromConfig) {
            if ($SpecialSetFromConfig -match '[\x00-\x1F\x7F]') {
                throw "Special character set cannot contain control characters"
            }
            # Validate against the same pattern as backend config - safe typable characters including forward slash
            $allowedSpecialPattern = '^[!@#$%^&*()\-_=+/]+$'
            if ($SpecialSetFromConfig -notmatch $allowedSpecialPattern) {
                throw "Special character set contains invalid symbols"
            }
        }

        # Validate word count
        if ($WordCount -lt 2 -or $WordCount -gt 10) {
            throw "Word count must be between 2 and 10 for passphrase generation"
        }

        # Get words file path with better error handling
        $WordsPath = Get-SafeWordsPath
        $Words = @(Get-Content $WordsPath -Encoding UTF8 | Where-Object { $_.Length -gt 0 -and $_ -match '^[a-zA-Z]+$' })
        if ($Words.Count -lt $WordCount) {
            throw "Passphrase word list has insufficient entries ($($Words.Count) words, need at least $WordCount)"
        }
        $wordPool = [System.Collections.Generic.List[string]]::new()
        $Words | ForEach-Object { $wordPool.Add($_) }
        $SelectedWords = @(1..$WordCount | ForEach-Object {
            $idx = Get-CryptoRandomInt -Maximum $wordPool.Count
            $word = $wordPool[$idx]
            $wordPool.RemoveAt($idx)
            $word
        })

        if ($Capitalize) {
            $SelectedWords = $SelectedWords | ForEach-Object {
                if ($_.Length -gt 1) {
                    $_.Substring(0,1).ToUpper() + $_.Substring(1)
                } elseif ($_.Length -eq 1) {
                    $_.ToUpper()
                } else {
                    $_  # This should not happen due to word validation, but keep as fallback
                }
            }
        }

        # Randomly assign numbers and special characters to specific words
        if ($AppendNum -or $AppendSpecial) {
            $wordIndices = @(0..($SelectedWords.Count - 1))

            if ($AppendNum) {
                # Randomly select a word to append number to
                $numWordIndex = $wordIndices[(Get-CryptoRandomInt -Maximum $wordIndices.Count)]
                $SelectedWords[$numWordIndex] += (Get-CryptoRandomInt -Minimum 10 -Maximum 100).ToString()
                # Remove this index from available indices
                $wordIndices = $wordIndices | Where-Object { $_ -ne $numWordIndex }
            }

            if ($AppendSpecial -and $wordIndices.Count -gt 0) {
                # Randomly select a different word to append special character to
                $specialWordIndex = $wordIndices[(Get-CryptoRandomInt -Maximum $wordIndices.Count)]
                # Use the configured special character set with proper fallback
                $AppendedSpecialSet = if ($Settings.specialCharSet -and $Settings.specialCharSet.Length -gt 0) {
                    $Settings.specialCharSet
                } else {
                    '$%&*#'
                }
                if ($AppendedSpecialSet.Length -gt 0) {
                    $SelectedWords[$specialWordIndex] += $AppendedSpecialSet[(Get-CryptoRandomInt -Maximum $AppendedSpecialSet.Length)]
                }
            }
        }

        $Passphrase = $SelectedWords -join $Separator

        # Validate Microsoft 365 compliance against actual generated passphrase
        $HasLowercase = $Passphrase -cmatch '[a-z]'
        $HasUppercase = $Passphrase -cmatch '[A-Z]'
        $HasDigits = $Passphrase -match '\d'
        $HasSpecial = $false
        $passphraseChars = $Passphrase.ToCharArray()
        foreach ($c in $passphraseChars) {
            if (-not [char]::IsLetterOrDigit($c)) {
                $HasSpecial = $true
                break
            }
        }

        Test-Microsoft365Compliance -Length $Passphrase.Length -HasUpper $HasUppercase -HasLower $HasLowercase -HasDigits $HasDigits -HasSpecial $HasSpecial

        $Passphrase
    } else {
        Write-Verbose "Password generation - Using Classic mode"
        $CharCount = ConvertTo-Int $Settings.charCount $count
        $UseUpper = if ($null -ne $Settings.includeUppercase) { ConvertTo-Bool $Settings.includeUppercase } else { $true }
        $UseLower = if ($null -ne $Settings.includeLowercase) { ConvertTo-Bool $Settings.includeLowercase } else { $true }
        $UseDigits = if ($null -ne $Settings.includeDigits) { ConvertTo-Bool $Settings.includeDigits } else { $true }
        $UseSpecial = if ($null -ne $Settings.includeSpecialChars) { ConvertTo-Bool $Settings.includeSpecialChars } else { $true }
        $SpecialSet = if ($Settings.specialCharSet) { $Settings.specialCharSet } else { '$%&*#' }

        # Basic validation for special character set - config validates on save
        if ($UseSpecial -and $SpecialSet -match '[\x00-\x1F\x7F]') {
            throw "Special character set contains control characters"
        }
        # Validate against the same pattern as backend config - safe typable characters including forward slash
        $allowedSpecialPattern = '^[!@#$%^&*()\-_=+/]+$'
        if ($UseSpecial -and $SpecialSet -notmatch $allowedSpecialPattern) {
            throw "Special character set contains invalid symbols"
        }

        # Validate character count for Microsoft 365 compliance
        if ($CharCount -lt 8 -or $CharCount -gt 256) {
            throw "Character count must be between 8 and 256 for Microsoft 365 compliance"
        }

        # Check Microsoft 365 complexity requirement
        $EnabledTypes = @()
        if ($UseLower) { $EnabledTypes += "lowercase" }
        if ($UseUpper) { $EnabledTypes += "uppercase" }
        if ($UseDigits) { $EnabledTypes += "digits" }
        if ($UseSpecial) { $EnabledTypes += "special" }

        if ($EnabledTypes.Count -lt 3) {
            throw "Microsoft 365 requires at least 3 of 4 character types: uppercase, lowercase, digits, and special characters"
        }

        # Generate character pool with accurate capacity calculation
        $actualSize = 0
        if ($UseUpper) { $actualSize += 22 }
        if ($UseLower) { $actualSize += 20 }
        if ($UseDigits) { $actualSize += 8 }
        if ($UseSpecial) { $actualSize += $SpecialSet.Length }
        $CharPoolBuilder = [System.Text.StringBuilder]::new($actualSize)
        if ($UseUpper) { [void]$CharPoolBuilder.Append('ABCDEFGHKLMNPRSTUVWXYZ') }
        if ($UseLower) { [void]$CharPoolBuilder.Append('abcdefghkmnrstuvwxyz') }
        if ($UseDigits) { [void]$CharPoolBuilder.Append('23456789') }
        if ($UseSpecial) { [void]$CharPoolBuilder.Append($SpecialSet) }
        $CharPool = $CharPoolBuilder.ToString()

        # Instead of falling back to full pool, enforce that at least one character type must be selected
        if ($CharPool.Length -eq 0) {
            throw "At least one character class must be selected for classic password generation"
        }

        # Generate a complex password with a maximum of 100 tries
        $PoolChars = $CharPool.ToCharArray()
        $maxTries = 100
        $tryCount = 0

        do {
            $Password = -join (1..$CharCount | ForEach-Object { $PoolChars[(Get-CryptoRandomInt -Maximum $PoolChars.Length)] })

            $isComplex = $true
            if ($UseUpper) { $isComplex = $isComplex -and ($Password -cmatch '[A-Z]') }
            if ($UseLower) { $isComplex = $isComplex -and ($Password -cmatch '[a-z]') }
            if ($UseDigits) { $isComplex = $isComplex -and ($Password -cmatch '\d') }
            if ($UseSpecial) {
                # Safe special character validation without regex injection
                $hasSpecialChar = $false
                $specialChars = $SpecialSet.ToCharArray()
                foreach ($char in $specialChars) {
                    if ($Password.IndexOf($char) -ge 0) {
                        $hasSpecialChar = $true
                        break
                    }
                }
                $isComplex = $isComplex -and $hasSpecialChar
            }

            $tryCount++
        } while (!$isComplex -and ($tryCount -lt $maxTries))

        # If we couldn't generate a compliant password, throw an error
        if (!$isComplex) {
            throw "Failed to generate a compliant password after $maxTries attempts. Please check your character class settings."
        }

        $Password
    }
    } catch {
        $errorMessage = "Password generation with configured settings failed: $($_.Exception.Message)"
        Write-Warning $errorMessage
        Write-Debug "Error details: $($_.Exception.ToString())"

        # Fallback to secure default generation with validation
        try {
            $fallbackChars = 'abcdefghkmnrstuvwxyzABCDEFGHKLMNPRSTUVWXYZ23456789$%&*#'.ToCharArray()
            $fallbackCount = [Math]::Max($count, 14)
            $fallbackMaxTries = 100
            $fallbackTry = 0

            # Validate fallback character set has sufficient complexity
            $fbHasLower = ($fallbackChars | Where-Object { $_ -cmatch '[a-z]' }).Count
            $fbHasUpper = ($fallbackChars | Where-Object { $_ -cmatch '[A-Z]' }).Count
            $fbHasDigits = ($fallbackChars | Where-Object { $_ -match '\d' }).Count
            $fbHasSpecial = ($fallbackChars | Where-Object { $_ -match '[$%&*#]' }).Count

            if ($fbHasLower -eq 0 -or $fbHasUpper -eq 0 -or $fbHasDigits -eq 0 -or $fbHasSpecial -eq 0) {
                throw "Fallback character set lacks sufficient complexity for Microsoft 365 compliance"
            }

            do {
                $fallbackPassword = -join (1..$fallbackCount | ForEach-Object { $fallbackChars[([System.Security.Cryptography.RandomNumberGenerator]::GetInt32($fallbackChars.Length))] })
                $fbComplex = ($fallbackPassword -cmatch '[a-z]') -and ($fallbackPassword -cmatch '[A-Z]') -and ($fallbackPassword -match '\d') -and ($fallbackPassword -match '[$%&*#]')
                $fallbackTry++
            } while (-not $fbComplex -and $fallbackTry -lt $fallbackMaxTries)

            if (-not $fbComplex) {
                throw "Failed to generate compliant fallback password after $fallbackMaxTries attempts"
            }

            Write-Warning "Using fallback password generation with secure defaults"
            return $fallbackPassword
        } catch {
            $finalError = "Both configured and fallback password generation failed: $($_.Exception.Message)"
            Write-Error $finalError
            throw $finalError
        }
    }
}
