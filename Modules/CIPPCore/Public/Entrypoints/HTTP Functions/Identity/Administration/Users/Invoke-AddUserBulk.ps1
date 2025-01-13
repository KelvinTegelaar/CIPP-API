using namespace System.Net

Function Invoke-AddUserBulk {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = 'AddUserBulk'
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $TenantFilter = $Request.body.TenantFilter
    $Body = foreach ($userobj in $request.body.BulkUser) {
        if ($userobj.usageLocation.value) {
            $userobj.usageLocation = $userobj.usageLocation.value
        }
        try {
            $password = if ($userobj.password) { $userobj.password } else { New-passwordString }
            $UserprincipalName = "$($userobj.mailNickName)@$($userobj.domain)"
            $BodyToship = $userobj
            #Remove domain from body to ship
            $BodyToship = $BodyToship | Select-Object * -ExcludeProperty password, domain
            $BodyToship | Add-Member -NotePropertyName accountEnabled -NotePropertyValue $true -Force
            $BodyToship | Add-Member -NotePropertyName userPrincipalName -NotePropertyValue $UserprincipalName -Force
            $BodyToship | Add-Member -NotePropertyName passwordProfile -NotePropertyValue @{'password' = $password; 'forceChangePasswordNextSignIn' = $true } -Force
            Write-Host "body is now: $($BodyToship | ConvertTo-Json -Depth 10 -Compress)"
            if ($userobj.businessPhones) { $bodytoShip.businessPhones = @($userobj.businessPhones) }
            $bodyToShip = ConvertTo-Json -Depth 10 -InputObject $BodyToship -Compress
            Write-Host "Our body to ship is $bodyToShip"
            $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/users' -tenantid $TenantFilter -type POST -body $BodyToship
            Write-Host "Graph request is $GraphRequest"
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($TenantFilter) -message "Created user $($userobj.displayname) with id $($GraphRequest.id) " -Sev 'Info'

            #PWPush
            $PasswordLink = New-PwPushLink -Payload $password
            if ($PasswordLink) {
                $password = $PasswordLink
            }
            $results = "Created user $($UserprincipalName). Password is $password"

        } catch {
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($TenantFilter) -message "Failed to create user. Error:$($_.Exception.Message)" -Sev 'Error'
            $results = "Failed to create user $($UserprincipalName). $($_.Exception.Message)"
        }
        [PSCustomObject]@{
            'Results'  = $results
            'Username' = $UserprincipalName
            'Password' = $password
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Body)
        })

}
