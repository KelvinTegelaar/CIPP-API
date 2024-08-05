function New-CIPPUser {
    [CmdletBinding()]
    param (
        $userobj,
        $Aliases = 'Scheduled',
        $RestoreValues,
        $APIName = 'New User',
        $ExecutingUser
    )

    try {
        $Aliases = ($UserObj.AddedAliases) -split '\s'
        $password = if ($UserObj.password) { $UserObj.password } else { New-passwordString }
        $UserprincipalName = "$($UserObj.Username)@$($UserObj.Domain)"
        $BodyToship = [pscustomobject] @{
            'givenName'         = $UserObj.FirstName
            'surname'           = $UserObj.LastName
            'accountEnabled'    = $true
            'displayName'       = $UserObj.DisplayName
            'department'        = $UserObj.Department
            'mailNickname'      = $UserObj.Username
            'userPrincipalName' = $UserprincipalName
            'usageLocation'     = $UserObj.usageLocation
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
        if ($userobj.businessPhone) { $bodytoShip | Add-Member -NotePropertyName businessPhones -NotePropertyValue @($UserObj.businessPhone) }
        if ($UserObj.addedAttributes) {
            Write-Host 'Found added attribute'
            Write-Host "Added attributes: $($UserObj.addedAttributes | ConvertTo-Json)"
            $UserObj.addedAttributes.GetEnumerator() | ForEach-Object {
                $results.add("Added property $($_.Key) with value $($_.value)")
                $bodytoShip | Add-Member -NotePropertyName $_.Key -NotePropertyValue $_.Value
            }
        }
        $bodyToShip = ConvertTo-Json -Depth 10 -InputObject $BodyToship -Compress
        $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/users' -tenantid $UserObj.tenantID -type POST -body $BodyToship -verbose
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($UserObj.tenantID) -message "Created user $($UserObj.displayname) with id $($GraphRequest.id) " -Sev 'Info'

        try {
            $PasswordLink = New-PwPushLink -Payload $password
            if ($PasswordLink) {
                $password = $PasswordLink
            }
        } catch {

        }
        $Results = @{
            Results  = ('Created New User.')
            Username = $UserprincipalName
            Password = $password
        }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($UserObj.tenantID) -message "Failed to create user. Error:$($_.Exception.Message)" -Sev 'Error'
        $results = @{ Results = ("Failed to create user. $($_.Exception.Message)" ) }
        throw "Failed to create user  $($_.Exception.Message)"
    }
    return $Results
}

