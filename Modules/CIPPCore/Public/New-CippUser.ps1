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
            'department'        = $UserObj.Department
            'mailNickname'      = $UserObj.Username ? $UserObj.username : $UserObj.mailNickname
            'userPrincipalName' = $UserPrincipalName
            'usageLocation'     = $UserObj.usageLocation.value ? $UserObj.usageLocation.value : $UserObj.usageLocation
            'city'              = $UserObj.City
            'country'           = $UserObj.Country
            'jobtitle'          = $UserObj.Jobtitle
            'mobilePhone'       = $UserObj.MobilePhone
            'streetAddress'     = $UserObj.streetAddress
            'postalCode'        = $UserObj.PostalCode
            'companyName'       = $UserObj.CompanyName
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

