using namespace System.Net

function Invoke-AddUserBulk {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = 'AddUserBulk'
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $TenantFilter = $Request.body.TenantFilter

    $BulkUsers = $Request.Body.BulkUser

    if (!$BulkUsers) {
        $Body = @{
            Results = @{
                resultText = 'No users specified to import'
                state      = 'error'
            }
        }
    } else {
        $BulkRequests = [System.Collections.Generic.List[object]]::new()
        $Results = [System.Collections.Generic.List[object]]::new()
        $Messages = [System.Collections.Generic.List[object]]::new()
        foreach ($User in $BulkUsers) {
            # User input validation
            $missingFields = [System.Collections.Generic.List[string]]::new()
            if (!$User.mailNickName) { $missingFields.Add('mailNickName') }
            if (!$User.domain) { $missingFields.Add('domain') }
            if (!$User.displayName -and !$User.givenName -and !$User.surname) { $missingFields.Add('displayName') }

            $Name = if ([string]::IsNullOrEmpty($User.displayName)) {
                '{0} {1}' -f $User.givenName, $User.surname
            } else {
                $User.displayName
            }

            # Check for missing required fields
            if ($missingFields.Count -gt 0) {
                $Results.Add(@{
                        resultText = "Required fields missing for $($User ?? 'No name specified'): $($missingFields -join ', ')"
                        state      = 'error'
                    })
            } else {
                # Create user body with required properties
                $Password = if ($User.password) { $User.password } else { New-passwordString }
                $UserBody = @{
                    accountEnabled    = $true
                    displayName       = $Name
                    mailNickName      = $User.mailNickName
                    userPrincipalName = '{0}@{1}' -f $User.mailNickName, $User.domain
                    passwordProfile   = @{
                        password                      = $Password
                        forceChangePasswordNextSignIn = $true
                    }
                }

                # Add optional properties if not null or empty
                if (![string]::IsNullOrEmpty($User.usageLocation)) {
                    $UserBody.usageLocation = $User.usageLocation.value ?? $User.usageLocation
                }

                # Convert businessPhones to array if not null or empty
                if (![string]::IsNullOrEmpty($User.businessPhones)) {
                    $UserBody.businessPhones = @($User.businessPhones)
                }

                # loop through rest of post body and add to user body if not null or empty or not already set in the user body
                foreach ($key in $User.PSObject.Properties.Name) {
                    if ($key -notin @('displayName', 'mailNickName', 'domain', 'password', 'usageLocation', 'businessPhones')) {
                        if (![string]::IsNullOrEmpty($User.$key) -and $UserBody.$key -eq $null) {
                            $UserBody.$key = $User.$key
                        }
                    }
                }

                # Build bulk request
                $BulkRequests.Add(@{
                        'id'      = $UserBody.userPrincipalName
                        'url'     = 'users'
                        'method'  = 'POST'
                        'body'    = $UserBody
                        'headers' = @{
                            'Content-Type' = 'application/json'
                        }
                    })

                # Create password link
                $PasswordLink = New-PwPushLink -Payload $password
                if ($PasswordLink) {
                    $password = $PasswordLink
                }

                # Set success messages
                $Messages.Add(@{
                        id         = $UserBody.userPrincipalName
                        resultText = "Created user for $($Name) with username $($UserBody.userPrincipalName)"
                        copyField  = $Password
                    })
            }
        }

        if ($BulkRequests.Count -gt 0) {
            Write-Warning "We have $($BulkRequests.Count) users to import"
            Write-Information ($BulkRequests | ConvertTo-Json -Depth 5)
            $BulkResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests $BulkRequests
            Write-Warning "We have $($BulkResults.Count) results"
            Write-Information ($BulkResults | ConvertTo-Json -Depth 10
            )
            foreach ($BulkResult in $BulkResults) {
                if ($BulkResult.status -ne 201) {
                    Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($TenantFilter) -message "Failed to create user $($BulkResult.id). Error:$($BulkResult.body.error.message)" -Sev 'Error'
                    $Results.Add(@{
                            resultText = "Failed to create user $($BulkResult.id). Error: $($BulkResult.body.error.message)"
                            state      = 'error'
                        })
                } else {
                    $Message = $Messages.Where({ $_.id -eq $BulkResult.id })
                    $Results.Add(@{
                            resultText = $Message.resultText
                            state      = 'success'
                            copyField  = $Message.copyField
                            username   = $BulkResult.body.userPrincipalName
                            id         = $BulkResult.id
                        })
                }
            }
        } else {
            $Results.Add(@{
                    resultText = 'No users to import'
                    state      = 'error'
                })
        }
        $Body = @{
            Results = @($Results)
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
