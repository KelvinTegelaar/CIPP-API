function New-CIPPUser {
    [CmdletBinding()]
    param (
        $UserObj,
        $Aliases = 'Scheduled',
        $RestoreValues,
        $APIName = 'New User',
        $Headers
    )

    try {
        $UserObj = $UserObj | ConvertTo-Json -Depth 10 | ConvertFrom-Json -Depth 10

        #Region Input Validation
        #TODO: Move this to a separate function for reuse in other parts of the API that needs input validation
        $ValidationRules = @(
            @{ Field = 'tenantFilter'; Type = 'Required'; Value = $UserObj.tenantFilter }
            @{ Field = 'displayName'; Type = 'Required'; Value = $UserObj.displayName }
            @{ Field = 'username'; Type = 'Required'; Value = $UserObj.username }
            @{ Field = 'displayName'; Type = 'MaxLength'; Value = $UserObj.displayName; MaxLength = 256 }
            @{ Field = 'username'; Type = 'MaxLength'; Value = $UserObj.username; MaxLength = 64 }
            @{ Field = 'givenName'; Type = 'MaxLength'; Value = $UserObj.givenName; MaxLength = 64 }
            @{ Field = 'surname'; Type = 'MaxLength'; Value = $UserObj.surname; MaxLength = 64 }
            @{ Field = 'jobTitle'; Type = 'MaxLength'; Value = $UserObj.jobTitle; MaxLength = 128 }
            @{ Field = 'department'; Type = 'MaxLength'; Value = $UserObj.department; MaxLength = 64 }
            @{ Field = 'companyName'; Type = 'MaxLength'; Value = $UserObj.companyName; MaxLength = 64 }
            @{ Field = 'mobilePhone'; Type = 'MaxLength'; Value = $UserObj.mobilePhone; MaxLength = 64 }
            @{ Field = 'streetAddress'; Type = 'MaxLength'; Value = $UserObj.streetAddress; MaxLength = 1024 }
            @{ Field = 'city'; Type = 'MaxLength'; Value = $UserObj.city; MaxLength = 128 }
            @{ Field = 'state'; Type = 'MaxLength'; Value = $UserObj.state; MaxLength = 128 }
            @{ Field = 'postalCode'; Type = 'MaxLength'; Value = $UserObj.postalCode; MaxLength = 40 }
            @{ Field = 'username'; Type = 'Pattern'; Value = $UserObj.username; Pattern = "^[A-Za-z0-9'\.\-_!#\^~]{1,64}$"; PatternDesc = "letters, numbers, and ' . - _ ! # ^ ~ only (no accented or Unicode characters)" }
            @{ Field = 'Domain'; Type = 'Pattern'; Value = $UserObj.Domain; Pattern = "^[A-Za-z0-9'\.\-_!#\^~]{1,64}$"; PatternDesc = "letters, numbers, and ' . - _ ! # ^ ~ only (no accented or Unicode characters)" }
            @{ Field = 'MustChangePass'; Type = 'Pattern'; Value = "$($UserObj.MustChangePass)"; Pattern = '^(true|false|True|False|1|0)$'; PatternDesc = 'must be a boolean value (true/false)' }
            @{ Field = 'otherMails'; Type = 'Pattern'; Value = $UserObj.otherMails; Pattern = '^[^@\s]+@[^@\s]+\.[^@\s]+$'; PatternDesc = 'must be a valid email address' }
        )

        $ValidationErrors = [System.Collections.Generic.List[string]]::new()

        foreach ($Rule in $ValidationRules) {
            $IsCollection = $Rule.Value -is [System.Collections.IEnumerable] -and $Rule.Value -isnot [string]
            $IsEmpty = -not $IsCollection -and [string]::IsNullOrWhiteSpace($Rule.Value)
            switch ($Rule.Type) {
                'Required' {
                    if ($IsEmpty) {
                        $ValidationErrors.Add("'$($Rule.Field)' is required.")
                    }
                }
                'MaxLength' {
                    if (-not $IsEmpty -and $Rule.Value.Length -gt $Rule.MaxLength) {
                        $ValidationErrors.Add("'$($Rule.Field)' exceeds the maximum length of $($Rule.MaxLength) characters (got $($Rule.Value.Length)).")
                    }
                }
                'Pattern' {
                    foreach ($Item in @($Rule.Value)) {
                        if (-not [string]::IsNullOrWhiteSpace($Item) -and $Item -notmatch $Rule.Pattern) {
                            if ($IsCollection) {
                                $ValidationErrors.Add("'$($Rule.Field)' contains an invalid value '$Item': $($Rule.PatternDesc).")
                            } else {
                                $ValidationErrors.Add("'$($Rule.Field)' has an invalid format: $($Rule.PatternDesc).")
                            }
                        }
                    }
                }
                'AllowedValues' {
                    if (-not $IsEmpty -and $Rule.Value -notin $Rule.AllowedValues) {
                        $ValidationErrors.Add("'$($Rule.Field)' value '$($Rule.Value)' is not a valid allowed value.")
                    }
                }
                'Range' {
                    if (-not $IsEmpty) {
                        $numValue = 0.0
                        if ([double]::TryParse("$($Rule.Value)", [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$numValue)) {
                            if ($numValue -lt $Rule.Min -or $numValue -gt $Rule.Max) {
                                $ValidationErrors.Add("'$($Rule.Field)' must be between $($Rule.Min) and $($Rule.Max) (got $numValue).")
                            }
                        } else {
                            $ValidationErrors.Add("'$($Rule.Field)' must be a number between $($Rule.Min) and $($Rule.Max).")
                        }
                    }
                }
            }
        }

        if ($ValidationErrors.Count -gt 0) {
            throw ($ValidationErrors -join '; ')
        }
        #EndRegion Input Validation

        Write-Host $UserObj.PrimDomain.value
        $Aliases = ($UserObj.AddedAliases) -split '\s'
        $password = if ($UserObj.password) { $UserObj.password } else { New-passwordString }
        $UserPrincipalName = "$($UserObj.username)@$($UserObj.Domain ? $UserObj.Domain : $UserObj.PrimDomain.value)"
        Write-Host "Creating user $UserPrincipalName"
        Write-Host "tenant filter is $($UserObj.tenantFilter)"
        $BodyToship = [pscustomobject] @{
            'givenName'         = $UserObj.givenName
            'surname'           = $UserObj.surname
            'accountEnabled'    = $true
            'displayName'       = $UserObj.displayName
            'department'        = $UserObj.department
            'mailNickname'      = $UserObj.username ? $UserObj.username : $UserObj.mailNickname
            'userPrincipalName' = $UserPrincipalName
            'usageLocation'     = $UserObj.usageLocation.value ? $UserObj.usageLocation.value : $UserObj.usageLocation
            'otherMails'        = $UserObj.otherMails ? @($UserObj.otherMails) : @()
            'jobTitle'          = $UserObj.jobTitle
            'mobilePhone'       = $UserObj.mobilePhone
            'streetAddress'     = $UserObj.streetAddress
            'city'              = $UserObj.city
            'state'             = $UserObj.state
            'country'           = $UserObj.country
            'postalCode'        = $UserObj.postalCode
            'companyName'       = $UserObj.companyName
            'passwordProfile'   = @{
                'forceChangePasswordNextSignIn' = [bool]$UserObj.MustChangePass
                'password'                      = $password
            }
        }
        if ($UserObj.businessPhones) { $bodytoShip | Add-Member -NotePropertyName businessPhones -NotePropertyValue @($UserObj.businessPhones) }
        if ($UserObj.defaultAttributes) {
            $UserObj.defaultAttributes | Get-Member -MemberType NoteProperty | ForEach-Object {
                Write-Host "Editing user and adding $($_.Name) with value $($UserObj.defaultAttributes.$($_.Name).value)"
                if (-not [string]::IsNullOrWhiteSpace($UserObj.defaultAttributes.$($_.Name).value)) {
                    Write-Host 'adding body to ship'
                    $BodyToShip | Add-Member -NotePropertyName $_.Name -NotePropertyValue $UserObj.defaultAttributes.$($_.Name).value -Force
                }
            }
        }
        if ($UserObj.customData) {
            $UserObj.customData | Get-Member -MemberType NoteProperty | ForEach-Object {
                Write-Host "Editing user and adding custom data $($_.Name) with value $($UserObj.customData.$($_.Name))"
                if (-not [string]::IsNullOrWhiteSpace($UserObj.customData.$($_.Name))) {
                    Write-Host 'adding custom data to body'
                    $BodyToShip | Add-Member -NotePropertyName $_.Name -NotePropertyValue $UserObj.customData.$($_.Name) -Force
                }
            }
        }
        $bodyToShip = ConvertTo-Json -Depth 10 -InputObject $BodyToship -Compress
        Write-Host "Shipping: $bodyToShip"
        $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/users' -tenantId $UserObj.tenantFilter -type POST -body $BodyToship -verbose
        Write-LogMessage -headers $Headers -API $APIName -tenant $($UserObj.tenantFilter) -message "Created user $($UserObj.displayName) with id $($GraphRequest.id)" -Sev 'Info'

        try {
            $PasswordLink = New-PwPushLink -Payload $password
            if ($PasswordLink) {
                $password = $PasswordLink
            }
        } catch {

        }
        $Results = @{
            Results  = ('Created New User.')
            Username = $UserPrincipalName
            Password = $password
            User     = $GraphRequest
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create user. Error:$($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($UserObj.tenantFilter) -message "Failed to create user. Error:$($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Results = @{ Results = $Result }
        throw $Result
    }
    return $Results
}

