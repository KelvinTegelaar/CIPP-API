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
        $userobj = $userobj | ConvertTo-Json -Depth 10 | ConvertFrom-Json -Depth 10
        Write-Host $UserObj.PrimDomain.value
        $Aliases = ($UserObj.AddedAliases) -split '\s'
        $password = if ($UserObj.password) { $UserObj.password } else { New-passwordString }
        $UserprincipalName = "$($UserObj.Username ? $userobj.username :$userobj.mailNickname )@$($UserObj.Domain ? $UserObj.Domain : $UserObj.PrimDomain.value)"
        Write-Host "Creating user $UserprincipalName"
        Write-Host "tenant filter is $($UserObj.tenantFilter)"
        $BodyToship = [pscustomobject] @{
            'givenName'         = $UserObj.givenname
            'surname'           = $UserObj.surname
            'accountEnabled'    = $true
            'displayName'       = $UserObj.displayName
            'department'        = $UserObj.Department
            'mailNickname'      = $UserObj.Username ? $userobj.username :$userobj.mailNickname
            'userPrincipalName' = $UserprincipalName
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
        if ($userobj.businessPhone) { $bodytoShip | Add-Member -NotePropertyName businessPhones -NotePropertyValue @($UserObj.businessPhone) }
        if ($UserObj.defaultAttributes.value) {
            [hashtable]($UserObj.defaultAttributes).GetEnumerator() | ForEach-Object {
                $results.add("Added property $($_.Key) with value $($_.value)")
                $bodytoShip | Add-Member -NotePropertyName $_.Key -NotePropertyValue $_.Value
            }
        }
        $bodyToShip = ConvertTo-Json -Depth 10 -InputObject $BodyToship -Compress
        Write-Host "Shipping: $bodyToShip"
        $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/users' -tenantId $UserObj.tenantFilter -type POST -body $BodyToship -verbose
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($UserObj.tenantFilter) -message "Created user $($UserObj.displayname) with id $($GraphRequest.id) " -Sev 'Info'

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
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($UserObj.tenantFilter) -message "Failed to create user. Error:$($_.Exception.Message)" -Sev 'Error'
        $results = @{ Results = ("Failed to create user. $($_.Exception.Message)" ) }
        throw "Failed to create user  $($_.Exception.Message)"
    }
    return $Results
}

